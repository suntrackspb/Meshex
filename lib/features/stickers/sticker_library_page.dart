import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/sticker_providers.dart';
import '../../core/stickers/wire_codec.dart';
import '../../data/database.dart';
import '../../data/stickers/pack_repository.dart';
import '../../data/stickers/source_models.dart';
import '../../data/stickers/source_repository.dart';
import '../../data/stickers/sticker_http.dart';
import '../../l10n/l10n.dart';

Future<void> showStickerLibrary(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push<void>(MaterialPageRoute(builder: (_) => const StickerLibraryPage()));

class StickerLibraryPage extends ConsumerStatefulWidget {
  const StickerLibraryPage({super.key});
  @override
  ConsumerState<StickerLibraryPage> createState() => _StickerLibraryPageState();
}

class _StickerLibraryPageState extends ConsumerState<StickerLibraryPage> {
  final _busy = <String>{};
  final _tokens = <String, StickerCancellation>{};
  int _tab = 0;
  String? _error;

  Future<void> _run(String key, Future<void> Function() action) async {
    if (!_busy.add(key)) return;
    setState(() => _error = null);
    try {
      await action();
    } on StickerCancelled {
      /* Cancellation is a normal user action. */
    } on FormatException {
      if (mounted) _error = context.l10n.stickerInvalidData;
    } on StickerHttpException catch (e) {
      if (mounted) {
        _error = e.statusCode == 410
            ? context.l10n.stickerWithdrawn
            : context.l10n.stickerOperationFailed;
      }
    } on StateError catch (e) {
      if (mounted) {
        _error = e.message == 'Sticker storage quota exceeded'
            ? context.l10n.stickerQuotaExceeded
            : e.message == 'Sticker revision is withdrawn'
            ? context.l10n.stickerWithdrawn
            : context.l10n.stickerOperationFailed;
      }
    } catch (_) {
      if (mounted) _error = context.l10n.stickerOperationFailed;
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel_0ec753),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(title),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addSource() async {
    final controller = TextEditingController();
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.stickerAddSource),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.l10n.stickerSourceAddress,
              hintText: 'https://…/source.json',
            ),
            validator: (input) {
              try {
                normalizeSourceUrl(input ?? '');
                return null;
              } catch (_) {
                return context.l10n.stickerInvalidUrl;
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel_0ec753),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: Text(context.l10n.stickerAddSource),
          ),
        ],
      ),
    );
    // Dispose after the dialog's reverse transition has stopped using the field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (value != null && mounted) {
      await _run(
        'add',
        () => ref.read(stickerSourceRepositoryProvider).addManual(value),
      );
    }
  }

  Future<void> _quota(int quota, int used) async {
    final controller = TextEditingController(text: '${quota ~/ (1024 * 1024)}');
    final form = GlobalKey<FormState>();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.stickerQuota),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n != null && n > 0 && n <= 4096 && n * 1024 * 1024 >= used
                  ? null
                  : context.l10n.stickerQuotaExceeded;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel_0ec753),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, int.parse(controller.text) * 1024 * 1024);
              }
            },
            child: Text(context.l10n.stickerSave),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (value != null && mounted) {
      await _run(
        'quota',
        () => ref
            .read(appDatabaseProvider)
            .setSetting(AppSettingKeys.stickerQuotaBytes, '$value'),
      );
    }
  }

  String _status(StickerSourceStatus status) => switch (status) {
    StickerSourceStatus.unchecked => context.l10n.stickerUnchecked,
    StickerSourceStatus.ready => context.l10n.stickerReady,
    StickerSourceStatus.offline => context.l10n.stickerOffline,
    StickerSourceStatus.incompatible => context.l10n.stickerIncompatible,
    StickerSourceStatus.invalid => context.l10n.stickerInvalid,
  };

  String _size(int bytes) => bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(stickerSourcesProvider);
    final installed = ref.watch(installedStickersProvider);
    final progress = ref.watch(stickerInstallProgressProvider).value;
    final quota =
        ref.watch(stickerQuotaProvider).value ??
        StickerPackRepository.defaultQuotaBytes;
    final used =
        installed.value?.fold(
          0,
          (n, p) => n + p.manifest.downloadBytes + p.manifest.bytes.length,
        ) ??
        0;
    final strings = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.stickersTitle),
        actions: [
          IconButton(
            tooltip: strings.stickerQuota,
            onPressed: () => _quota(quota, used),
            icon: const Icon(Icons.storage_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (index, label) in [
                    strings.stickerMyPacks,
                    strings.stickerCatalogs,
                    strings.stickerSources,
                  ].indexed)
                    ChoiceChip(
                      label: Text(label),
                      selected: _tab == index,
                      onSelected: (_) => setState(() => _tab = index),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Text(
                '${_size(used)} / ${_size(quota)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _tab == 0
                  ? installed.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) =>
                          Center(child: Text(strings.stickerLoadFailed)),
                      data: (packs) => packs.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  strings.stickerNoInstalled,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final pack in packs) _installedPack(pack),
                              ],
                            ),
                    )
                  : sources.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) =>
                          Center(child: Text(strings.stickerLoadFailed)),
                      data: (items) => _tab == 2
                          ? _sources(items)
                          : _catalogs(items, progress),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sources(List<StickerSourceState> sources) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(context.l10n.stickerSourceHint),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy.contains('add') ? null : _addSource,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.stickerAddSource),
        ),
      ),
      for (final source in sources)
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                ListTile(
                  title: Text(source.name),
                  subtitle: Text('${source.url}\n${_status(source.status)}'),
                  trailing: IconButton(
                    tooltip: context.l10n.stickerDeleteSource,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await _confirm(
                            context.l10n.stickerDeleteSource,
                            context.l10n.stickerDeleteSourceHint,
                          ) &&
                          mounted) {
                        await _run(
                          source.url,
                          () => ref
                              .read(stickerSourceRepositoryProvider)
                              .remove(source.url),
                        );
                      }
                    },
                  ),
                ),
                if (source.announcedByCurrentMirror)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      source.cachedAnnouncement
                          ? context.l10n.stickerCachedSource
                          : context.l10n.stickerMirrorSource,
                    ),
                  )
                else if (source.bindings.isNotEmpty)
                  Text(context.l10n.stickerFormerSource),
                SwitchListTile(
                  title: Text(context.l10n.stickerSourceEnabled),
                  value: source.record.manualEnabled,
                  onChanged: (value) => _run(
                    source.url,
                    () => ref
                        .read(stickerSourceRepositoryProvider)
                        .setManualEnabled(source.url, value),
                  ),
                ),
                SwitchListTile(
                  title: Text(context.l10n.stickerSourceBlocked),
                  value: source.record.blocked,
                  onChanged: (value) => _run(
                    source.url,
                    () => ref
                        .read(stickerSourceRepositoryProvider)
                        .setBlocked(source.url, value),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _catalogs(
    List<StickerSourceState> sources,
    StickerInstallProgress? progress,
  ) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (sources.isEmpty)
        ListTile(
          title: Text(context.l10n.stickerNoSources),
          subtitle: Text(context.l10n.stickerSourceHint),
          trailing: IconButton(
            tooltip: context.l10n.stickerAddSource,
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => _tab = 2),
          ),
        ),
      for (final source in sources) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(source.name),
          subtitle: Text(
            source.active
                ? _status(source.status)
                : context.l10n.stickerSourceDisabled,
          ),
          trailing: _busy.contains(source.url)
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(),
                )
              : IconButton(
                  tooltip: context.l10n.stickerRefresh,
                  onPressed: source.active
                      ? () => _run(
                          source.url,
                          () => ref
                              .read(stickerSourceClientProvider)
                              .refresh(source.url),
                        )
                      : null,
                  icon: const Icon(Icons.refresh),
                ),
        ),
        if (source.catalog == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(context.l10n.stickerRefreshFirst),
          ),
        for (final revision in source.catalog?.revisions ?? <StickerRevision>[])
          Card(
            child: ListTile(
              title: Text(revision.title),
              subtitle: Text(
                '${context.l10n.stickerRevision} ${revision.revision}\n${revision.stickerCount} · ${_size(revision.downloadBytes)}',
              ),
              onTap: () => _preview(source, revision),
              trailing: _busy.contains(revision.packSha256)
                  ? SizedBox(
                      width: 48,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            value: progress?.hash == revision.packSha256
                                ? progress!.completedBytes / progress.totalBytes
                                : null,
                          ),
                          IconButton(
                            tooltip: context.l10n.cancel_0ec753,
                            onPressed: () {
                              _tokens[revision.packSha256]?.cancel();
                              ref
                                  .read(stickerPackRepositoryProvider)
                                  .cancel(revision.packSha256);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    )
                  : ref
                        .read(stickerPackRepositoryProvider)
                        .contains(revision.packSha256)
                  ? Icon(
                      Icons.check_circle_outline,
                      semanticLabel: context.l10n.stickerInstalled,
                    )
                  : IconButton(
                      tooltip: context.l10n.stickerDownload,
                      icon: const Icon(Icons.download_outlined),
                      onPressed: source.active && revision.canInstall
                          ? () => _preview(source, revision)
                          : null,
                    ),
            ),
          ),
      ],
    ],
  );

  Future<void> _preview(StickerSourceState source, StickerRevision revision) =>
      _run(revision.packSha256, () async {
        if (!source.active || !revision.canInstall) {
          throw StateError('Sticker source is disabled or blocked');
        }
        final token = StickerCancellation();
        _tokens[revision.packSha256] = token;
        try {
          final preview = await ref
              .read(stickerSourceClientProvider)
              .preview(
                source.url,
                revision.packSha256,
                userConsent: true,
                cancellation: token,
              );
          if (!mounted) return;
          final install = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(preview.manifest.title),
              content: SingleChildScrollView(
                child: _metadata(preview.manifest, source.url),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.l10n.cancel_0ec753),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.l10n.stickerDownload),
                ),
              ],
            ),
          );
          if (install == true && mounted) {
            await ref
                .read(stickerPackRepositoryProvider)
                .install(source.url, revision.packSha256, cancellation: token);
          }
        } finally {
          _tokens.remove(revision.packSha256);
        }
      });

  Widget _metadata(StickerManifest manifest, String sourceUrl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (manifest.authors.isNotEmpty) Text(manifest.authors.join(', ')),
      Text(manifest.licenseId ?? context.l10n.stickerLicenseUnknown),
      if (manifest.licenseUrl != null) SelectableText('${manifest.licenseUrl}'),
      if (manifest.attributionUrl != null)
        SelectableText('${manifest.attributionUrl}'),
      Text('${manifest.stickers.length} · ${_size(manifest.downloadBytes)}'),
      Text('${context.l10n.stickerRevision} ${manifest.revision}'),
      const SizedBox(height: 8),
      SelectableText(sourceUrl),
      const SizedBox(height: 8),
      SelectableText(manifest.packSha256),
    ],
  );

  Widget _originPicker(InstalledStickerPack pack) {
    final sources = ref.watch(stickerLocalSourcesProvider);
    bool blocked(String url) =>
        sources.value?.any((s) => s.url == url && s.record.blocked) == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pack.origins.length > 1)
            DropdownButtonFormField<String>(
              key: ValueKey('${pack.hash}:${pack.preferredSourceUrl}'),
              initialValue: pack.preferredSourceUrl,
              decoration: InputDecoration(
                labelText: context.l10n.stickerSourceForSending,
              ),
              isExpanded: true,
              items: [
                for (final url in pack.origins)
                  DropdownMenuItem(
                    value: url,
                    enabled: !blocked(url),
                    child: Text(url, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged:
                  _busy.contains(pack.hash) ||
                      !sources.hasValue ||
                      sources.hasError
                  ? null
                  : (url) {
                      if (url != null) {
                        _run(
                          pack.hash,
                          () => ref
                              .read(stickerPackRepositoryProvider)
                              .setPreferredSource(pack.hash, url),
                        );
                      }
                    },
            ),
          if (blocked(pack.preferredSourceUrl))
            Text(context.l10n.stickerSendingBlocked),
        ],
      ),
    );
  }

  Widget _installedPack(InstalledStickerPack pack) => ExpansionTile(
    key: ValueKey(pack.hash),
    title: Text(pack.manifest.title),
    subtitle: Text(
      '${context.l10n.stickerRevision} ${pack.manifest.revision} · ${_size(pack.manifest.downloadBytes)}',
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                [
                  if (pack.manifest.authors.isNotEmpty)
                    pack.manifest.authors.join(', '),
                  pack.manifest.licenseId ?? context.l10n.stickerLicenseUnknown,
                ].join('\n'),
              ),
            ),
            IconButton(
              tooltip: context.l10n.stickerDetails,
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(pack.manifest.title),
                  content: SingleChildScrollView(
                    child: _metadata(pack.manifest, pack.preferredSourceUrl),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        MaterialLocalizations.of(context).closeButtonLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _originPicker(pack),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 112,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: pack.manifest.stickers.length,
        itemBuilder: (context, index) {
          final sticker = pack.manifest.stickers[index];
          return Semantics(
            label: sticker.alt,
            button: true,
            child: Tooltip(
              message: sticker.alt,
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(sticker.alt),
                    content: SizedBox.square(
                      dimension: 240,
                      child: StickerImage(hash: pack.hash, sticker: sticker),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          MaterialLocalizations.of(context).closeButtonLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: StickerImage(
                    hash: pack.hash,
                    sticker: sticker,
                    still: true,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: Text(context.l10n.stickerRemove),
          onPressed: _busy.contains(pack.hash)
              ? null
              : () async {
                  if (await _confirm(
                        context.l10n.stickerRemove,
                        context.l10n.stickerRemoveConfirm,
                      ) &&
                      mounted) {
                    await _run(
                      pack.hash,
                      () => ref
                          .read(stickerPackRepositoryProvider)
                          .remove(pack.hash),
                    );
                  }
                },
        ),
      ),
    ],
  );
}

class StickerImage extends ConsumerWidget {
  const StickerImage({
    super.key,
    required this.hash,
    required this.sticker,
    this.still = false,
  });
  final String hash;
  final StickerManifestEntry sticker;
  final bool still;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Image.file(
    ref
        .watch(stickerPackRepositoryProvider)
        .file(
          hash,
          sticker,
          still: still || MediaQuery.disableAnimationsOf(context),
        ),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (context, _, _) => Tooltip(
      message: context.l10n.stickerLocalError,
      child: Icon(
        Icons.broken_image_outlined,
        semanticLabel: context.l10n.stickerLocalError,
      ),
    ),
  );
}
