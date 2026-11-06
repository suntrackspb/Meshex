import 'dart:convert';

import '../core/proto/mesh.dart';

/// PRIVATE_APP is shared with other applications: accept only our own envelope.
abstract final class StickerProtocol {
  static const port = PortNum.PRIVATE_APP;
  static const prefix = 'sticker:eto:s1:';
  static const maxBytes = 100;
  static final _pattern = RegExp(
    r'^sticker:eto:s1:([A-Za-z0-9_-]{1,48}):([A-Za-z0-9_-]{1,24})$',
  );

  static StickerRef? parse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null || match.end != text.length) return null;
    return StickerRef(match[1]!, match[2]!);
  }

  static String preview(String body, int portnum, String label) {
    final ref = portnum == port.value ? parse(body) : null;
    if (ref == null) return body;
    return '$label ${StickerCatalog.find(ref)?.emoji ?? '▫️'}';
  }

  static StickerRef? decode(List<int> bytes) {
    if (bytes.length > maxBytes) return null;
    try {
      return parse(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }
}

/// IDs identify immutable pack contents; never renumber published stickers.
class StickerRef {
  const StickerRef(this.pack, this.id);

  final String pack;
  final String id;

  String get wire => '${StickerProtocol.prefix}$pack:$id';
  List<int> encode() {
    if (StickerProtocol.parse(wire) == null) {
      throw ArgumentError('Invalid sticker identifier');
    }
    return utf8.encode(wire);
  }
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.title,
    required this.animated,
    required this.emojis,
  });

  final String id;
  final String title;
  final bool animated;
  final List<String> emojis;

  List<StickerAsset> get stickers => [
    for (var i = 0; i < emojis.length; i++)
      StickerAsset(
        ref: StickerRef(id, '${i + 1}'.padLeft(3, '0')),
        emoji: emojis[i],
        animated: animated,
      ),
  ];
}

class StickerAsset {
  const StickerAsset({
    required this.ref,
    required this.emoji,
    required this.animated,
  });

  final StickerRef ref;
  final String emoji;
  final bool animated;
  String get path => 'assets/stickers/${ref.pack}/${ref.id}.webp';
}

abstract final class StickerCatalog {
  static const packs = <StickerPack>[
    StickerPack(
      id: 'biscuit_vk',
      title: 'Бисквит',
      animated: false,
      emojis: [
        "☺️",
        "❤️",
        "☹️",
        "😽",
        "🙈",
        "😱",
        "☹️",
        "🎶",
        "☺️",
        "😳",
        "☹️",
        "❤️",
        "😬",
        "☺️",
        "😡",
        "🥺",
        "😰",
        "👌",
        "😡",
        "❓",
        "☺️",
        "🐁",
        "☺️",
        "🔪",
        "🙅‍♂️",
        "❓",
        "🤦‍♀️",
        "❓",
        "😡",
        "🤨",
        "🍞",
        "😡",
        "🌹",
        "😐",
        "🤔",
        "🙈",
        "🔝",
        "🤓",
        "😠",
        "🍪",
        "😰",
        "😭",
        "🤬",
        "☺️",
        "☹️",
        "😡",
        "🖕",
        "😴",
        "🏡",
      ],
    ),
    StickerPack(
      id: 'MemeS1ick3r',
      title: 'Мемы',
      animated: true,
      emojis: ["😆", "🤣", "🤣", "😆", "😃", "🤨", "😂", "👏", "🌚", "😂"],
    ),
  ];

  static StickerAsset? find(StickerRef ref) {
    for (final pack in packs) {
      if (pack.id != ref.pack) continue;
      for (final sticker in pack.stickers) {
        if (sticker.ref.id == ref.id) return sticker;
      }
    }
    return null;
  }
}
