import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/data/sticker_store.dart';
import 'package:meshex/data/stickers.dart';
import 'package:meshex/features/chat/sticker_library.dart';
import 'package:meshex/l10n/l10n.dart';

import 'sticker_fixtures.dart';

void main() {
  late Directory directory;
  late StickerStore store;
  late StickerPack staticPack;
  late StickerPack animatedPack;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('meshex-picker-test-');
    staticPack = await testStickerPack();
    animatedPack = await testStickerPack(id: 'animated_pack', animated: true);
    store = StickerStore(
      directory: () async => directory,
      client: testStickerClient([staticPack, animatedPack]),
    );
    await store.initialize();
  });
  tearDown(() async {
    store.dispose();
    await directory.delete(recursive: true);
  });

  Widget app(Widget child, {String url = ''}) => ProviderScope(
    overrides: [
      stickerStoreProvider.overrideWithValue(store),
      stickerCatalogUrlProvider.overrideWith((_) => Stream.value(url)),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'empty library offers a configurable server without bundling packs',
    (tester) async {
      await tester.pumpWidget(app(const StickerLibrary()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Установленных паков пока нет'),
        findsOneWidget,
      );
      await tester.tap(find.text('Каталог').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Укажите адрес каталога'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library previews installed stickers without selecting or sending a message',
    (tester) async {
      await tester.runAsync(() async {
        await store.install(staticPack);
        await store.install(animatedPack);
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showStickerLibrary(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Test pack · 1'), findsOneWidget);
      await tester.tap(find.text('Animation · 1'));
      await tester.pump();
      await tester.tap(find.byType(StickerImage).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(StickerLibrary), findsOneWidget);
      expect(find.textContaining('Отправка пока недоступна'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('installing a pack updates the open library', (tester) async {
    await tester.pumpWidget(app(const StickerLibrary()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Установленных паков пока нет'), findsOneWidget);
    await tester.runAsync(() => store.install(staticPack));
    await tester.pumpAndSettle();
    expect(find.text('Test pack · 1'), findsOneWidget);
    expect(find.byType(StickerImage), findsOneWidget);
  });

  testWidgets(
    'catalog shows attribution and a download action from a configurable URL',
    (tester) async {
      await tester.pumpWidget(
        app(
          const StickerLibrary(),
          url: 'https://stickers.example/catalog.json',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Каталог').first);
      // HTTP's response stream completes on the real event queue.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      await tester.pumpAndSettle();
      expect(find.text('Test pack · 1'), findsOneWidget);
      expect(find.textContaining('CC0-1.0'), findsWidgets);
      expect(find.byTooltip('Скачать пак'), findsNWidgets(2));
      expect(store.installed, isEmpty);
    },
  );

  testWidgets('reduced motion reads the cached still image', (tester) async {
    await tester.runAsync(() => store.install(animatedPack));
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StickerImage(sticker: animatedPack.stickers.single),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as FileImage).file.path,
      endsWith('/animated_pack/001.png'),
    );
  });
}
