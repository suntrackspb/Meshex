import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sticker_providers.dart';
import '../../core/stickers/wire_codec.dart';
import '../../data/stickers/source_client.dart';
import '../../data/stickers/sticker_http.dart';
import '../../l10n/l10n.dart';
import 'sticker_library_page.dart';

/// An incoming reference is not network permission. Opening this page is local;
/// fetching metadata and trusting/installing the source are separate actions.
class StickerOfferPage extends ConsumerStatefulWidget {
  const StickerOfferPage({super.key, required this.envelope});
  final StickerEnvelope envelope;
  @override
  ConsumerState<StickerOfferPage> createState() => _StickerOfferPageState();
}

class _StickerOfferPageState extends ConsumerState<StickerOfferPage> {
  late String _sourceUrl = widget.envelope.sourceUrl;
  StickerSourcePreview? _preview;
  StickerCancellation? _cancellation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(StickerCancellation) action) async {
    if (_busy) return;
    final cancellation = StickerCancellation();
    setState(() {
      _busy = true;
      _error = null;
      _cancellation = cancellation;
    });
    try {
      await action(cancellation);
    } on StickerCancelled {
      /* Back/cancel does not grant trust or show an error. */
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
        _error = switch (e.message) {
          'Sticker source is blocked' ||
          'Sticker source is disabled or blocked' =>
            context.l10n.stickerSendingBlocked,
          'Sticker revision is withdrawn' => context.l10n.stickerWithdrawn,
          'Sticker storage quota exceeded' => context.l10n.stickerQuotaExceeded,
          _ => context.l10n.stickerOperationFailed,
        };
      }
    } catch (_) {
      if (mounted) _error = context.l10n.stickerOperationFailed;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _cancellation = null;
        });
      }
    }
  }

  Future<void> _open() => _run((token) async {
    final preview = await ref
        .read(stickerSourceClientProvider)
        .preview(
          _sourceUrl,
          widget.envelope.packSha256,
          userConsent: true,
          cancellation: token,
        );
    if (mounted) setState(() => _preview = preview);
  });

  Future<void> _install(bool addSource) => _run((token) async {
    if (_preview == null ||
        !_preview!.manifest.stickers.any(
          (s) => s.id == widget.envelope.stickerId,
        )) {
      return;
    }
    final repository = ref.read(stickerSourceRepositoryProvider);
    final known =
        (await repository
                .watchSources(
                  currentMirror: ref
                      .read(stickerSourceClientProvider)
                      .currentMirror(),
                )
                .first)
            .where((s) => s.url == _sourceUrl)
            .firstOrNull;
    if (known?.record.blocked == true) {
      throw StateError('Sticker source is blocked');
    }
    token.check();
    // The label explicitly asks for permanent addition if not already active.
    if (addSource) {
      await repository.addManual(_sourceUrl);
    } else if (known?.active != true) {
      throw StateError('Sticker source is disabled or blocked');
    }
    await ref
        .read(stickerPackRepositoryProvider)
        .install(_sourceUrl, widget.envelope.packSha256, cancellation: token);
    if (mounted) Navigator.pop(context);
  });

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(stickerLocalSourcesProvider);
    // This is a local-only subscription: the page itself must never prefetch.
    ref.watch(installedStickersProvider);
    final known = sources.value?.where((s) => s.url == _sourceUrl).firstOrNull;
    final blocked = known?.record.blocked == true;
    final alternatives =
        sources.value
            ?.where(
              (s) =>
                  s.url != widget.envelope.sourceUrl &&
                  s.active &&
                  s.catalog?.revisions.any(
                        (r) =>
                            r.packSha256 == widget.envelope.packSha256 &&
                            r.canInstall,
                      ) ==
                      true,
            )
            .toList() ??
        [];
    final manifest = _preview?.manifest;
    final hasSticker =
        manifest?.stickers.any((s) => s.id == widget.envelope.stickerId) ==
        true;
    final progress = ref.watch(stickerInstallProgressProvider).value;
    final strings = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(strings.stickerSourceAndPack)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              Uri.parse(_sourceUrl).host,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText(_sourceUrl),
            const SizedBox(height: 12),
            Text(
              '${strings.stickerRevision} ${widget.envelope.packSha256.substring(0, 12)}',
            ),
            const SizedBox(height: 12),
            Text(strings.stickerSourceConsent),
            if (alternatives.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(strings.stickerTrustedCopy),
              DropdownButtonFormField<String>(
                key: ValueKey(_sourceUrl),
                initialValue: _sourceUrl,
                isExpanded: true,
                items:
                    {
                          widget.envelope.sourceUrl,
                          _sourceUrl,
                          ...alternatives.map((s) => s.url),
                        }
                        .map(
                          (url) => DropdownMenuItem(
                            value: url,
                            child: Text(
                              Uri.parse(url).host,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: _busy
                    ? null
                    : (url) {
                        if (url != null) {
                          setState(() {
                            _sourceUrl = url;
                            _preview = null;
                            _error = null;
                          });
                        }
                      },
              ),
            ],
            const SizedBox(height: 16),
            if (sources.hasError)
              Text(strings.stickerLoadFailed)
            else if (blocked) ...[
              Text(strings.stickerSendingBlocked),
              TextButton(
                onPressed: () => showStickerLibrary(context),
                child: Text(strings.stickerManagePacks),
              ),
            ] else if (manifest == null && !_busy)
              FilledButton(
                onPressed: sources.isLoading ? null : _open,
                child: Text(strings.stickerOpenSource),
              ),
            if (_busy) ...[
              LinearProgressIndicator(
                value: progress?.hash == widget.envelope.packSha256
                    ? progress!.completedBytes / progress.totalBytes
                    : null,
              ),
              TextButton(
                onPressed: () => _cancellation?.cancel(),
                child: Text(strings.cancel_0ec753),
              ),
            ],
            if (manifest != null) ...[
              const Divider(height: 32),
              Text(
                manifest.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('${strings.stickerRevision} ${manifest.revision}'),
              if (manifest.authors.isNotEmpty)
                Text(manifest.authors.join(', ')),
              Text(manifest.licenseId ?? strings.stickerLicenseUnknown),
              if (manifest.licenseUrl != null)
                SelectableText('${manifest.licenseUrl}'),
              if (manifest.attributionUrl != null)
                SelectableText('${manifest.attributionUrl}'),
              Text(
                '${manifest.stickers.length} · ${(manifest.downloadBytes / 1024).toStringAsFixed(1)} KB',
              ),
              const SizedBox(height: 12),
              Text(_preview!.descriptor.operatorName),
              SelectableText(_preview!.descriptor.operatorContact),
              const SizedBox(height: 12),
              SelectableText(manifest.packSha256),
              if (!hasSticker)
                Text(strings.stickerMissingId)
              else if (!blocked && !sources.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _install(known?.active != true),
                    child: Text(
                      known?.active == true
                          ? strings.stickerInstallExact
                          : strings.stickerAddAndInstall,
                    ),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
