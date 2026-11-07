import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'stickers.dart';

/// Downloaded packs live in Application Support and remain available offline.
/// A pack becomes visible only after all files pass size and SHA-256 checks.
class StickerStore {
  StickerStore({
    required Future<Directory> Function() directory,
    http.Client? client,
  }) : _directory = directory,
       _client = client ?? http.Client();

  final Future<Directory> Function() _directory;
  final http.Client _client;
  final _changes = StreamController<void>.broadcast();
  final _installed = <String, StickerPack>{};
  final _busy = <String>{};
  Future<void>? _initializing;
  bool _ready = false;
  late Directory _root;

  List<StickerPack> get installed => List.unmodifiable(_installed.values);
  bool contains(String id) => _installed.containsKey(id);

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    _root = await _directory();
    await _root.create(recursive: true);
    await for (final entity in _root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      try {
        final raw = await File('${entity.path}/manifest.json').readAsString();
        final pack = StickerPack.fromJson(
          (jsonDecode(raw) as Map).cast(),
          Uri(),
        );
        if (entity.path.split(Platform.pathSeparator).last != pack.id) continue;
        var complete = true;
        for (final s in pack.stickers) {
          final media = File('${entity.path}/${s.ref.id}.webp');
          if (!await media.exists() || await media.length() != s.media.bytes) {
            complete = false;
            break;
          }
          if (s.preview != null) {
            final preview = File('${entity.path}/${s.ref.id}.png');
            if (!await preview.exists() ||
                await preview.length() != s.preview!.bytes) {
              complete = false;
              break;
            }
          }
        }
        if (complete) _installed[pack.id] = pack;
      } on Object {
        // Interrupted or damaged packs are not offered for sending.
      }
    }
    _ready = true;
  }

  Stream<List<StickerPack>> watchInstalled() async* {
    if (!_ready) await initialize();
    yield installed;
    await for (final _ in _changes.stream) {
      yield installed;
    }
  }

  StickerAsset? find(StickerKey ref) {
    final pack = _installed[ref.pack];
    return pack?.stickers.where((s) => s.ref.id == ref.id).firstOrNull;
  }

  File file(StickerAsset sticker, {bool still = false}) => File(
    '${_root.path}/${sticker.ref.pack}/${sticker.ref.id}'
    '${still && sticker.preview != null ? '.png' : '.webp'}',
  );

  static Uri catalogUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Expected an HTTPS catalog URL');
    }
    return uri;
  }

  Future<Uint8List> _read(Uri uri, int limit) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    if ((response.contentLength ?? 0) > limit) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Sticker response too large');
    }
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator(response.stream);
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    try {
      while (await iterator.moveNext().timeout(
        deadline.difference(DateTime.now()),
      )) {
        final chunk = iterator.current;
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Sticker response too large');
        }
        bytes.add(chunk);
      }
    } finally {
      await iterator.cancel();
    }
    return bytes.takeBytes();
  }

  Future<List<StickerPack>> catalog(String url) async {
    final uri = catalogUri(url);
    final bytes = await _read(uri, 1024 * 1024);
    return parseStickerCatalog(utf8.decode(bytes), uri);
  }

  Future<void> _download(
    StickerMedia media,
    File target, {
    required bool png,
  }) async {
    final bytes = await _read(media.url, media.bytes);
    final hash = await Sha256().hash(bytes);
    final hex = hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final correctType = png
        ? bytes.length >= 8 &&
              bytes.take(8).join(',') == '137,80,78,71,13,10,26,10'
        : bytes.length >= 12 &&
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    if (bytes.length != media.bytes || hex != media.sha256 || !correctType) {
      throw const FormatException('Sticker integrity check failed');
    }
    await target.writeAsBytes(bytes, flush: true);
  }

  Future<void> install(StickerPack pack) async {
    await initialize();
    // Validate programmatically supplied packs too, before using any paths.
    pack = StickerPack.fromJson(pack.toJson(), Uri());
    if (_installed.containsKey(pack.id)) {
      final old = _installed[pack.id]!;
      final oldMedia = [
        for (final s in old.stickers)
          '${s.ref.id}:${s.media.sha256}:${s.preview?.sha256}',
      ];
      final newMedia = [
        for (final s in pack.stickers)
          '${s.ref.id}:${s.media.sha256}:${s.preview?.sha256}',
      ];
      if (oldMedia.join('|') != newMedia.join('|')) {
        throw const FormatException(
          'A published pack ID cannot change contents',
        );
      }
      return;
    }
    if (!_busy.add(pack.id)) throw StateError('Pack operation already running');
    final staging = Directory(
      '${_root.path}/.install-${pack.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.create();
      for (final s in pack.stickers) {
        await _download(
          s.media,
          File('${staging.path}/${s.ref.id}.webp'),
          png: false,
        );
        if (s.preview != null) {
          await _download(
            s.preview!,
            File('${staging.path}/${s.ref.id}.png'),
            png: true,
          );
        }
      }
      await File(
        '${staging.path}/manifest.json',
      ).writeAsString(jsonEncode(pack.toJson()), flush: true);
      final destination = Directory('${_root.path}/${pack.id}');
      // Only an incomplete old install can remain here; a live pack was handled above.
      if (await destination.exists()) await destination.delete(recursive: true);
      await staging.rename(destination.path);
      _installed[pack.id] = pack;
      _changed();
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      _busy.remove(pack.id);
    }
  }

  Future<void> remove(String id) async {
    await initialize();
    if (!_installed.containsKey(id)) return;
    if (!_busy.add(id)) throw StateError('Pack operation already running');
    try {
      await Directory('${_root.path}/$id').delete(recursive: true);
      _installed.remove(id);
      _changed();
    } finally {
      _busy.remove(id);
    }
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() {
    _client.close();
    _changes.close();
  }
}
