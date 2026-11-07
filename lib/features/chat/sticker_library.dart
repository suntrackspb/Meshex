import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/sticker_providers.dart';
import '../../data/database.dart';
import '../../data/sticker_store.dart';
import '../../data/stickers.dart';
import '../../l10n/l10n.dart';

Future<void> showStickerLibrary(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const StickerLibrary(),
    );

class StickerLibrary extends ConsumerStatefulWidget {
  const StickerLibrary({super.key});

  @override
  ConsumerState<StickerLibrary> createState() => _StickerLibraryState();
}

class _StickerLibraryState extends ConsumerState<StickerLibrary> {
  String? _selected;
  bool _catalogTab = false;
  List<StickerPack>? _catalog;
  String? _loadedUrl;
  bool _loading = false;
  bool _failed = false;
  final _busy = <String>{};
  String? _operationError;

  Future<void> _load({String? url}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final address =
          url ?? (await ref.read(stickerCatalogUrlProvider.future)) ?? '';
      if (address.isEmpty) {
        if (mounted) {
          setState(() {
            _catalog = null;
            _loadedUrl = '';
          });
        }
        return;
      }
      final packs = await ref.read(stickerStoreProvider).catalog(address);
      if (mounted) {
        setState(() {
          _catalog = packs;
          _loadedUrl = address;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configure() async {
    final controller = TextEditingController(
      text: ref.read(stickerCatalogUrlProvider).value ?? '',
    );
    final strings = context.l10n;
    final form = GlobalKey<FormState>();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.stickerServer),
        content: Form(
          key: form,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: strings.stickerCatalogAddress,
              hintText: 'https://…/catalog.json',
            ),
            validator: (text) {
              if (text?.trim().isEmpty ?? true) return null;
              try {
                StickerStore.catalogUri(text!);
                return null;
              } catch (_) {
                return strings.stickerInvalidUrl;
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.cancel_0ec753),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text(strings.stickerSave),
          ),
        ],
      ),
    );
    // The route's closing animation may still be using the controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (url == null || !mounted) return;
    await ref
        .read(appDatabaseProvider)
        .setSetting(AppSettingKeys.stickerCatalogUrl, url);
    if (!mounted) return;
    setState(() {
      _catalogTab = true;
      _catalog = null;
      _loadedUrl = null;
    });
    await _load(url: url);
  }

  Future<void> _install(StickerPack pack) async {
    if (!_busy.add(pack.id)) return;
    setState(() => _operationError = null);
    try {
      await ref.read(stickerStoreProvider).install(pack);
    } catch (_) {
      if (mounted) {
        setState(() => _operationError = context.l10n.stickerDownloadFailed);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(pack.id));
    }
  }

  Future<void> _remove(StickerPack pack) async {
    if (!_busy.add(pack.id)) return;
    setState(() => _operationError = null);
    try {
      await ref.read(stickerStoreProvider).remove(pack.id);
    } catch (_) {
      if (mounted) {
        setState(() => _operationError = context.l10n.stickerRemoveFailed);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(pack.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.l10n;
    final installed = ref.watch(installedStickersProvider);
    final url = ref.watch(stickerCatalogUrlProvider).value ?? '';
    final store = ref.watch(stickerStoreProvider);
    final packs = installed.value ?? const <StickerPack>[];
    final selected =
        packs.where((p) => p.id == _selected).firstOrNull ?? packs.firstOrNull;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.stickersTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: strings.stickerServer,
                    onPressed: _configure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(strings.stickerMyPacks),
                    selected: !_catalogTab,
                    onSelected: (_) => setState(() => _catalogTab = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(strings.stickerCatalog),
                    selected: _catalogTab,
                    onSelected: (_) {
                      setState(() => _catalogTab = true);
                      if (_catalog == null || _loadedUrl != url) _load();
                    },
                  ),
                  const Spacer(),
                  if (_catalogTab)
                    IconButton(
                      tooltip: strings.stickerRefresh,
                      onPressed: _loading ? null : () => _load(),
                      icon: const Icon(Icons.refresh),
                    ),
                ],
              ),
            ),
            if (_operationError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _operationError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_catalogTab)
              Expanded(child: _catalogBody(store, url))
            else if (installed.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (installed.hasError)
              Expanded(child: Center(child: Text(strings.stickerLoadFailed)))
            else if (selected == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          strings.stickerNoInstalled,
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _catalogTab = true);
                            _load();
                          },
                          child: Text(strings.stickerCatalog),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final pack in packs)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: selected.id == pack.id,
                          label: Text(
                            '${pack.title} · ${pack.stickers.length}',
                          ),
                          onSelected: (_) =>
                              setState(() => _selected = pack.id),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.stickerPreviewHint,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: strings.stickerRemove,
                      onPressed: _busy.contains(selected.id)
                          ? null
                          : () => _remove(selected),
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  key: ValueKey(selected.id),
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 112,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: selected.stickers.length,
                  itemBuilder: (context, index) {
                    final sticker = selected.stickers[index];
                    final label =
                        '${strings.stickerLabel} ${sticker.emoji}, ${selected.title}, ${sticker.ref.id}';
                    return Semantics(
                      label: label,
                      button: true,
                      child: Tooltip(
                        message: label,
                        child: Material(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _preview(sticker),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: StickerImage(sticker: sticker),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _preview(StickerAsset sticker) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${context.l10n.stickerLabel} ${sticker.emoji}'),
        content: SizedBox.square(
          dimension: 240,
          child: StickerImage(sticker: sticker),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  Widget _catalogBody(StickerStore store, String url) {
    final strings = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (url.isEmpty && _catalog == null && !_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.stickerConfigureHint, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _configure,
                child: Text(strings.stickerServer),
              ),
            ],
          ),
        ),
      );
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.stickerLoadFailed),
            TextButton(
              onPressed: () => _load(),
              child: Text(strings.stickerRefresh),
            ),
          ],
        ),
      );
    }
    final catalog = _catalog ?? const <StickerPack>[];
    final packs = catalog;
    if (packs.isEmpty) return Center(child: Text(strings.stickerCatalogEmpty));
    return ListView.builder(
      itemCount: packs.length,
      itemBuilder: (context, i) {
        final pack = packs[i];
        final installed = store.contains(pack.id);
        return ListTile(
          leading: Icon(
            pack.animated
                ? Icons.play_circle_outline
                : Icons.sticky_note_2_outlined,
          ),
          title: Text('${pack.title} · ${pack.stickers.length}'),
          subtitle: Text(
            [
              if (pack.author?.isNotEmpty == true) pack.author!,
              pack.license?.isNotEmpty == true
                  ? pack.license!
                  : strings.stickerLicenseUnknown,
              if (pack.source?.isNotEmpty == true) pack.source!,
              '${(pack.bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
            ].join('\n'),
          ),
          isThreeLine: true,
          trailing: _busy.contains(pack.id)
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : installed
              ? Tooltip(
                  message: strings.stickerInstalled,
                  child: const Icon(Icons.check_circle_outline),
                )
              : IconButton(
                  tooltip: strings.stickerDownload,
                  onPressed: () => _install(pack),
                  icon: const Icon(Icons.download_outlined),
                ),
        );
      },
    );
  }
}

class StickerImage extends ConsumerWidget {
  const StickerImage({super.key, required this.sticker});
  final StickerAsset sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(stickerStoreProvider);
    final still = sticker.animated && MediaQuery.disableAnimationsOf(context);
    return Image.file(
      store.file(sticker, still: still),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }
}
