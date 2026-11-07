import 'dart:convert';

/// Local catalog key; this is not a radio message or wire representation.
class StickerKey {
  const StickerKey(this.pack, this.id);
  final String pack;
  final String id;
}

final _packId = RegExp(r'^[A-Za-z0-9_-]{1,48}$');
final _stickerId = RegExp(r'^[A-Za-z0-9_-]{1,24}$');
bool _matchesId(RegExp pattern, String value) {
  final match = pattern.firstMatch(value);
  return match != null && match.end == value.length;
}

/// Downloadable media is described by a server manifest, never bundled.
class StickerMedia {
  const StickerMedia({
    required this.url,
    required this.sha256,
    required this.bytes,
  });
  final Uri url;
  final String sha256;
  final int bytes;

  factory StickerMedia.fromJson(Map<String, dynamic> json, Uri base) {
    final url = base.resolve(json['url'] as String);
    final hash = json['sha256'] as String;
    final bytes = json['bytes'] as int;
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        bytes <= 0 ||
        bytes > 5 * 1024 * 1024) {
      throw const FormatException('Invalid sticker media');
    }
    return StickerMedia(url: url, sha256: hash, bytes: bytes);
  }

  Map<String, dynamic> toJson() => {
    'url': '$url',
    'sha256': sha256,
    'bytes': bytes,
  };
}

class StickerAsset {
  const StickerAsset({
    required this.ref,
    required this.emoji,
    required this.animated,
    required this.media,
    this.preview,
  });
  final StickerKey ref;
  final String emoji;
  final bool animated;
  final StickerMedia media;
  final StickerMedia? preview;
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.title,
    required this.stickers,
    this.author,
    this.source,
    this.license,
  });
  final String id;
  final String title;
  final String? author;
  final String? source;
  final String? license;
  final List<StickerAsset> stickers;
  bool get animated => stickers.any((s) => s.animated);
  int get bytes =>
      stickers.fold(0, (n, s) => n + s.media.bytes + (s.preview?.bytes ?? 0));

  factory StickerPack.fromJson(Map<String, dynamic> json, Uri base) {
    final id = json['id'] as String;
    final title = json['title'] as String;
    final raw = json['stickers'] as List;
    if (!_matchesId(_packId, id) ||
        title.trim().isEmpty ||
        title.length > 160 ||
        raw.isEmpty ||
        raw.length > 100) {
      throw const FormatException('Invalid sticker pack');
    }
    final ids = <String>{};
    final stickers = <StickerAsset>[];
    for (final item in raw) {
      final j = (item as Map).cast<String, dynamic>();
      final ref = StickerKey(id, j['id'] as String);
      if (!_matchesId(_stickerId, ref.id) || !ids.add(ref.id)) {
        throw const FormatException('Invalid or duplicate sticker ID');
      }
      final animated = j['animated'] == true;
      final preview = j['preview'] == null
          ? null
          : StickerMedia.fromJson((j['preview'] as Map).cast(), base);
      if (animated && preview == null) {
        throw const FormatException('Animated stickers need a still preview');
      }
      stickers.add(
        StickerAsset(
          ref: ref,
          emoji: j['emoji'] as String? ?? '',
          animated: animated,
          media: StickerMedia.fromJson((j['media'] as Map).cast(), base),
          preview: preview,
        ),
      );
    }
    final pack = StickerPack(
      id: id,
      title: title,
      stickers: List.unmodifiable(stickers),
      author: json['author'] as String?,
      source: json['source'] as String?,
      license: json['license'] as String?,
    );
    if (pack.bytes > 50 * 1024 * 1024) {
      throw const FormatException('Sticker pack too large');
    }
    return pack;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'source': source,
    'license': license,
    'stickers': [
      for (final s in stickers)
        {
          'id': s.ref.id,
          'emoji': s.emoji,
          'animated': s.animated,
          'media': s.media.toJson(),
          if (s.preview != null) 'preview': s.preview!.toJson(),
        },
    ],
  };
}

List<StickerPack> parseStickerCatalog(String body, Uri base) {
  final json = (jsonDecode(body) as Map).cast<String, dynamic>();
  if (json['version'] != 1) {
    throw const FormatException('Unsupported sticker catalog');
  }
  final raw = json['packs'] as List;
  if (raw.length > 200) throw const FormatException('Too many sticker packs');
  final packs = [
    for (final p in raw) StickerPack.fromJson((p as Map).cast(), base),
  ];
  if (packs.map((p) => p.id).toSet().length != packs.length) {
    throw const FormatException('Duplicate sticker pack ID');
  }
  return List.unmodifiable(packs);
}
