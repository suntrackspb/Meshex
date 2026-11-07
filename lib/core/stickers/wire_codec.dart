import 'dart:convert';
import 'dart:typed_data';

/// STK-DRAFT-2 identity. The source is a discovery hint, not the image key.
class StickerEnvelope {
  StickerEnvelope({
    required this.sourceUrl,
    required this.packSha256,
    required this.stickerId,
  }) {
    validateSourceUrl(sourceUrl);
    if (!_fullMatch(r'[a-f0-9]{64}', packSha256) ||
        !_fullMatch(r'[A-Za-z0-9_-]{1,24}', stickerId)) {
      throw const FormatException('Invalid sticker identity');
    }
  }

  final String sourceUrl;
  final String packSha256;
  final String stickerId;

  Map<String, Object> toJson() => {
    'wire_version': 2,
    'source_url': sourceUrl,
    'pack_sha256': packSha256,
    'sticker_id': stickerId,
  };

  factory StickerEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['wire_version'] is! int ||
        json['wire_version'] != 2 ||
        json['source_url'] is! String ||
        json['pack_sha256'] is! String ||
        json['sticker_id'] is! String) {
      throw const FormatException('Invalid sticker envelope');
    }
    return StickerEnvelope(
      sourceUrl: json['source_url'] as String,
      packSha256: json['pack_sha256'] as String,
      stickerId: json['sticker_id'] as String,
    );
  }
}

bool _fullMatch(String pattern, String value) {
  final match = RegExp(pattern).matchAsPrefix(value);
  return match != null && match.end == value.length;
}

/// Pure syntax validation: never resolves DNS or accesses the network.
/// Fetchers must additionally validate DNS and the actual connection address.
Uri validateSourceUrl(String value) {
  if (value.length > 128 ||
      !_fullMatch(r'https://[a-z0-9.-]+(?:/[A-Za-z0-9._~-]+)+', value)) {
    throw const FormatException('Expected canonical public source URL');
  }
  final uri = Uri.parse(value);
  final host = uri.host;
  final labels = host.split('.');
  if (labels.length < 2 ||
      host.endsWith('.') ||
      labels.any(
        (s) => !_fullMatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', s),
      ) ||
      !_fullMatch(r'[a-z][a-z0-9-]*', labels.last) ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host == 'metadata.google.internal' ||
      value
          .substring(value.indexOf('/', 8))
          .split('/')
          .any((s) => s == '.' || s == '..') ||
      !value.endsWith('/source.json')) {
    throw const FormatException('Invalid public source URL');
  }
  return uri;
}

/// Normalizes ASCII user input. Unicode hosts must first be converted to IDNA
/// A-labels by the input layer; wire decoding never normalizes received bytes.
String normalizeSourceUrl(String input) {
  final raw = input.trim();
  final match = RegExp(
    r'^https://([^/]+)(/.*)$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) throw const FormatException('Expected HTTPS source URL');
  var authority = match.group(1)!.toLowerCase();
  if (authority.endsWith(':443')) {
    authority = authority.substring(0, authority.length - 4);
  }
  final normalized = 'https://$authority${match.group(2)}';
  validateSourceUrl(normalized);
  return normalized;
}

class StickerWireCodec {
  static const portnum = 256;
  static const maxEnvelopeBytes = 191;

  static Uint8List encode(StickerEnvelope value, {int payloadBudget = 200}) {
    final url = ascii.encode(value.sourceUrl);
    final id = ascii.encode(value.stickerId);
    final bytes = Uint8List.fromList([
      0x45,
      0x54,
      0x4f,
      2,
      1,
      url.length,
      ...url,
      for (var i = 0; i < 64; i += 2)
        int.parse(value.packSha256.substring(i, i + 2), radix: 16),
      id.length,
      ...id,
    ]);
    if (bytes.length > payloadBudget) {
      throw const FormatException('Sticker exceeds transport payload budget');
    }
    return bytes;
  }

  /// Unrelated PRIVATE_APP packets and malformed envelopes return null.
  static StickerEnvelope? decode(List<int> bytes) {
    if (bytes.length < 41 ||
        bytes.length > maxEnvelopeBytes ||
        bytes.any((b) => b < 0 || b > 255) ||
        bytes[0] != 0x45 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x4f ||
        bytes[3] != 2 ||
        bytes[4] != 1) {
      return null;
    }
    final n = bytes[5];
    if (n < 1 || n > 128 || bytes.length < 39 + n) return null;
    final k = bytes[38 + n];
    if (k < 1 || k > 24 || bytes.length != 39 + n + k) return null;
    try {
      return StickerEnvelope(
        sourceUrl: ascii.decode(bytes.sublist(6, 6 + n)),
        packSha256: bytes
            .sublist(6 + n, 38 + n)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        stickerId: ascii.decode(bytes.sublist(39 + n)),
      );
    } on FormatException {
      return null;
    }
  }
}
