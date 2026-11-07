import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';

import 'source_models.dart';

Future<void> verifyStickerFile(
  Uint8List bytes,
  StickerFileDescriptor media, {
  required bool png,
}) async {
  final hash = await Sha256().hash(bytes);
  final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final correctType = png
      ? bytes.length >= 8 &&
            bytes.take(8).join(',') == '137,80,78,71,13,10,26,10'
      : bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP' &&
            ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 ==
                bytes.length;
  if (bytes.length != media.bytes || hex != media.sha256 || !correctType) {
    throw const FormatException('Sticker file integrity check failed');
  }
}

Future<void> verifyStickerImage(
  Uint8List bytes,
  StickerFileDescriptor media, {
  required bool animated,
  int? frameCount,
  int? durationMs,
}) async {
  // Read intrinsic dimensions before allocating image frames.
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width != media.width ||
        descriptor.height != media.height ||
        descriptor.width > 512 ||
        descriptor.height > 512) {
      throw const FormatException('Sticker image dimensions mismatch');
    }
    codec = await descriptor.instantiateCodec();
    final expected = animated ? frameCount : 1;
    if (codec.frameCount != expected || codec.frameCount > 90) {
      throw const FormatException('Sticker animation frame count mismatch');
    }
    var duration = 0;
    for (var i = 0; i < codec.frameCount; i++) {
      final frame = await codec.getNextFrame();
      try {
        if (frame.image.width != media.width ||
            frame.image.height != media.height) {
          throw const FormatException('Sticker frame dimensions mismatch');
        }
        duration += frame.duration.inMilliseconds;
      } finally {
        frame.image.dispose();
      }
    }
    if (animated && (duration != durationMs || duration > 3000)) {
      throw const FormatException('Sticker animation duration mismatch');
    }
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
