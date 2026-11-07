import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:meshex/core/stickers/wire_codec.dart';

void main() {
  final fixture =
      (jsonDecode(File('test/fixtures/stickers/wire.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>();
  final envelope = StickerEnvelope.fromJson({...fixture, 'wire_version': 2});
  final bytes = StickerWireCodec.encode(envelope);

  test('shared STK-DRAFT-2 exact vector and immutable manifest', () async {
    expect(bytes.length, fixture['payload_bytes']);
    expect(
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      fixture['payload_hex'],
    );
    expect(StickerWireCodec.decode(bytes)!.toJson(), envelope.toJson());
    final manifest = File(
      'test/fixtures/stickers/manifest.json',
    ).readAsBytesSync();
    expect(manifest.length, 1050);
    final digest = await Sha256().hash(manifest);
    expect(
      digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      envelope.packSha256,
    );
  });

  test('every truncation and trailing byte are rejected', () {
    for (var n = 0; n < bytes.length; n++) {
      expect(
        StickerWireCodec.decode(bytes.sublist(0, n)),
        isNull,
        reason: 'length $n',
      );
    }
    expect(StickerWireCodec.decode([...bytes, 0]), isNull);
  });

  test('magic, version, type, lengths and non-ASCII are strict', () {
    for (final index in [0, 1, 2, 3, 4, 5, 38 + bytes[5]]) {
      final bad = [...bytes]..[index] = 0;
      expect(StickerWireCodec.decode(bad), isNull, reason: 'offset $index');
    }
    for (final index in [6, bytes.length - 1]) {
      final bad = [...bytes]..[index] = 255;
      expect(StickerWireCodec.decode(bad), isNull);
    }
    expect(
      StickerWireCodec.decode(utf8.encode('sticker:eto:s1:test:001')),
      isNull,
    );
  });

  test(
    'maximum envelope is 191 bytes; transport can impose a smaller budget',
    () {
      final source = 'https://s.example/${'a' * 98}/source.json';
      expect(source.length, 128);
      final value = StickerEnvelope(
        sourceUrl: source,
        packSha256: envelope.packSha256,
        stickerId: 'a' * 24,
      );
      final maximum = StickerWireCodec.encode(value);
      expect(maximum.length, 191);
      expect(StickerWireCodec.decode(maximum), isNotNull);
      expect(
        () => StickerWireCodec.encode(value, payloadBudget: 190),
        throwsFormatException,
      );
      expect(
        () => StickerEnvelope(
          sourceUrl: source.replaceFirst('aaa', 'aaaa'),
          packSha256: envelope.packSha256,
          stickerId: 'a',
        ),
        throwsFormatException,
      );
    },
  );

  test('reject unsafe and noncanonical source URLs without network access', () {
    for (final url in [
      'http://s.example/source.json',
      'HTTPS://s.example/source.json',
      'https://S.example/source.json',
      'https://s.example:443/source.json',
      'https://u:p@s.example/source.json',
      'https://s.example/source.json?q=x',
      'https://s.example/source.json#x',
      'https://127.0.0.1/source.json',
      'https://[::1]/source.json',
      'https://localhost/source.json',
      'https://s.local/source.json',
      'https://s.localhost/source.json',
      'https://metadata.google.internal/source.json',
      'https://s.example./source.json',
      'https://s.example//source.json',
      'https://s.example/../source.json',
      'https://s.example/%61/source.json',
      'https://s.example/привет/source.json',
      'https://-s.example/source.json',
      'https://s.example/source.json\n',
    ]) {
      expect(() => validateSourceUrl(url), throwsFormatException, reason: url);
    }
    expect(
      normalizeSourceUrl(' HTTPS://S.EXAMPLE:443/Test/source.json '),
      'https://s.example/Test/source.json',
    );
    expect(
      validateSourceUrl('https://xn--e1afmkfd.xn--p1ai/source.json').host,
      'xn--e1afmkfd.xn--p1ai',
    );
  });

  test('identity is strict and cannot bypass validation through JSON', () {
    for (final id in ['', 'a' * 25, '../x', '😀', 'x\n']) {
      expect(
        () => StickerEnvelope(
          sourceUrl: envelope.sourceUrl,
          packSha256: envelope.packSha256,
          stickerId: id,
        ),
        throwsFormatException,
      );
    }
    for (final hash in ['', 'a' * 63, 'A' * 64, '${'a' * 64}\n']) {
      expect(
        () => StickerEnvelope(
          sourceUrl: envelope.sourceUrl,
          packSha256: hash,
          stickerId: 'a',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => StickerEnvelope.fromJson({...envelope.toJson(), 'wire_version': 1}),
      throwsFormatException,
    );
  });
}
