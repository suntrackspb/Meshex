import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/node_dbs.dart';
import 'package:meshex/mirror/mirror_config.dart';

void main() {
  late AppDatabase shared;
  late AppDatabase a;
  late AppDatabase b;
  const initial = MirrorConfig(enabled: true, address: 'first.example.org');
  const second = MirrorConfig(enabled: true, address: 'second.example.org');

  setUp(() async {
    shared = AppDatabase(NativeDatabase.memory());
    a = AppDatabase(NativeDatabase.memory(), shared);
    b = AppDatabase(NativeDatabase.memory(), shared);
    await shared.saveMirrorConfig(initial);
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await shared.close();
  });

  test(
    'nodes snapshot defaults, then address and enabled are independent',
    () async {
      expect(await a.watchMirrorConfig().first, initial);
      expect(await b.watchMirrorConfig().first, initial);
      await a.saveMirrorConfig(second);
      await b.saveMirrorConfig(
        const MirrorConfig(address: 'first.example.org'),
      );
      expect(await a.watchMirrorConfig().first, second);
      expect((await b.watchMirrorConfig().first).enabled, isFalse);
      expect(await shared.watchMirrorConfig().first, initial);
      await shared.saveMirrorConfig(const MirrorConfig());
      expect(await a.watchMirrorConfig().first, second);
      expect((await b.watchMirrorConfig().first).address, initial.address);
      // Ordinary application settings still use the shared database.
      await a.setSetting(AppSettingKeys.theme, 'dark');
      expect(await b.getSetting(AppSettingKeys.theme), 'dark');
    },
  );

  test(
    'node preferences survive reopening, without inheriting new defaults',
    () async {
      final dir = Directory.systemTemp.createTempSync('mirror_settings');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/node.sqlite');
      final first = AppDatabase(NativeDatabase(file), shared);
      expect(await first.watchMirrorConfig().first, initial);
      await first.saveMirrorConfig(second);
      await first.close();
      await shared.saveMirrorConfig(const MirrorConfig());
      final reopened = AppDatabase(NativeDatabase(file), shared);
      try {
        expect(await reopened.watchMirrorConfig().first, second);
      } finally {
        await reopened.close();
      }
    },
  );

  test(
    'switching nodes immediately clears previous config; no-node uses shared',
    () async {
      await a.saveMirrorConfig(second);
      await b.saveMirrorConfig(const MirrorConfig());
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(shared),
          databaseProvider.overrideWith(
            (ref) => ref.watch(activeNodeDbProvider) == 1 ? a : b,
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(mirrorConfigProvider, (_, _) {});
      addTearDown(subscription.close);
      Future<MirrorConfig> loaded() async {
        for (var i = 0; i < 100; i++) {
          final value = container.read(mirrorConfigProvider).value;
          if (value != null) return value;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        throw StateError('Mirror config did not load');
      }

      expect(await loaded(), initial);
      container.read(activeNodeDbProvider.notifier).state = 1;
      expect(container.read(mirrorConfigProvider).value, isNull);
      expect(await loaded(), second);
      container.read(activeNodeDbProvider.notifier).state = 2;
      expect(container.read(mirrorConfigProvider).value, isNull);
      expect(await loaded(), MirrorConfig.off);
      container.read(activeNodeDbProvider.notifier).state = noNodeDb;
      expect(await loaded(), initial);
    },
  );
}
