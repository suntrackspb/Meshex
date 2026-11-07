import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/stickers/source_models.dart';

import 'sticker_fixtures.dart';

void main() {
  test(
    'local publisher emits client-readable schemas and preserves exact shared revision',
    () async {
      final dir = await Directory.systemTemp.createTemp('sticker-publisher-');
      try {
        final output = '${dir.path}/source';
        final args = [
          'tool/export_sticker_catalog.py',
          '--pack-dir',
          'test/fixtures/stickers',
          '--source-url',
          testSourceUrl,
          '--name',
          'Demo',
          '--operator-name',
          'Demo',
          '--operator-contact',
          'mailto:test@example.org',
          '--published-at',
          '2026-11-06T00:00:00Z',
          '--output',
          output,
        ];
        final exported = await Process.run('python3', args);
        expect(exported.exitCode, 0, reason: '${exported.stderr}');
        final descriptor = StickerSourceDescriptor.parse(
          await File('$output/source.json').readAsBytes(),
          sourceUrl: testSourceUrl,
        );
        expect(descriptor.name, 'Demo');
        final catalog = StickerSourceCatalog.parse(
          await File('$output/catalog.json').readAsBytes(),
        );
        expect(catalog.revisions.single.packSha256, testPackHash);
        expect(catalog.revisions.single.downloadBytes, 366);
        final bytes = await File(
          '$output/packs/$testPackHash/manifest.json',
        ).readAsBytes();
        expect(bytes, stickerFixture('manifest.json'));
        final manifest = await StickerManifest.parse(
          bytes,
          packSha256: testPackHash,
        );
        for (final s in manifest.stickers) {
          for (final media in [s.media, ?s.preview]) {
            final data = await File(
              '$output/packs/$testPackHash/${media.path}',
            ).readAsBytes();
            expect(await stickerDigest(data), media.sha256);
          }
        }
        expect((await Process.run('python3', args)).exitCode, isNot(0));
        expect(
          await File('$output/packs/$testPackHash/manifest.json').readAsBytes(),
          bytes,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'publisher rejects inconsistent media identity without publishing a partial source',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'sticker-publisher-bad-',
      );
      try {
        final input = Directory('${dir.path}/input');
        await input.create();
        final json =
            jsonDecode(utf8.decode(stickerFixture('manifest.json'))) as Map;
        (json['stickers'] as List).first['media']['sha256'] = 'a' * 64;
        await File(
          '${input.path}/manifest.json',
        ).writeAsString(jsonEncode(json));
        final output = '${dir.path}/output';
        final result = await Process.run('python3', [
          'tool/export_sticker_catalog.py',
          '--pack-dir',
          input.path,
          '--source-url',
          testSourceUrl,
          '--name',
          'Demo',
          '--operator-name',
          'Demo',
          '--operator-contact',
          'mailto:test@example.org',
          '--published-at',
          '2026-11-06T00:00:00Z',
          '--output',
          output,
        ]);
        expect(result.exitCode, isNot(0));
        expect(await Directory(output).exists(), isFalse);
        expect(
          (await dir.list().toList()).where(
            (e) => e.path.contains('.sticker-publish-'),
          ),
          isEmpty,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
