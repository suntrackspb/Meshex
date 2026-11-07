import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/stickers/pack_repository.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/data/stickers/sticker_http.dart';

import 'sticker_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase db;
  late StickerSourceRepository sources;
  late TestStickerHttp http;
  late StickerSourceClient client;
  late StickerPackRepository store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('meshex-packs-');
    db = AppDatabase(NativeDatabase.memory());
    sources = StickerSourceRepository(db);
    await sources.addManual(testSourceUrl);
    http = TestStickerHttp();
    client = StickerSourceClient(sources, http, currentMirror: () => null);
    store = StickerPackRepository(
      client: client,
      directory: () async => directory,
    );
  });
  tearDown(() async {
    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'atomic install verifies exact manifest, media and animation, then survives restart offline',
    () async {
      await store.install(testSourceUrl, testPackHash);
      final pack = store.installed.single;
      expect(pack.manifest.bytes, stickerFixture('manifest.json'));
      expect(
        await store.file(pack.hash, pack.manifest.stickers.first).exists(),
        isTrue,
      );
      expect(
        (await db.select(db.stickerInstalls).getSingle()).manifestBytes,
        pack.manifest.bytes,
      );
      store.dispose();
      http.beforeFetch = (_) => throw StateError('No network allowed');
      store = StickerPackRepository(
        client: client,
        directory: () async => directory,
      );
      await store.initialize();
      expect(store.contains(testPackHash), isTrue);
      expect(store.installed.single.preferredSourceUrl, testSourceUrl);
    },
  );

  test(
    'same hash at two origins is one install with confirmed origins',
    () async {
      const other = 'https://other.example/source.json';
      await sources.addManual(other);
      http.addSource(other);
      await store.install(testSourceUrl, testPackHash);
      final firstCalls = http.calls.length;
      await store.install(other, testPackHash);
      expect(store.installed.length, 1);
      expect(store.installed.single.origins, {testSourceUrl, other});
      expect(
        http.calls
            .skip(firstCalls)
            .where((c) => c.url.path.contains('/media/')),
        isEmpty,
      );
    },
  );

  test(
    'same title with different hash is a separate immutable revision',
    () async {
      final json =
          (jsonDecode(utf8.decode(stickerFixture('manifest.json'))) as Map)
            ..['revision'] = '2';
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final hash = await stickerDigest(bytes);
      http.addSource(testSourceUrl, manifest: bytes, hash: hash);
      await store.install(testSourceUrl, testPackHash);
      await store.install(testSourceUrl, hash);
      expect(store.installed.length, 2);
      expect(store.installed.map((p) => p.manifest.title).toSet().length, 1);
    },
  );

  test('bad bytes never expose a partial install and retry succeeds', () async {
    final media = http.bodies.keys.firstWhere((u) => u.path.endsWith('.webp'));
    final correct = http.bodies[media]!;
    http.bodies[media] = Uint8List(correct.length);
    await expectLater(
      store.install(testSourceUrl, testPackHash),
      throwsFormatException,
    );
    expect(store.installed, isEmpty);
    expect(await db.select(db.stickerInstalls).get(), isEmpty);
    expect(
      (await directory.list().toList()).where(
        (e) => e.path.contains('.install-'),
      ),
      isEmpty,
    );
    http.bodies[media] = correct;
    await store.install(testSourceUrl, testPackHash);
    expect(store.contains(testPackHash), isTrue);
  });

  test('cancel in-flight install removes staging and permits retry', () async {
    final started = Completer<void>();
    final stalled = Completer<void>();
    http.beforeFetch = (uri) async {
      if (uri.path.contains('/media/')) {
        if (!started.isCompleted) started.complete();
        await stalled.future;
      }
    };
    final operation = store.install(testSourceUrl, testPackHash);
    final rejected = expectLater(operation, throwsA(isA<StickerCancelled>()));
    await started.future;
    store.cancel(testPackHash);
    await rejected;
    expect(store.installed, isEmpty);
    expect(await db.select(db.stickerInstalls).get(), isEmpty);
    http.beforeFetch = null;
    stalled.complete();
    await store.install(testSourceUrl, testPackHash);
    expect(store.contains(testPackHash), isTrue);
  });

  test('concurrent install of one hash shares a single operation', () async {
    await Future.wait([
      store.install(testSourceUrl, testPackHash),
      store.install(testSourceUrl, testPackHash),
    ]);
    expect(store.installed.length, 1);
    expect(
      http.calls.where((c) => c.url.path.endsWith('manifest.json')).length,
      1,
    );
  });

  test(
    'quota refusal happens before media fetch and never evicts an install',
    () async {
      await db.setSetting(AppSettingKeys.stickerQuotaBytes, '1');
      await expectLater(
        store.install(testSourceUrl, testPackHash),
        throwsStateError,
      );
      expect(http.calls.where((c) => c.url.path.contains('/media/')), isEmpty);
      expect(store.installed, isEmpty);
    },
  );

  test(
    'blocked source cannot start DNS or HTTP; blocking mid-install prevents commit',
    () async {
      await sources.setBlocked(testSourceUrl, true);
      await expectLater(
        store.install(testSourceUrl, testPackHash),
        throwsStateError,
      );
      expect(http.calls, isEmpty);
      await sources.setBlocked(testSourceUrl, false);
      http.beforeFetch = (uri) async {
        if (uri.path.contains('/media/')) {
          await sources.setBlocked(testSourceUrl, true);
        }
      };
      await expectLater(
        store.install(testSourceUrl, testPackHash),
        throwsA(anyOf(isA<StateError>(), isA<StickerCancelled>())),
      );
      expect(store.installed, isEmpty);
      expect(await db.select(db.stickerInstalls).get(), isEmpty);
    },
  );

  test(
    'missing or same-sized corrupt file is detected on restart and can be repaired',
    () async {
      await store.install(testSourceUrl, testPackHash);
      final pack = store.installed.single;
      final file = store.file(testPackHash, pack.manifest.stickers.first);
      await file.writeAsBytes(List.filled(await file.length(), 0));
      store.dispose();
      store = StickerPackRepository(
        client: client,
        directory: () async => directory,
      );
      await store.initialize();
      expect(store.installed, isEmpty);
      expect(store.damagedHashes, contains(testPackHash));
      expect(
        (await db.select(db.stickerInstalls).getSingle()).status,
        'damaged',
      );
      await store.install(testSourceUrl, testPackHash);
      expect(store.contains(testPackHash), isTrue);
      expect(store.damagedHashes, isEmpty);
      expect((await db.select(db.stickerInstalls).getSingle()).status, 'ready');
    },
  );

  test(
    'hash-correct media with false dimensions or animation metadata fails decoder verification',
    () async {
      final json =
          jsonDecode(utf8.decode(stickerFixture('manifest.json'))) as Map;
      (json['stickers'] as List).last['duration_ms'] = 201;
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final hash = await stickerDigest(bytes);
      http.addSource(testSourceUrl, manifest: bytes, hash: hash);
      await expectLater(
        store.install(testSourceUrl, hash),
        throwsFormatException,
      );
      expect(store.installed, isEmpty);
    },
  );

  test(
    'startup clears interrupted staging and orphan packs; remove preserves message data',
    () async {
      await Directory('${directory.path}/.install-interrupted').create();
      await Directory(
        '${directory.path}/packs/${'a' * 64}',
      ).create(recursive: true);
      await store.initialize();
      expect(
        await Directory('${directory.path}/.install-interrupted').exists(),
        isFalse,
      );
      expect(
        await Directory('${directory.path}/packs/${'a' * 64}').exists(),
        isFalse,
      );
      await store.install(testSourceUrl, testPackHash);
      await db.setSetting('app.theme', 'dark');
      await store.remove(testPackHash);
      expect(store.installed, isEmpty);
      expect(await db.select(db.stickerInstalls).get(), isEmpty);
      expect(await db.getSetting('app.theme'), 'dark');
      expect(
        await Directory('${directory.path}/packs/$testPackHash').exists(),
        isFalse,
      );
    },
  );

  test(
    'symlinked media does not become an installed pack on restart',
    () async {
      await store.install(testSourceUrl, testPackHash);
      final pack = store.installed.single;
      final file = store.file(testPackHash, pack.manifest.stickers.first);
      final external = File('${directory.path}/outside.webp');
      await external.writeAsBytes(await file.readAsBytes());
      await file.delete();
      await Link(file.path).create(external.path);
      store.dispose();
      store = StickerPackRepository(
        client: client,
        directory: () async => directory,
      );
      await store.initialize();
      expect(store.installed, isEmpty);
      expect(await external.exists(), isTrue);
    },
  );
}
