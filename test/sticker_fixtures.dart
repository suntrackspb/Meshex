import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshex/data/stickers.dart';

// Original test images: solid blue (and red for the two-frame animation).
final testStickerBytes = base64Decode(
  'UklGRjoAAABXRUJQVlA4IC4AAACwAQCdASoIAAgAAgA0JaACdLoABDAAAP75k2//kB//kB//kB//ID/iF3sYUAAA',
);
final testPreviewBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAFElEQVR4nGNkYPjLgA2wYBUdtBIAzzEBGxVmohQAAAAASUVORK5CYII=',
);
final testAnimatedBytes = base64Decode(
  'UklGRsIAAABXRUJQVlA4WAoAAAACAAAABwAABwAAQU5JTQYAAAD/////AABBTk1GRgAAAAAAAAAAAAcAAAcAAGQAAAJWUDggLgAAALABAJ0BKggACAACADQloAJ0ugAEMAAA/vmTb/+QH/+QH/+QH/8gP+IXexhQAABBTk1GSAAAAAAAAAAAAAcAAAcAAGQAAABWUDggMAAAANQBAJ0BKggACAAAADQloAJ0ugH4AAOwAP7w6Pf/ILlhdcjX/yA/4yp8ZU/48gAAAA==',
);

Future<StickerPack> testStickerPack({
  String id = 'test_pack',
  bool animated = false,
}) async {
  Future<StickerMedia> media(Uint8List bytes, String path) async {
    final digest = await Sha256().hash(bytes);
    return StickerMedia(
      url: Uri.parse('https://stickers.example/$path'),
      bytes: bytes.length,
      sha256: digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    );
  }

  return StickerPack(
    id: id,
    title: animated ? 'Animation' : 'Test pack',
    author: 'Test author',
    license: 'CC0-1.0',
    stickers: [
      StickerAsset(
        ref: StickerKey(id, '001'),
        emoji: '🔵',
        animated: animated,
        media: await media(
          animated ? testAnimatedBytes : testStickerBytes,
          '$id/001.webp',
        ),
        preview: animated ? await media(testPreviewBytes, '$id/001.png') : null,
      ),
    ],
  );
}

MockClient testStickerClient(List<StickerPack> packs) =>
    MockClient((request) async {
      if (request.url.path.endsWith('catalog.json')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'packs': [for (final p in packs) p.toJson()],
            }),
          ),
          200,
        );
      }
      for (final p in packs) {
        for (final s in p.stickers) {
          if (request.url == s.media.url) {
            return http.Response.bytes(
              s.animated ? testAnimatedBytes : testStickerBytes,
              200,
            );
          }
          if (request.url == s.preview?.url) {
            return http.Response.bytes(testPreviewBytes, 200);
          }
        }
      }
      return http.Response('not found', 404);
    });
