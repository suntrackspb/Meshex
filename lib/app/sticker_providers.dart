import 'dart:io';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/stickers/pack_repository.dart';
import '../data/stickers/source_client.dart';
import '../data/stickers/sticker_http.dart';
import '../data/stickers/source_repository.dart';
import 'providers.dart';

final stickerHttpProvider = Provider<StickerHttp>((ref) => NativeStickerHttp());

final stickerSourceClientProvider = Provider<StickerSourceClient>((ref) {
  return StickerSourceClient(
    ref.watch(stickerSourceRepositoryProvider),
    ref.watch(stickerHttpProvider),
    currentMirror: () => ref.read(mirrorApiProvider)?.baseUrl,
  );
});

final stickerPackRepositoryProvider = Provider<StickerPackRepository>((ref) {
  final repository = StickerPackRepository(
    client: ref.watch(stickerSourceClientProvider),
    directory: () async {
      final support = await getApplicationSupportDirectory();
      // The one-device prototype is not migrated into the public format.
      final prototype = Directory('${support.path}/stickers-v1');
      if (await FileSystemEntity.type(prototype.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await prototype.delete(recursive: true);
      }
      return Directory('${support.path}/stickers-v2');
    },
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final installedStickersProvider = StreamProvider<List<InstalledStickerPack>>(
  (ref) => ref.watch(stickerPackRepositoryProvider).watchInstalled(),
);

final stickerInstallProgressProvider = StreamProvider<StickerInstallProgress>(
  (ref) => ref.watch(stickerPackRepositoryProvider).progress,
);

final stickerQuotaProvider = StreamProvider<int>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchSetting(AppSettingKeys.stickerQuotaBytes)
      .map(
        (v) => int.tryParse(v ?? '') ?? StickerPackRepository.defaultQuotaBytes,
      ),
);

/// Global registry; never depends on databaseProvider (the current node).
final stickerSourceRepositoryProvider = Provider<StickerSourceRepository>(
  (ref) => StickerSourceRepository(ref.watch(appDatabaseProvider)),
);

/// Persist declarations only; this provider performs no requests to sources.
final stickerSourceSyncProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(stickerSourceRepositoryProvider);
  final mirror = ref.watch(mirrorApiProvider)?.baseUrl;
  if (mirror == null) return;
  final loaded = await ref.watch(mirrorCapabilitiesLoadProvider.future);
  if (!ref.mounted) return;
  await repository.reconcileMirror(
    mirror,
    loaded.capabilities?.stickers,
    cached: !loaded.refreshed,
  );
});

/// Reads only local state. Rendering messages and opening the picker must not
/// trigger even a capabilities request or DNS lookup.
final stickerLocalSourcesProvider = StreamProvider<List<StickerSourceState>>((
  ref,
) {
  final mirror = ref.watch(mirrorApiProvider)?.baseUrl;
  return ref
      .watch(stickerSourceRepositoryProvider)
      .watchSources(currentMirror: mirror);
});

final stickerSourcesProvider = StreamProvider<List<StickerSourceState>>((ref) {
  ref.watch(stickerSourceSyncProvider);
  final mirror = ref.watch(mirrorApiProvider)?.baseUrl;
  return ref
      .watch(stickerSourceRepositoryProvider)
      .watchSources(currentMirror: mirror);
});

const recentStickersSettingKey = 'stickers.recent';
typedef RecentSticker = ({String packSha256, String stickerId});

List<RecentSticker> parseRecentStickers(String? value) {
  try {
    final decoded = jsonDecode(value ?? '[]') as List;
    final result = <RecentSticker>[];
    for (final entry in decoded) {
      if (entry is! Map || entry['pack'] is! String || entry['id'] is! String) {
        continue;
      }
      final sticker = (
        packSha256: entry['pack'] as String,
        stickerId: entry['id'] as String,
      );
      if (!result.contains(sticker)) result.add(sticker);
      if (result.length == 20) break;
    }
    return result;
  } catch (_) {
    return [];
  }
}

final recentStickersProvider = StreamProvider<List<RecentSticker>>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchSetting(recentStickersSettingKey)
      .map(parseRecentStickers),
);

Future<void> recordRecentSticker(AppDatabase db, RecentSticker sticker) async {
  final recent = parseRecentStickers(
    await db.getSetting(recentStickersSettingKey),
  );
  recent.remove(sticker);
  recent.insert(0, sticker);
  await db.setSetting(
    recentStickersSettingKey,
    jsonEncode([
      for (final item in recent.take(20))
        {'pack': item.packSha256, 'id': item.stickerId},
    ]),
  );
}
