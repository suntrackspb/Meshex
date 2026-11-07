import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/mirror/mirror_capabilities.dart';

const url = 'https://s.example/stickers/source.json';
StickersCapability capability(List<String> urls) =>
    StickersCapability.tryParse({
      'enabled': true,
      'source_schema_versions': [1],
      'wire_versions': [2],
      'sources': [
        for (final u in urls) {'url': u, 'label': 'Source'},
      ],
    })!;

void main() {
  late AppDatabase db;
  late StickerSourceRepository repository;
  final a = Uri.parse('https://mirror-a.example/');
  final b = Uri.parse('https://mirror-b.example/');
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = StickerSourceRepository(db);
  });
  tearDown(() => db.close());

  Future<List<StickerSourceState>> read([Uri? mirror]) =>
      repository.watchSources(currentMirror: mirror).first;

  test(
    'deduplicates manual and multiple mirror origins without losing provenance',
    () async {
      await repository.addManual('HTTPS://S.EXAMPLE:443/stickers/source.json');
      await repository.reconcileMirror(
        a,
        capability([url, url]),
        cached: false,
      );
      await repository.reconcileMirror(b, capability([url]), cached: true);
      final source = (await read(a)).single;
      expect(source.url, url);
      expect(source.bindings.length, 2);
      expect(source.record.manualEnabled, isTrue);
      expect(source.active, isTrue);
      expect(source.cachedAnnouncement, isFalse);
      expect((await read(b)).single.cachedAnnouncement, isTrue);
      expect((await read()).single.active, isTrue);
    },
  );

  test(
    'mirror switch deactivates old announcements and keeps manual sources',
    () async {
      await repository.reconcileMirror(a, capability([url]), cached: false);
      await repository.addManual('https://manual.example/source.json');
      expect((await read(a)).where((s) => s.active).length, 2);
      expect(
        (await read(b)).where((s) => s.active).single.url,
        'https://manual.example/source.json',
      );
      expect((await read()).where((s) => s.active).length, 1);
      expect((await read()).length, 2);
    },
  );

  test(
    'block wins over manual enable, cached and repeated declarations',
    () async {
      await repository.addManual(url);
      await repository.setBlocked(url, true);
      await repository.reconcileMirror(a, capability([url]), cached: true);
      await repository.addManual(url);
      final source = (await read(a)).single;
      expect(source.active, isFalse);
      expect(source.record.blocked, isTrue);
      await repository.setBlocked(url, false);
      expect((await read(a)).single.active, isTrue);
      await repository.setManualEnabled(url, false);
      expect((await read()).single.active, isFalse);
      expect((await read(a)).single.active, isTrue);
    },
  );

  test('revocation removes only the specified mirror binding', () async {
    await repository.reconcileMirror(a, capability([url]), cached: false);
    await repository.reconcileMirror(b, capability([url]), cached: false);
    await repository.reconcileMirror(a, null, cached: false);
    expect((await read(a)).single.active, isFalse);
    expect((await read(b)).single.active, isTrue);
    expect((await read(b)).single.bindings.length, 1);
  });

  test(
    'verified cache persists after failure and invalid update is atomic',
    () async {
      await repository.addManual(url);
      final descriptor = File(
        'test/fixtures/stickers/source.json',
      ).readAsBytesSync();
      final catalog = File(
        'test/fixtures/stickers/catalog.json',
      ).readAsBytesSync();
      await repository.cacheSnapshot(
        sourceUrl: url,
        descriptorBytes: descriptor,
        catalogBytes: catalog,
        descriptorEtag: '"s1"',
        catalogEtag: '"c1"',
      );
      expect((await read()).single.status, StickerSourceStatus.ready);
      await repository.markFailure(url, StickerSourceStatus.offline);
      var source = (await read()).single;
      expect(source.status, StickerSourceStatus.offline);
      expect(source.catalog!.revisions.length, 1);
      expect(source.record.catalogEtag, '"c1"');
      await expectLater(
        repository.cacheSnapshot(
          sourceUrl: url,
          descriptorBytes: descriptor,
          catalogBytes: [0],
        ),
        throwsFormatException,
      );
      source = (await read()).single;
      expect(source.record.catalogEtag, '"c1"');
      expect(source.status, StickerSourceStatus.offline);
    },
  );

  test(
    'node repositories resolve to the common application registry',
    () async {
      final node = AppDatabase(NativeDatabase.memory(), db);
      try {
        await StickerSourceRepository(node).addManual(url);
        expect((await read()).single.url, url);
        expect(await node.select(node.stickerSources).get(), isEmpty);
      } finally {
        await node.close();
      }
    },
  );

  test(
    'corrupt cache isolates one source rather than breaking the registry',
    () async {
      await repository.addManual(url);
      await repository.addManual('https://other.example/source.json');
      await (db.update(db.stickerSources)
            ..where((s) => s.sourceUrl.equals(url)))
          .write(const StickerSourcesCompanion(catalogJson: Value('{bad')));
      final sources = await read();
      expect(
        sources.singleWhere((s) => s.url == url).status,
        StickerSourceStatus.invalid,
      );
      expect(
        sources.singleWhere((s) => s.url != url).status,
        StickerSourceStatus.unchecked,
      );
    },
  );

  test(
    'source removal leaves unrelated history and settings untouched',
    () async {
      await repository.addManual(url);
      await repository.reconcileMirror(a, capability([url]), cached: false);
      await db.setSetting('app.theme', 'dark');
      await repository.remove(url);
      expect(await read(a), isEmpty);
      expect(await db.select(db.stickerSourceBindings).get(), isEmpty);
      expect(await db.getSetting('app.theme'), 'dark');
    },
  );

  test(
    'registry survives restart without an active mirror or network',
    () async {
      final dir = await Directory.systemTemp.createTemp('sticker-registry-');
      try {
        final file = File('${dir.path}/app.sqlite');
        final first = AppDatabase(NativeDatabase(file));
        await StickerSourceRepository(first).addManual(url);
        await StickerSourceRepository(first).setBlocked(url, true);
        await first.close();
        final second = AppDatabase(NativeDatabase(file));
        try {
          final source = (await StickerSourceRepository(
            second,
          ).watchSources().first).single;
          expect(source.record.manualEnabled, isTrue);
          expect(source.record.blocked, isTrue);
          expect(source.active, isFalse);
        } finally {
          await second.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
