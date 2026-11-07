import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/mirror/mirror_api.dart';

const url = 'https://s.example/stickers/source.json';
final declared = {
  'stickers': {
    'enabled': true,
    'source_schema_versions': [1],
    'wire_versions': [2],
    'sources': [
      {'url': url},
    ],
  },
};

void main() {
  test(
    'sync records only capabilities; switch and disable retain manual sources',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var requests = 0;
      MirrorApi api(String host) {
        final api = MirrorApi(
          Uri.parse('https://$host/'),
          client: MockClient((request) async {
            requests++;
            expect(request.url.host, host);
            expect(request.url.path, '/api/v1/capabilities');
            return http.Response(jsonEncode(declared), 200);
          }),
        );
        addTearDown(api.close);
        return api;
      }

      final first = api('mirror-a.example');
      final second = api('mirror-b.example');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mirrorApiProvider.overrideWithValue(first),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(stickerSourcesProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(stickerSourceSyncProvider.future);
      await container
          .read(stickerSourceRepositoryProvider)
          .addManual('https://manual.example/source.json');
      expect(
        (await container.read(
          stickerSourcesProvider.future,
        )).where((s) => s.active).length,
        2,
      );
      container.updateOverrides([
        appDatabaseProvider.overrideWithValue(db),
        mirrorApiProvider.overrideWithValue(second),
      ]);
      await container.read(stickerSourceSyncProvider.future);
      expect(
        (await container.read(
          stickerSourcesProvider.future,
        )).singleWhere((s) => s.url == url).bindings.length,
        2,
      );
      container.updateOverrides([
        appDatabaseProvider.overrideWithValue(db),
        mirrorApiProvider.overrideWithValue(null),
      ]);
      await container.read(stickerSourceSyncProvider.future);
      final offline = await container.read(stickerSourcesProvider.future);
      expect(offline.singleWhere((s) => s.url == url).active, isFalse);
      expect(offline.singleWhere((s) => s.record.manualEnabled).active, isTrue);
      expect(
        requests,
        2,
      ); // No descriptor/catalog/media or DNS requests from sync.
    },
  );

  test(
    'offline cached capabilities never override a persisted block',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final base = Uri.parse('https://offline.example/');
      await db.setSetting(
        AppSettingKeys.mirrorCapabilities(base),
        jsonEncode(declared),
      );
      final api = MirrorApi(
        base,
        client: MockClient((_) async => http.Response('', 503)),
      );
      addTearDown(api.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mirrorApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(stickerSourcesProvider, (_, _) {});
      addTearDown(subscription.close);
      final repository = container.read(stickerSourceRepositoryProvider);
      await repository.addManual(url);
      await repository.setBlocked(url, true);
      await container.read(stickerSourceSyncProvider.future);
      final source = (await container.read(
        stickerSourcesProvider.future,
      )).single;
      expect(source.cachedAnnouncement, isTrue);
      expect(source.record.blocked, isTrue);
      expect(source.active, isFalse);
    },
  );
}
