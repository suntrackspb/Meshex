import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/stickers/wire_codec.dart';
import '../../mirror/mirror_capabilities.dart';
import '../database.dart';
import 'source_models.dart';

enum StickerSourceStatus { unchecked, ready, offline, incompatible, invalid }

class StickerSourceState {
  StickerSourceState._(
    this.record,
    this.bindings,
    this.currentMirror,
    this.descriptor,
    this.catalog,
    this.status,
  );
  final StickerSource record;
  final List<StickerSourceBinding> bindings;
  final String? currentMirror;
  final StickerSourceDescriptor? descriptor;
  final StickerSourceCatalog? catalog;
  final StickerSourceStatus status;
  String get url => record.sourceUrl;
  bool get announcedByCurrentMirror =>
      bindings.any((b) => b.mirrorBaseUrl == currentMirror);
  bool get active =>
      !record.blocked && (record.manualEnabled || announcedByCurrentMirror);
  bool get cachedAnnouncement =>
      bindings.any((b) => b.mirrorBaseUrl == currentMirror && b.cached);
  String get name =>
      descriptor?.name ??
      bindings
          .where((b) => b.mirrorBaseUrl == currentMirror)
          .firstOrNull
          ?.label ??
      Uri.parse(url).host;
}

/// Application-wide metadata only. Discovery and database reads never fetch a
/// source (not even DNS), and previewing an unknown source cannot add it here.
class StickerSourceRepository {
  StickerSourceRepository(AppDatabase database) : db = _global(database);
  final AppDatabase db;
  static AppDatabase _global(AppDatabase db) =>
      db.settings == null ? db : _global(db.settings!);

  Future<void> addManual(String input) async {
    final url = normalizeSourceUrl(input);
    await db
        .into(db.stickerSources)
        .insert(
          StickerSourcesCompanion.insert(
            sourceUrl: url,
            manualEnabled: const Value(true),
          ),
          onConflict: DoUpdate(
            (_) => const StickerSourcesCompanion(manualEnabled: Value(true)),
          ),
        );
  }

  Future<void> setManualEnabled(String sourceUrl, bool enabled) async {
    final url = validateSourceUrl(sourceUrl).toString();
    final changed =
        await (db.update(db.stickerSources)
              ..where((s) => s.sourceUrl.equals(url)))
            .write(StickerSourcesCompanion(manualEnabled: Value(enabled)));
    if (changed == 0) throw StateError('Unknown sticker source');
  }

  Future<void> setBlocked(String sourceUrl, bool blocked) async {
    final url = validateSourceUrl(sourceUrl).toString();
    final changed =
        await (db.update(db.stickerSources)
              ..where((s) => s.sourceUrl.equals(url)))
            .write(StickerSourcesCompanion(blocked: Value(blocked)));
    if (changed == 0) throw StateError('Unknown sticker source');
  }

  /// Replace only this mirror's announcements. Historical bindings remain for
  /// display, but only the currently enabled mirror can activate them.
  Future<void> reconcileMirror(
    Uri mirror,
    StickersCapability? capability, {
    required bool cached,
  }) => db.transaction(() async {
    final key = mirror.toString();
    await (db.delete(
      db.stickerSourceBindings,
    )..where((b) => b.mirrorBaseUrl.equals(key))).go();
    for (final source
        in capability?.sources ?? const <StickerSourceAnnouncement>[]) {
      final url = validateSourceUrl(source.url).toString();
      await db
          .into(db.stickerSources)
          .insert(
            StickerSourcesCompanion.insert(sourceUrl: url),
            mode: InsertMode.insertOrIgnore,
          );
      await db
          .into(db.stickerSourceBindings)
          .insert(
            StickerSourceBindingsCompanion.insert(
              sourceUrl: url,
              mirrorBaseUrl: key,
              label: Value(source.label),
              cached: Value(cached),
            ),
          );
    }
  });

  Stream<List<StickerSourceState>> watchSources({Uri? currentMirror}) {
    final sources = db.stickerSources;
    final bindings = db.stickerSourceBindings;
    final query =
        db.select(sources).join([
          leftOuterJoin(
            bindings,
            bindings.sourceUrl.equalsExp(sources.sourceUrl),
          ),
        ])..orderBy([
          OrderingTerm.asc(sources.sourceUrl),
          OrderingTerm.asc(bindings.mirrorBaseUrl),
        ]);
    return query.watch().map((rows) {
      final records = <String, StickerSource>{};
      final allBindings = <String, List<StickerSourceBinding>>{};
      for (final row in rows) {
        final source = row.readTable(sources);
        records[source.sourceUrl] = source;
        final binding = row.readTableOrNull(bindings);
        if (binding != null) {
          (allBindings[source.sourceUrl] ??= []).add(binding);
        }
      }
      return List.unmodifiable(
        records.values.map(
          (record) => _state(
            record,
            allBindings[record.sourceUrl] ?? const [],
            currentMirror?.toString(),
          ),
        ),
      );
    });
  }

  StickerSourceState _state(
    StickerSource record,
    List<StickerSourceBinding> bindings,
    String? mirror,
  ) {
    var status =
        StickerSourceStatus.values
            .where((s) => s.name == record.status)
            .firstOrNull ??
        StickerSourceStatus.invalid;
    StickerSourceDescriptor? descriptor;
    StickerSourceCatalog? catalog;
    try {
      if (record.descriptorJson != null) {
        descriptor = StickerSourceDescriptor.parse(
          utf8.encode(record.descriptorJson!),
          sourceUrl: record.sourceUrl,
        );
      }
      if (record.catalogJson != null) {
        catalog = StickerSourceCatalog.parse(utf8.encode(record.catalogJson!));
      }
    } on FormatException {
      status = StickerSourceStatus.invalid;
    }
    return StickerSourceState._(
      record,
      List.unmodifiable(bindings),
      mirror,
      descriptor,
      catalog,
      status,
    );
  }

  /// Commit validated descriptor/catalog together; a failed refresh must never
  /// erase a previously verified catalog. Fetch policy belongs to the caller.
  Future<void> cacheSnapshot({
    required String sourceUrl,
    required List<int> descriptorBytes,
    required List<int> catalogBytes,
    String? descriptorEtag,
    String? catalogEtag,
  }) async {
    StickerSourceDescriptor.parse(descriptorBytes, sourceUrl: sourceUrl);
    StickerSourceCatalog.parse(catalogBytes);
    for (final etag in [descriptorEtag, catalogEtag]) {
      if (etag != null &&
          (etag.length > 1024 || etag.runes.any((c) => c < 32 || c == 127))) {
        throw const FormatException('Invalid sticker ETag');
      }
    }
    final changed =
        await (db.update(
          db.stickerSources,
        )..where((s) => s.sourceUrl.equals(sourceUrl))).write(
          StickerSourcesCompanion(
            descriptorJson: Value(utf8.decode(descriptorBytes)),
            catalogJson: Value(utf8.decode(catalogBytes)),
            descriptorEtag: Value(descriptorEtag),
            catalogEtag: Value(catalogEtag),
            lastChecked: Value(DateTime.now()),
            status: const Value('ready'),
          ),
        );
    if (changed == 0) throw StateError('Unknown sticker source');
  }

  Future<void> markFailure(String sourceUrl, StickerSourceStatus status) async {
    validateSourceUrl(sourceUrl);
    if (![
      StickerSourceStatus.offline,
      StickerSourceStatus.incompatible,
      StickerSourceStatus.invalid,
    ].contains(status)) {
      throw ArgumentError('Expected a failed source status');
    }
    await (db.update(
      db.stickerSources,
    )..where((s) => s.sourceUrl.equals(sourceUrl))).write(
      StickerSourcesCompanion(
        status: Value(status.name),
        lastChecked: Value(DateTime.now()),
      ),
    );
  }

  /// Does not touch messages or installed pack files (which retain origins).
  Future<void> remove(String sourceUrl) async {
    validateSourceUrl(sourceUrl);
    await db.transaction(() async {
      await (db.delete(
        db.stickerSourceBindings,
      )..where((b) => b.sourceUrl.equals(sourceUrl))).go();
      await (db.delete(
        db.stickerSources,
      )..where((s) => s.sourceUrl.equals(sourceUrl))).go();
    });
  }
}
