import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/data/stickers/sticker_http.dart';

import 'sticker_fixtures.dart';

void main() {
  late AppDatabase db;
  late StickerSourceRepository sources;
  late TestStickerHttp http;
  late StickerSourceClient client;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sources = StickerSourceRepository(db);
    http = TestStickerHttp();
    client = StickerSourceClient(sources, http, currentMirror: () => null);
  });
  tearDown(() => db.close());

  test('preview needs consent and never registers an unknown source', () async {
    await expectLater(
      client.preview(testSourceUrl, testPackHash, userConsent: false),
      throwsStateError,
    );
    expect(http.calls, isEmpty);
    final preview = await client.preview(
      testSourceUrl,
      testPackHash,
      userConsent: true,
    );
    expect(preview.manifest.packSha256, testPackHash);
    expect(await sources.watchSources().first, isEmpty);
    expect(http.calls.where((c) => c.url.path.contains('/media/')), isEmpty);
  });

  test('known disabled or blocked sources cannot refresh', () async {
    await sources.addManual(testSourceUrl);
    await sources.setManualEnabled(testSourceUrl, false);
    await expectLater(client.refresh(testSourceUrl), throwsStateError);
    await sources.setBlocked(testSourceUrl, true);
    await expectLater(
      client.preview(testSourceUrl, testPackHash, userConsent: true),
      throwsStateError,
    );
    expect(http.calls, isEmpty);
  });

  test(
    'refresh uses independent ETags and 304 retains verified data',
    () async {
      await sources.addManual(testSourceUrl);
      final source = Uri.parse(testSourceUrl),
          catalog = Uri.parse(testSourceUrl).resolve('catalog.json');
      http.etags[source] = '"descriptor"';
      http.etags[catalog] = '"catalog"';
      await client.refresh(testSourceUrl);
      http.status[source] = 304;
      http.status[catalog] = 304;
      await client.refresh(testSourceUrl);
      expect(http.calls[2].etag, '"descriptor"');
      expect(http.calls[3].etag, '"catalog"');
      final state = (await sources.watchSources().first).single;
      expect(state.catalog!.revisions.single.packSha256, testPackHash);
      expect(state.status, StickerSourceStatus.ready);
      http.status[source] = 503;
      await expectLater(
        client.refresh(testSourceUrl),
        throwsA(isA<StickerHttpException>()),
      );
      expect(
        (await sources.watchSources().first).single.catalog!.revisions.length,
        1,
      );
      expect(
        (await sources.watchSources().first).single.status,
        StickerSourceStatus.offline,
      );
    },
  );

  test(
    'withdrawn and unknown statuses deny preview before fetching manifest',
    () async {
      final catalog = Uri.parse(testSourceUrl).resolve('catalog.json');
      for (final status in ['withdrawn', 'unknown']) {
        http.calls.clear();
        final j =
            jsonDecode(utf8.decode(stickerFixture('catalog.json'))) as Map;
        (j['packs'] as List).first['status'] = status;
        http.bodies[catalog] = Uint8List.fromList(utf8.encode(jsonEncode(j)));
        await expectLater(
          client.preview(testSourceUrl, testPackHash, userConsent: true),
          throwsStateError,
        );
        expect(
          http.calls.where((c) => c.url.path.endsWith('/manifest.json')),
          isEmpty,
        );
      }
    },
  );

  test(
    'unlisted immutable revision and absent catalog remain discoverable; 410 does not',
    () async {
      final catalog = Uri.parse(testSourceUrl).resolve('catalog.json');
      http.status[catalog] = 404;
      expect(
        (await client.preview(
          testSourceUrl,
          testPackHash,
          userConsent: true,
        )).manifest.packSha256,
        testPackHash,
      );
      http.status[catalog] = 410;
      await expectLater(
        client.preview(testSourceUrl, testPackHash, userConsent: true),
        throwsA(isA<StickerHttpException>()),
      );
    },
  );

  test('block applied during preview prevents further requests', () async {
    await sources.addManual(testSourceUrl);
    http.beforeFetch = (_) => sources.setBlocked(testSourceUrl, true);
    await expectLater(
      client.preview(testSourceUrl, testPackHash, userConsent: true),
      throwsStateError,
    );
    expect(http.calls.length, 1);
  });
}
