import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshex/data/sticker_store.dart';
import 'package:meshex/data/stickers.dart';

import 'sticker_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late StickerStore store;
  late StickerPack pack;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('meshex-sticker-test-');
    pack = await testStickerPack(animated: true);
    store = StickerStore(
      directory: () async => directory,
      client: testStickerClient([pack]),
    );
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  test('catalog resolves metadata and relative URLs', () async {
    final catalog = await store.catalog(
      'https://stickers.example/catalog.json',
    );
    expect(catalog.single.license, 'CC0-1.0');
    final json = pack.toJson();
    (json['stickers'] as List).first['media']['url'] = 'packs/001.webp';
    final parsed = StickerPack.fromJson(
      json,
      Uri.parse('https://example.org/stickers/catalog.json'),
    );
    expect(
      '${parsed.stickers.single.media.url}',
      'https://example.org/stickers/packs/001.webp',
    );
  });

  test(
    'download persists animations and survives restart entirely offline',
    () async {
      await store.install(pack);
      expect(store.contains(pack.id), isTrue);
      final s = store.find(StickerKey(pack.id, '001'))!;
      expect(await store.file(s).readAsBytes(), testAnimatedBytes);
      expect(await store.file(s, still: true).readAsBytes(), testPreviewBytes);
      final codec = await ui.instantiateImageCodec(
        await store.file(s).readAsBytes(),
      );
      expect(codec.frameCount, 2);
      codec.dispose();
      store.dispose();
      store = StickerStore(
        directory: () async => directory,
        client: MockClient((_) async => throw StateError('offline')),
      );
      expect((await store.watchInstalled().first).single.id, pack.id);
      expect(store.find(StickerKey(pack.id, '001')), isNotNull);
      await store.remove(pack.id);
      expect(store.installed, isEmpty);
      expect(await Directory('${directory.path}/${pack.id}').exists(), isFalse);
    },
  );

  test(
    'hash failure or interrupted install never exposes a partial pack',
    () async {
      store.dispose();
      store = StickerStore(
        directory: () async => directory,
        client: MockClient(
          (_) async => http.Response.bytes(
            List.filled(pack.stickers.first.media.bytes, 0),
            200,
          ),
        ),
      );
      await expectLater(store.install(pack), throwsFormatException);
      expect(store.installed, isEmpty);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'HTTP failure cleans up staging and the same pack can be retried',
    () async {
      store.dispose();
      var fail = true;
      final good = testStickerClient([pack]);
      store = StickerStore(
        directory: () async => directory,
        client: MockClient((request) async {
          if (fail) return http.Response('unavailable', 503);
          return http.Response.bytes(await good.readBytes(request.url), 200);
        }),
      );
      await expectLater(store.install(pack), throwsA(isA<HttpException>()));
      expect(await directory.list().toList(), isEmpty);
      fail = false;
      await store.install(pack);
      expect(store.contains(pack.id), isTrue);
      good.close();
    },
  );

  test('existing pack contents cannot be silently replaced', () async {
    await store.install(pack);
    final changed = pack.toJson();
    (changed['stickers'] as List).first['media']['sha256'] = 'a' * 64;
    await expectLater(
      store.install(StickerPack.fromJson(changed, Uri())),
      throwsFormatException,
    );
    expect(
      await store.file(pack.stickers.single).readAsBytes(),
      testAnimatedBytes,
    );
  });

  test(
    'catalog rejects traversal, duplicate IDs, oversized files and unsafe URLs',
    () {
      for (final id in ['../escape', 'a/b', 'a:b', '.']) {
        final json = pack.toJson()..['id'] = id;
        expect(() => StickerPack.fromJson(json, Uri()), throwsFormatException);
      }
      for (final url in [
        'http://example.org/catalog.json',
        'file:///tmp/catalog.json',
        'https://user:pass@example.org',
      ]) {
        expect(() => StickerStore.catalogUri(url), throwsFormatException);
      }
      final duplicate = pack.toJson();
      (duplicate['stickers'] as List).add(
        (duplicate['stickers'] as List).first,
      );
      expect(
        () => StickerPack.fromJson(duplicate, Uri()),
        throwsFormatException,
      );
      final oversized = pack.toJson();
      (oversized['stickers'] as List).first['media']['bytes'] = 6 * 1024 * 1024;
      expect(
        () => StickerPack.fromJson(oversized, Uri()),
        throwsFormatException,
      );
      expect(
        () =>
            parseStickerCatalog(jsonEncode({'version': 2, 'packs': []}), Uri()),
        throwsFormatException,
      );
    },
  );

  test('incomplete pack on disk is ignored after restart', () async {
    await store.install(pack);
    await store.file(pack.stickers.single).delete();
    store.dispose();
    store = StickerStore(
      directory: () async => directory,
      client: testStickerClient([pack]),
    );
    await store.initialize();
    expect(store.installed, isEmpty);
    await store.install(pack);
    expect(store.contains(pack.id), isTrue);
  });
}
