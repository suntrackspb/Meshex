import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/mirror/mirror_api.dart';
import 'package:meshex/mirror/mirror_capabilities.dart';

void main() {
  test(
    'persists across launches, isolates mirrors and accepts removal',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final url = Uri.parse('https://mirror.example.org');
      var requests = 0;
      Future<({MirrorCapabilities? capabilities, bool refreshed})> launch(
        Uri base,
        int status,
        Object body,
      ) async {
        final api = MirrorApi(
          base,
          client: MockClient((_) async {
            requests++;
            return http.Response(jsonEncode(body), status);
          }),
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mirrorApiProvider.overrideWithValue(api),
          ],
        );
        try {
          return await container.read(mirrorCapabilitiesLoadProvider.future);
        } finally {
          container.dispose();
          api.close();
        }
      }

      final original = {
        'name': 'Mirror',
        'operator': {'contact': 'admin@example.org'},
        'images': {
          'enabled': true,
          'base_url': 'https://images.example.org',
          'public_key': base64Encode(List.filled(32, 7)),
          'max_bytes': 12345,
          'preview_hosts': ['images.example.org', 'cdn.example.org'],
          'report': true,
          'delete': true,
        },
        'reports': {
          'base_url': 'https://reports.example.org',
          'api_key': 'key',
          'notices': true,
        },
      };
      expect((await launch(url, 200, original)).refreshed, isTrue);
      final offline = await launch(url, 503, {});
      expect(offline.refreshed, isFalse);
      expect(
        offline.capabilities!.toJson(),
        (await launch(url, 200, original)).capabilities!.toJson(),
      );
      final other = await launch(
        Uri.parse('https://other.example.org'),
        503,
        {},
      );
      expect(other.capabilities!.images, isNull);
      expect(other.capabilities!.reports, isNull);
      // A successful empty response revokes previously advertised features.
      expect((await launch(url, 200, {})).capabilities!.images, isNull);
      expect((await launch(url, 503, {})).capabilities!.images, isNull);
      await launch(url, 200, original);
      expect((await launch(url, 404, {})).refreshed, isTrue);
      expect((await launch(url, 503, {})).capabilities!.reports, isNull);
      expect(requests, 9);
    },
  );
}
