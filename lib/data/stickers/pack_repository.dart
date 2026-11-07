import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/stickers/wire_codec.dart';
import '../database.dart';
import 'media_verifier.dart';
import 'source_client.dart';
import 'source_models.dart';
import 'source_repository.dart';
import 'sticker_http.dart';

class InstalledStickerPack {
  const InstalledStickerPack(
    this.manifest,
    this.origins,
    this.preferredSourceUrl,
  );
  final StickerManifest manifest;
  final Set<String> origins;
  final String preferredSourceUrl;
  String get hash => manifest.packSha256;
}

class StickerInstallProgress {
  const StickerInstallProgress(this.hash, this.completedBytes, this.totalBytes);
  final String hash;
  final int completedBytes;
  final int totalBytes;
}

/// Hash-addressed packs, global across all nodes and mirrors. No network during
/// startup or local lookup. The DB is committed only after an atomic rename.
class StickerPackRepository {
  StickerPackRepository({
    required this.client,
    required Future<Directory> Function() directory,
  }) : db = client.sources.db,
       _directory = directory;
  final StickerSourceClient client;
  final AppDatabase db;
  final Future<Directory> Function() _directory;
  final _installed = <String, InstalledStickerPack>{};
  final _damaged = <String>{};
  final _removing = <String>{};
  final _operations = <String, Future<void>>{};
  final _cancellations = <String, StickerCancellation>{};
  final _changes = StreamController<List<InstalledStickerPack>>.broadcast();
  final _progress = StreamController<StickerInstallProgress>.broadcast();
  Future<void>? _initializing;
  late Directory _root;
  bool _disposed = false;
  int _reservedBytes = 0;
  static const defaultQuotaBytes = 200 * 1024 * 1024;

  List<InstalledStickerPack> get installed =>
      List.unmodifiable(_installed.values);
  Set<String> get damagedHashes => Set.unmodifiable(_damaged);
  Stream<StickerInstallProgress> get progress => _progress.stream;
  bool contains(String hash) => _installed.containsKey(hash);
  int get usedBytes => _installed.values.fold(
    0,
    (n, p) => n + p.manifest.downloadBytes + p.manifest.bytes.length,
  );

  Future<void> initialize() => _initializing ??= _initialize().catchError((
    Object error,
    StackTrace stack,
  ) {
    _initializing = null;
    Error.throwWithStackTrace(error, stack);
  });

  Future<void> _directorySafe(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      await directory.create(recursive: true);
    } else if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('Unsafe sticker directory');
    }
  }

  Future<void> _initialize() async {
    _root = await _directory();
    await _directorySafe(_root);
    final packs = Directory('${_root.path}/packs');
    await _directorySafe(packs);
    final records = await db.select(db.stickerInstalls).get();
    final known = records.map((r) => r.packSha256).toSet();
    await for (final entry in _root.list(followLinks: false)) {
      if (entry.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('.install-')) {
        await entry.delete(recursive: true);
      }
    }
    await for (final entry in packs.list(followLinks: false)) {
      if (!known.contains(entry.path.split(Platform.pathSeparator).last)) {
        await entry.delete(recursive: true);
      }
    }
    for (final record in records) {
      try {
        final hash = stickerHash(record.packSha256);
        final manifest = await StickerManifest.parse(
          record.manifestBytes,
          packSha256: hash,
        );
        final origins = (jsonDecode(record.originsJson) as List)
            .cast<String>()
            .toSet();
        for (final url in origins) {
          validateSourceUrl(url);
        }
        if (!origins.contains(record.preferredSourceUrl)) {
          throw const FormatException('Invalid pack origins');
        }
        final packDir = Directory('${packs.path}/$hash');
        if (await FileSystemEntity.type(packDir.path, followLinks: false) !=
                FileSystemEntityType.directory ||
            await FileSystemEntity.type(
                  '${packDir.path}/media',
                  followLinks: false,
                ) !=
                FileSystemEntityType.directory) {
          throw const FileSystemException('Missing sticker directory');
        }
        final onDisk = await _readFile(
          '${packDir.path}/manifest.json',
          256 * 1024,
        );
        await StickerManifest.parse(onDisk, packSha256: hash);
        await _verifyFiles(manifest, packDir);
        _installed[hash] = InstalledStickerPack(
          manifest,
          Set.unmodifiable(origins),
          record.preferredSourceUrl,
        );
        if (record.status != 'ready') {
          await (db.update(db.stickerInstalls)
                ..where((r) => r.packSha256.equals(hash)))
              .write(const StickerInstallsCompanion(status: Value('ready')));
        }
      } on Object {
        _damaged.add(record.packSha256);
        // Retain metadata for repair, but do not let corrupt files bypass quota.
        try {
          stickerHash(record.packSha256);
          final dir = Directory('${packs.path}/${record.packSha256}');
          final type = await FileSystemEntity.type(
            dir.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.directory) {
            await dir.delete(recursive: true);
          } else if (type == FileSystemEntityType.link) {
            await Link(dir.path).delete();
          }
        } on FormatException {
          /* Never build a path from an invalid hash. */
        }

        await (db.update(db.stickerInstalls)
              ..where((r) => r.packSha256.equals(record.packSha256)))
            .write(const StickerInstallsCompanion(status: Value('damaged')));
      }
    }
  }

  Future<Uint8List> _readFile(String path, int limit) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Missing sticker file');
    }
    final file = File(path);
    if (await file.length() > limit) {
      throw const FormatException('Sticker file too large');
    }
    return file.readAsBytes();
  }

  Future<void> _verifyFiles(
    StickerManifest manifest,
    Directory dir, {
    StickerCancellation? cancellation,
  }) async {
    final verified = <String>{};
    for (final sticker in manifest.stickers) {
      for (final descriptor in [sticker.media, ?sticker.preview]) {
        cancellation?.check();
        final bytes = await _readFile(
          '${dir.path}/${descriptor.path}',
          descriptor.bytes,
        );
        final preview = identical(descriptor, sticker.preview);
        if (verified.add(descriptor.path)) {
          await verifyStickerFile(bytes, descriptor, png: preview);
        }
        await verifyStickerImage(
          bytes,
          descriptor,
          animated: !preview && sticker.animated,
          frameCount: preview ? null : sticker.frameCount,
          durationMs: preview ? null : sticker.durationMs,
        );
      }
    }
  }

  Stream<List<InstalledStickerPack>> watchInstalled() {
    // Subscribe before the initial async read to avoid losing an install event.
    late StreamController<List<InstalledStickerPack>> output;
    StreamSubscription<List<InstalledStickerPack>>? subscription;
    output = StreamController(
      onListen: () async {
        subscription = _changes.stream.listen(
          output.add,
          onError: output.addError,
          onDone: output.close,
        );
        try {
          await initialize();
          if (!output.isClosed) output.add(installed);
        } catch (e, s) {
          if (!output.isClosed) output.addError(e, s);
        }
      },
      onCancel: () async {
        await subscription?.cancel();
      },
    );
    return output.stream;
  }

  File file(String hash, StickerManifestEntry sticker, {bool still = false}) {
    stickerHash(hash);
    final descriptor = still && sticker.preview != null
        ? sticker.preview!
        : sticker.media;
    return File('${_root.path}/packs/$hash/${descriptor.path}');
  }

  void cancel(String hash) => _cancellations[hash]?.cancel();
  void _emit() {
    if (!_changes.isClosed) _changes.add(installed);
  }

  Future<void> install(
    String sourceUrl,
    String hash, {
    StickerCancellation? cancellation,
  }) {
    validateSourceUrl(sourceUrl);
    stickerHash(hash);
    if (_disposed) throw StateError('Sticker repository is disposed');
    if (_removing.contains(hash)) {
      throw StateError('Sticker operation in progress');
    }
    return _operations.putIfAbsent(hash, () {
      final token = cancellation ?? StickerCancellation();
      _cancellations[hash] = token;
      return _install(sourceUrl, hash, token).whenComplete(() {
        _operations.remove(hash);
        _cancellations.remove(hash);
      });
    });
  }

  Future<void> _install(
    String sourceUrl,
    String hash,
    StickerCancellation token,
  ) async {
    final timer = Timer(const Duration(minutes: 10), token.cancel);
    Directory? staging;
    StreamSubscription<List<StickerSourceState>>? permission;
    var reserved = 0;
    try {
      await initialize();
      token.check();
      await client.requireAllowed(sourceUrl);
      permission = client.sources.watchSources().listen((states) {
        final source = states.where((s) => s.url == sourceUrl).firstOrNull;
        final mirror = client.currentMirror()?.toString();
        if (source == null ||
            source.record.blocked ||
            (!source.record.manualEnabled &&
                !source.bindings.any((b) => b.mirrorBaseUrl == mirror))) {
          token.cancel();
        }
      });
      final preview = await client.preview(
        sourceUrl,
        hash,
        userConsent: true,
        cancellation: token,
      );
      await client.requireAllowed(sourceUrl);
      final manifest = preview.manifest;
      final existing = _installed[hash];
      if (existing != null) {
        token.check();
        final origins = {...existing.origins, sourceUrl};
        await (db.update(
          db.stickerInstalls,
        )..where((r) => r.packSha256.equals(hash))).write(
          StickerInstallsCompanion(
            originsJson: Value(jsonEncode(origins.toList())),
          ),
        );
        _installed[hash] = InstalledStickerPack(
          existing.manifest,
          Set.unmodifiable(origins),
          existing.preferredSourceUrl,
        );
        _emit();
        return;
      }
      final quota =
          int.tryParse(
            await db.getSetting(AppSettingKeys.stickerQuotaBytes) ?? '',
          ) ??
          defaultQuotaBytes;
      if (usedBytes +
              _reservedBytes +
              manifest.downloadBytes +
              manifest.bytes.length >
          quota) {
        throw StateError('Sticker storage quota exceeded');
      }
      reserved = manifest.downloadBytes + manifest.bytes.length;
      _reservedBytes += reserved;
      staging = Directory('${_root.path}/.install-$hash');
      if (await staging.exists()) await staging.delete(recursive: true);
      await _directorySafe(staging);
      await _directorySafe(Directory('${staging.path}/media'));
      final files = {
        for (final s in manifest.stickers)
          for (final f in [s.media, ?s.preview]) f.path: f,
      };
      var completed = 0;
      for (final descriptor in files.values) {
        await client.requireAllowed(sourceUrl);
        token.check();
        final response = await client.http.fetch(
          preview.descriptor.manifestUrl(hash).resolve(descriptor.path),
          sourceUrl: sourceUrl,
          limit: descriptor.bytes,
          contentType: descriptor.path.endsWith('.png')
              ? 'image/png'
              : 'image/webp',
          cancellation: token,
        );
        await verifyStickerFile(
          response.bytes,
          descriptor,
          png: descriptor.path.endsWith('.png'),
        );
        await File(
          '${staging.path}/${descriptor.path}',
        ).writeAsBytes(response.bytes, flush: true);
        completed += descriptor.bytes;
        if (!_progress.isClosed) {
          _progress.add(
            StickerInstallProgress(hash, completed, manifest.downloadBytes),
          );
        }
      }
      await _verifyFiles(manifest, staging, cancellation: token);
      await File(
        '${staging.path}/manifest.json',
      ).writeAsBytes(manifest.bytes, flush: true);
      await client.requireAllowed(sourceUrl);
      token.check();
      final destination = Directory('${_root.path}/packs/$hash');
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await destination.delete(recursive: true);
      }
      await staging.rename(destination.path);
      try {
        await db
            .into(db.stickerInstalls)
            .insertOnConflictUpdate(
              StickerInstallsCompanion.insert(
                packSha256: hash,
                manifestBytes: manifest.bytes,
                originsJson: jsonEncode([sourceUrl]),
                preferredSourceUrl: sourceUrl,
                bytes: manifest.downloadBytes + manifest.bytes.length,
                installedAt: DateTime.now(),
                status: const Value('ready'),
              ),
            );
      } on Object {
        await destination.delete(recursive: true);
        rethrow;
      }
      _installed[hash] = InstalledStickerPack(
        manifest,
        Set.unmodifiable({sourceUrl}),
        sourceUrl,
      );
      _damaged.remove(hash);
      _emit();
    } finally {
      await permission?.cancel();
      timer.cancel();
      _reservedBytes -= reserved;
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> remove(String hash) {
    stickerHash(hash);
    if (_operations.containsKey(hash) || !_removing.add(hash)) {
      throw StateError('Sticker operation in progress');
    }
    return _remove(hash).whenComplete(() => _removing.remove(hash));
  }

  Future<void> _remove(String hash) async {
    await initialize();
    await (db.delete(
      db.stickerInstalls,
    )..where((r) => r.packSha256.equals(hash))).go();
    _installed.remove(hash);
    _damaged.remove(hash);
    _emit();
    final dir = Directory('${_root.path}/packs/$hash');
    if (await FileSystemEntity.type(dir.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      await dir.delete(recursive: true);
    }
  }

  void dispose() {
    _disposed = true;
    for (final token in _cancellations.values) {
      token.cancel();
    }
    _changes.close();
    _progress.close();
  }
}
