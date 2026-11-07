import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/stickers/source_models.dart';
import 'package:meshex/data/stickers/strict_json.dart';

const source = 'https://s.example/stickers/source.json';
const hash = 'd2431a467ff3f617bf814ee3b2fddb976eba91ecbfe9a08650e84bd2cb5817d3';
List<int> fixture(String name) =>
    File('test/fixtures/stickers/$name.json').readAsBytesSync();
Map<String, dynamic> object(String name) =>
    (jsonDecode(utf8.decode(fixture(name))) as Map).cast<String, dynamic>();
List<int> encoded(Object? value) => utf8.encode(jsonEncode(value));
Future<StickerManifest> manifest(Map<String, dynamic> json) async {
  final bytes = encoded(json);
  final digest = await Sha256().hash(bytes);
  final hash = digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return StickerManifest.parse(bytes, packSha256: hash);
}

void main() {
  test('shared descriptor, catalog and immutable manifest', () async {
    final descriptor = StickerSourceDescriptor.parse(
      fixture('source'),
      sourceUrl: source,
    );
    expect(descriptor.name, 'Demo sticker source');
    expect(
      descriptor.catalogUrl.toString(),
      'https://s.example/stickers/catalog.json',
    );
    expect(
      descriptor.manifestUrl(hash).toString(),
      'https://s.example/stickers/packs/$hash/manifest.json',
    );
    final catalog = StickerSourceCatalog.parse(fixture('catalog'));
    expect(catalog.revisions.single.packSha256, hash);
    expect(catalog.revisions.single.canInstall, isTrue);
    final pack = await StickerManifest.parse(
      fixture('manifest'),
      packSha256: hash,
    );
    expect(pack.stickers.map((s) => s.id), ['blue', 'pulse']);
    expect(pack.downloadBytes, 366);
    expect(pack.stickers.last.frameCount, 2);
    expect(pack.authors.single, 'Meshex demo authors');
    expect(pack.licenseId, 'CC0-1.0');
    final bytes = pack.bytes..[0] = 0;
    expect(pack.bytes.first, isNot(bytes.first));
  });

  test('duplicate keys rejected, including escaped and nested keys', () {
    for (final body in [
      '{"name":1,"name":2}',
      r'{"name":1,"\u006eame":2}',
      '{"operator":{"name":1,"name":2}}',
      '{"array":[{"a":1,"a":2}]}',
    ]) {
      expect(
        () => decodeStickerJson(utf8.encode(body), limit: 1024),
        throwsFormatException,
      );
    }
    expect(
      decodeStickerJson(utf8.encode('{"a":1,"b":{"a":2}}'), limit: 1024)['a'],
      1,
    );
  });

  test(
    'reject invalid UTF-8, BOM, depth, trailing data and non-JSON literals',
    () {
      for (final body in [
        '{} {}',
        '{"a":NaN}',
        '{"a":true,}',
        '{"a":[1,]}',
        '\ufeff{}',
        '${'[' * 70}0${']' * 70}',
      ]) {
        expect(
          () => decodeStickerJson(utf8.encode(body), limit: 1024),
          throwsFormatException,
          reason: body,
        );
      }
      expect(
        () => decodeStickerJson([255], limit: 1024),
        throwsFormatException,
      );
      expect(
        () => decodeStickerJson(utf8.encode('{}'), limit: 1),
        throwsFormatException,
      );
    },
  );

  test(
    'source rejects a redirect alias, arbitrary catalog and invalid metadata',
    () {
      for (final patch in [
        {'canonical_url': 'https://other.example/source.json'},
        {'catalog_url': 'https://cdn.example/catalog.json'},
        {'catalog_url': '../catalog.json'},
        {'schema': 'other'},
        {'version': 1.0},
        {'name': 'bad\nname'},
        {
          'operator': {'name': 'Operator', 'contact': ''},
        },
      ]) {
        expect(
          () => StickerSourceDescriptor.parse(
            encoded({...object('source'), ...patch}),
            sourceUrl: source,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'catalog groups names but distinguishes hashes and blocks unknown status',
    () {
      final j = object('catalog');
      final first = (j['packs'] as List).single as Map;
      j['packs'] = [
        first,
        {
          ...first,
          'pack_sha256': 'a' * 64,
          'manifest_url': 'packs/${'a' * 64}/manifest.json',
          'status': 'future-status',
        },
      ];
      final revisions = StickerSourceCatalog.parse(encoded(j)).revisions;
      expect(revisions.map((r) => r.id).toSet().length, 1);
      expect(revisions.last.canInstall, isFalse);
      j['packs'] = [first, first];
      expect(
        () => StickerSourceCatalog.parse(encoded(j)),
        throwsFormatException,
      );
      j['packs'] = [
        {...first, 'status': 'withdrawn'},
      ];
      expect(
        StickerSourceCatalog.parse(encoded(j)).revisions.single.canInstall,
        isFalse,
      );
      j['packs'] = [
        {...first, 'manifest_url': '../manifest.json'},
      ];
      expect(
        () => StickerSourceCatalog.parse(encoded(j)),
        throwsFormatException,
      );
    },
  );

  test(
    'catalog requires real UTC dates rather than normalized overflow dates',
    () {
      for (final date in [
        '2026-02-30T00:00:00Z',
        '2026-11-06',
        '2026-11-06T00:00:00+03:00',
        '2026-11-06T25:00:00Z',
      ]) {
        final j = object('catalog');
        (j['packs'] as List).first['published_at'] = date;
        expect(
          () => StickerSourceCatalog.parse(encoded(j)),
          throwsFormatException,
        );
      }
    },
  );

  test('manifest integrity uses exact bytes before parsing', () async {
    await expectLater(
      StickerManifest.parse(encoded(object('manifest')), packSha256: hash),
      throwsFormatException,
    );
    final bytes = fixture('manifest')..[10] ^= 1;
    await expectLater(
      StickerManifest.parse(bytes, packSha256: hash),
      throwsFormatException,
    );
  });

  test('manifest metadata, IDs and media paths obey limits', () async {
    for (final patch in [
      {'id': '../escape'},
      {'animated': 'true'},
      {'alt': 'bad\nalt'},
      {
        'media': {
          ...((object('manifest')['stickers'] as List).first['media'] as Map),
          'width': 513,
        },
      },
      {
        'media': {
          ...((object('manifest')['stickers'] as List).first['media'] as Map),
          'bytes': 0,
        },
      },
      {
        'media': {
          ...((object('manifest')['stickers'] as List).first['media'] as Map),
          'url': 'https://cdn.example/image.webp',
        },
      },
    ]) {
      final j = object('manifest');
      (j['stickers'] as List)[0] = {
        ...((j['stickers'] as List).first as Map),
        ...patch,
      };
      await expectLater(manifest(j), throwsFormatException);
    }
    for (final patch in [
      {'preview': null},
      {'frame_count': 91},
      {'duration_ms': 3001},
    ]) {
      final j = object('manifest');
      (j['stickers'] as List)[1] = {
        ...((j['stickers'] as List).last as Map),
        ...patch,
      };
      await expectLater(manifest(j), throwsFormatException);
    }
    final j = object('manifest');
    (j['stickers'] as List).add((j['stickers'] as List).first);
    await expectLater(manifest(j), throwsFormatException);
  });

  test(
    'shared media counted once and contradictory metadata rejected',
    () async {
      final j = object('manifest');
      final sticker = (j['stickers'] as List).first as Map;
      j['stickers'] = [
        sticker,
        {...sticker, 'id': 'copy'},
      ];
      expect((await manifest(j)).downloadBytes, 66);
      (j['stickers'] as List)[1]['media'] = {...sticker['media'], 'bytes': 67};
      await expectLater(manifest(j), throwsFormatException);
    },
  );

  test('enforce aggregate limits independently of catalog claims', () async {
    final j = object('manifest');
    final sticker = (j['stickers'] as List).first as Map;
    j['stickers'] = [
      for (var i = 0; i < 11; i++)
        {
          ...sticker,
          'id': 's$i',
          'media': {
            ...sticker['media'],
            'sha256': i.toRadixString(16).padLeft(64, '0'),
            'url': 'media/${i.toRadixString(16).padLeft(64, '0')}.webp',
            'bytes': 5 * 1024 * 1024,
          },
        },
    ];
    await expectLater(manifest(j), throwsFormatException);
    final tooManyAuthors = object('manifest')
      ..['authors'] = List.filled(17, {'name': 'Author'});
    await expectLater(manifest(tooManyAuthors), throwsFormatException);
  });

  test('license may be explicitly unknown, but must not be missing', () async {
    final j = object('manifest')..['license'] = null;
    expect((await manifest(j)).licenseId, isNull);
    j.remove('license');
    await expectLater(manifest(j), throwsFormatException);
  });
}
