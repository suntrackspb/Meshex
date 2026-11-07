import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/stickers/wire_codec.dart';
import 'strict_json.dart';

bool _match(String pattern, String value) {
  final m = RegExp(pattern).matchAsPrefix(value);
  return m != null && m.end == value.length;
}

String stickerHash(Object? value) {
  if (value is! String || !_match(r'[a-f0-9]{64}', value)) {
    throw const FormatException('Invalid sticker hash');
  }
  return value;
}

String _text(Object? value, int max, {bool empty = false}) {
  if (value is! String ||
      value.runes.length > max ||
      (!empty && value.trim().isEmpty) ||
      value.runes.any((c) => c < 32 || (c >= 127 && c <= 159))) {
    throw const FormatException('Invalid sticker text');
  }
  return value;
}

String _id(Object? value, int max) {
  if (value is! String || !_match('[A-Za-z0-9_-]{1,$max}', value)) {
    throw const FormatException('Invalid sticker ID');
  }
  return value;
}

int _integer(Object? value, int max, {int min = 1}) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid sticker number');
  }
  return value;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

List<dynamic> _list(Object? value, int max, {bool nonempty = false}) {
  if (value is! List || value.length > max || (nonempty && value.isEmpty)) {
    throw const FormatException('Invalid sticker list');
  }
  return value;
}

void _schema(Map<String, dynamic> j, String type) {
  if (j['schema'] != 'meshex.stickers.$type' ||
      j['version'] is! int ||
      j['version'] != 1) {
    throw const FormatException('Unsupported sticker schema');
  }
}

Uri? _link(Object? value) {
  if (value == null) return null;
  final raw = _text(value, 2048);
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Expected HTTPS attribution link');
  }
  return uri;
}

DateTime? _utcDate(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?Z$',
  ).firstMatch(value);
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final time = DateTime.tryParse(value);
  if (time == null ||
      time.year != parts[0] ||
      time.month != parts[1] ||
      time.day != parts[2] ||
      time.hour != parts[3] ||
      time.minute != parts[4] ||
      time.second != parts[5]) {
    return null;
  }
  return time;
}

class StickerSourceDescriptor {
  StickerSourceDescriptor._(
    this.url,
    this.name,
    this.operatorName,
    this.operatorContact,
  );
  final Uri url;
  final String name;
  final String operatorName;
  final String operatorContact;
  Uri get catalogUrl => url.resolve('catalog.json');
  Uri manifestUrl(String hash) =>
      url.resolve('packs/${stickerHash(hash)}/manifest.json');

  factory StickerSourceDescriptor.parse(
    List<int> bytes, {
    required String sourceUrl,
  }) {
    final url = validateSourceUrl(sourceUrl);
    final j = decodeStickerJson(bytes, limit: 64 * 1024);
    _schema(j, 'source');
    if (j['canonical_url'] != sourceUrl || j['catalog_url'] != 'catalog.json') {
      throw const FormatException('Source URL mismatch');
    }
    final op = _map(j['operator']);
    return StickerSourceDescriptor._(
      url,
      _text(j['name'], 160),
      _text(op['name'], 160),
      _text(op['contact'], 256),
    );
  }
}

class StickerRevision {
  StickerRevision._(
    this.id,
    this.revision,
    this.title,
    this.packSha256,
    this.stickerCount,
    this.downloadBytes,
    this.publishedAt,
    this.status,
  );
  final String id;
  final String revision;
  final String title;
  final String packSha256;
  final int stickerCount;
  final int downloadBytes;
  final DateTime publishedAt;
  final String status;
  bool get canInstall => status == 'active';
  String get manifestPath => 'packs/$packSha256/manifest.json';

  factory StickerRevision.fromJson(Map<String, dynamic> j) {
    final hash = stickerHash(j['pack_sha256']);
    final published = _text(j['published_at'], 40);
    final time = _utcDate(published);
    if (j['manifest_url'] != 'packs/$hash/manifest.json' ||
        !published.endsWith('Z') ||
        time == null ||
        !time.isUtc) {
      throw const FormatException('Invalid sticker revision location or date');
    }
    return StickerRevision._(
      _id(j['id'], 48),
      _text(j['revision'], 64),
      _text(j['title'], 160),
      hash,
      _integer(j['sticker_count'], 100),
      _integer(j['download_bytes'], 50 * 1024 * 1024),
      time,
      _text(j['status'], 64),
    );
  }
}

class StickerSourceCatalog {
  StickerSourceCatalog._(this.revisions);
  final List<StickerRevision> revisions;
  factory StickerSourceCatalog.parse(List<int> bytes) {
    final j = decodeStickerJson(bytes, limit: 1024 * 1024);
    _schema(j, 'catalog');
    final seen = <String>{};
    final revisions = [
      for (final item in _list(j['packs'], 200))
        StickerRevision.fromJson(_map(item)),
    ];
    for (final revision in revisions) {
      if (!seen.add(revision.packSha256)) {
        throw const FormatException('Duplicate revision hash');
      }
    }
    return StickerSourceCatalog._(List.unmodifiable(revisions));
  }
}

class StickerFileDescriptor {
  StickerFileDescriptor._(
    this.path,
    this.sha256,
    this.bytes,
    this.width,
    this.height,
  );
  final String path;
  final String sha256;
  final int bytes;
  final int width;
  final int height;
  factory StickerFileDescriptor.fromJson(
    Map<String, dynamic> j, {
    required bool preview,
  }) {
    final hash = stickerHash(j['sha256']);
    final expected = 'media/$hash.${preview ? 'png' : 'webp'}';
    if (j['url'] != expected) throw const FormatException('Invalid media path');
    return StickerFileDescriptor._(
      expected,
      hash,
      _integer(j['bytes'], 5 * 1024 * 1024),
      _integer(j['width'], 512),
      _integer(j['height'], 512),
    );
  }
}

class StickerManifestEntry {
  StickerManifestEntry._(
    this.id,
    this.emoji,
    this.alt,
    this.animated,
    this.media,
    this.preview,
    this.durationMs,
    this.frameCount,
  );
  final String id;
  final String emoji;
  final String alt;
  final bool animated;
  final StickerFileDescriptor media;
  final StickerFileDescriptor? preview;
  final int? durationMs;
  final int? frameCount;

  factory StickerManifestEntry.fromJson(Map<String, dynamic> j) {
    if (j['animated'] is! bool) {
      throw const FormatException('Expected animation flag');
    }
    final animated = j['animated'] as bool;
    final preview = j['preview'] == null
        ? null
        : StickerFileDescriptor.fromJson(_map(j['preview']), preview: true);
    if (animated && preview == null) {
      throw const FormatException('Animation needs preview');
    }
    return StickerManifestEntry._(
      _id(j['id'], 24),
      _text(j['emoji'] ?? '', 64, empty: true),
      _text(j['alt'], 256),
      animated,
      StickerFileDescriptor.fromJson(_map(j['media']), preview: false),
      preview,
      animated ? _integer(j['duration_ms'], 3000) : null,
      animated ? _integer(j['frame_count'], 90) : null,
    );
  }
}

class StickerManifest {
  StickerManifest._(
    this._bytes,
    this.packSha256,
    this.id,
    this.revision,
    this.title,
    this.authors,
    this.attributionUrl,
    this.licenseId,
    this.licenseUrl,
    this.stickers,
    this.downloadBytes,
  );
  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  final String packSha256;
  final String id;
  final String revision;
  final String title;
  final List<String> authors;
  final Uri? attributionUrl;
  final String? licenseId;
  final Uri? licenseUrl;
  final List<StickerManifestEntry> stickers;
  final int downloadBytes;

  /// Hash received bytes, never a reserialized JSON document.
  static Future<StickerManifest> parse(
    List<int> bytes, {
    required String packSha256,
  }) async {
    stickerHash(packSha256);
    if (bytes.length > 256 * 1024) {
      throw const FormatException('Manifest too large');
    }
    final immutable = Uint8List.fromList(bytes);
    final digest = await Sha256().hash(immutable);
    final hash = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (hash != packSha256) {
      throw const FormatException('Manifest hash mismatch');
    }
    final j = decodeStickerJson(immutable, limit: 256 * 1024);
    _schema(j, 'pack');
    if (!j.containsKey('license')) {
      throw const FormatException('Missing license');
    }
    final license = j['license'] == null ? null : _map(j['license']);
    final stickers = [
      for (final item in _list(j['stickers'], 100, nonempty: true))
        StickerManifestEntry.fromJson(_map(item)),
    ];
    final ids = <String>{};
    final files = <String, StickerFileDescriptor>{};
    for (final sticker in stickers) {
      if (!ids.add(sticker.id)) {
        throw const FormatException('Duplicate sticker ID');
      }
      for (final file in [sticker.media, ?sticker.preview]) {
        final previous = files[file.sha256];
        if (previous != null &&
            (previous.path != file.path ||
                previous.bytes != file.bytes ||
                previous.width != file.width ||
                previous.height != file.height)) {
          throw const FormatException('Conflicting media metadata');
        }
        files[file.sha256] = file;
      }
    }
    final size = files.values.fold(0, (n, file) => n + file.bytes);
    if (size > 50 * 1024 * 1024) throw const FormatException('Pack too large');
    return StickerManifest._(
      immutable,
      packSha256,
      _id(j['id'], 48),
      _text(j['revision'], 64),
      _text(j['title'], 160),
      List.unmodifiable([
        for (final author in _list(j['authors'], 16))
          _text(_map(author)['name'], 160),
      ]),
      _link(j['attribution_url']),
      license == null ? null : _text(license['id'], 160),
      license == null ? null : _link(license['url']),
      List.unmodifiable(stickers),
      size,
    );
  }
}
