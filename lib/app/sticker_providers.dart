import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/sticker_store.dart';
import '../data/stickers.dart';
import '../data/stickers/source_repository.dart';
import 'providers.dart';

final stickerStoreProvider = Provider<StickerStore>((ref) {
  final store = StickerStore(
    directory: () async {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/stickers-v1');
    },
  );
  ref.onDispose(store.dispose);
  return store;
});

final installedStickersProvider = StreamProvider<List<StickerPack>>(
  (ref) => ref.watch(stickerStoreProvider).watchInstalled(),
);

final stickerCatalogUrlProvider = StreamProvider<String>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchSetting(AppSettingKeys.stickerCatalogUrl)
      .map((url) => url ?? const String.fromEnvironment('STICKER_CATALOG_URL')),
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

final stickerSourcesProvider = StreamProvider<List<StickerSourceState>>((ref) {
  ref.watch(stickerSourceSyncProvider);
  final mirror = ref.watch(mirrorApiProvider)?.baseUrl;
  return ref
      .watch(stickerSourceRepositoryProvider)
      .watchSources(currentMirror: mirror);
});
