import 'dart:convert';

import '../../core/stickers/wire_codec.dart';
import 'source_models.dart';
import 'source_repository.dart';
import 'sticker_http.dart';

class StickerSourcePreview {
  const StickerSourcePreview(this.sourceUrl, this.descriptor, this.manifest);
  final String sourceUrl;
  final StickerSourceDescriptor descriptor;
  final StickerManifest manifest;
}

class StickerSourceClient {
  StickerSourceClient(this.sources, this.http, {required this.currentMirror});
  final StickerSourceRepository sources;
  final StickerHttp http;
  final Uri? Function() currentMirror;

  Future<StickerSourceState> requireAllowed(String sourceUrl) async {
    final state =
        (await sources.watchSources(currentMirror: currentMirror()).first)
            .where((s) => s.url == sourceUrl)
            .firstOrNull;
    if (state == null || !state.active) {
      throw StateError('Sticker source is disabled or blocked');
    }
    return state;
  }

  Future<void> refresh(
    String sourceUrl, {
    StickerCancellation? cancellation,
  }) async {
    final state = await requireAllowed(sourceUrl);
    try {
      final source = validateSourceUrl(sourceUrl);
      final descriptor = await http.fetch(
        source,
        sourceUrl: sourceUrl,
        limit: 64 * 1024,
        contentType: 'application/json',
        etag: state.descriptor == null ? null : state.record.descriptorEtag,
        cancellation: cancellation,
      );
      final descriptorBytes = descriptor.notModified
          ? utf8.encode(state.record.descriptorJson!)
          : descriptor.bytes;
      final parsed = StickerSourceDescriptor.parse(
        descriptorBytes,
        sourceUrl: sourceUrl,
      );
      await requireAllowed(sourceUrl);
      final catalog = await http.fetch(
        parsed.catalogUrl,
        sourceUrl: sourceUrl,
        limit: 1024 * 1024,
        contentType: 'application/json',
        etag: state.catalog == null ? null : state.record.catalogEtag,
        cancellation: cancellation,
      );
      final catalogBytes = catalog.notModified
          ? utf8.encode(state.record.catalogJson!)
          : catalog.bytes;
      await requireAllowed(sourceUrl);
      cancellation?.check();
      await sources.cacheSnapshot(
        sourceUrl: sourceUrl,
        descriptorBytes: descriptorBytes,
        catalogBytes: catalogBytes,
        descriptorEtag: descriptor.etag,
        catalogEtag: catalog.etag,
      );
    } on StickerCancelled {
      rethrow;
    } on StickerSchemaException {
      await sources.markFailure(sourceUrl, StickerSourceStatus.incompatible);
      rethrow;
    } on FormatException {
      await sources.markFailure(sourceUrl, StickerSourceStatus.invalid);
      rethrow;
    } on Object {
      await sources.markFailure(sourceUrl, StickerSourceStatus.offline);
      rethrow;
    }
  }

  /// Explicit user action only. Preview does not register an unknown source.
  Future<StickerSourcePreview> preview(
    String sourceUrl,
    String hash, {
    required bool userConsent,
    StickerCancellation? cancellation,
  }) async {
    if (!userConsent) throw StateError('Source preview requires consent');
    validateSourceUrl(sourceUrl);
    stickerHash(hash);
    Future<void> checkBlocked() async {
      cancellation?.check();
      final known =
          (await sources.watchSources(currentMirror: currentMirror()).first)
              .where((s) => s.url == sourceUrl)
              .firstOrNull;
      if (known?.record.blocked == true) {
        throw StateError('Sticker source is blocked');
      }
      final cachedRevision = known?.catalog?.revisions
          .where((r) => r.packSha256 == hash)
          .firstOrNull;
      if (cachedRevision != null && !cachedRevision.canInstall) {
        throw StateError('Sticker revision is withdrawn');
      }
    }

    await checkBlocked();
    final descriptor = await http.fetch(
      Uri.parse(sourceUrl),
      sourceUrl: sourceUrl,
      limit: 64 * 1024,
      contentType: 'application/json',
      cancellation: cancellation,
    );
    final parsed = StickerSourceDescriptor.parse(
      descriptor.bytes,
      sourceUrl: sourceUrl,
    );
    // Catalog is checked for an explicit withdrawal; an unlisted immutable
    // revision remains installable. 404 for the catalog is not a withdrawal.
    await checkBlocked();
    try {
      final catalog = await http.fetch(
        parsed.catalogUrl,
        sourceUrl: sourceUrl,
        limit: 1024 * 1024,
        contentType: 'application/json',
        cancellation: cancellation,
      );
      final revision = StickerSourceCatalog.parse(
        catalog.bytes,
      ).revisions.where((r) => r.packSha256 == hash).firstOrNull;
      if (revision != null && !revision.canInstall) {
        throw StateError('Sticker revision is withdrawn');
      }
    } on StickerHttpException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    await checkBlocked();
    final manifest = await http.fetch(
      parsed.manifestUrl(hash),
      sourceUrl: sourceUrl,
      limit: 256 * 1024,
      contentType: 'application/json',
      cancellation: cancellation,
    );
    await checkBlocked();
    return StickerSourcePreview(
      sourceUrl,
      parsed,
      await StickerManifest.parse(manifest.bytes, packSha256: hash),
    );
  }
}
