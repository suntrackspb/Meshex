import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/sticker_store.dart';
import '../data/stickers.dart';
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
