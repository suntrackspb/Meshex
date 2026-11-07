import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/stickers/pack_repository.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/features/stickers/sticker_library_page.dart';
import 'package:meshex/l10n/l10n.dart';

import 'sticker_fixtures.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late StickerPackRepository store;
  late StickerSourceRepository sources;
  late TestStickerHttp http;
  late List<StickerSourceState> sourceStates;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('meshex-library-');
    db = AppDatabase(NativeDatabase.memory());
    sources = StickerSourceRepository(db);
    await sources.addManual(testSourceUrl);
    http = TestStickerHttp();
    store = StickerPackRepository(
      client: StickerSourceClient(sources, http, currentMirror: () => null),
      directory: () async => directory,
    );
    await store.initialize();
    sourceStates = await sources.watchSources().first;
  });
  tearDown(() async {
    store.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  Widget app(
    Widget child, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      mirrorApiProvider.overrideWithValue(null),
      stickerPackRepositoryProvider.overrideWithValue(store),
      stickerSourcesProvider.overrideWith((_) => Stream.value(sourceStates)),
      stickerQuotaProvider.overrideWith((_) => Stream.value(200 * 1024 * 1024)),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      theme: ThemeData(brightness: brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'empty library never fetches sources and offers source management',
    (tester) async {
      await tester.pumpWidget(app(const StickerLibraryPage()));
      await settle(tester);
      expect(
        find.textContaining('Установленных паков пока нет'),
        findsOneWidget,
      );
      await tester.tap(find.text('Источники'));
      await settle(tester);
      expect(find.text('Добавить источник'), findsOneWidget);
      expect(find.textContaining(testSourceUrl), findsOneWidget);
      expect(http.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'installation updates an already open library without message reload',
    (tester) async {
      await tester.pumpWidget(app(const StickerLibraryPage()));
      await settle(tester);
      await tester.runAsync(() => store.install(testSourceUrl, testPackHash));
      await settle(tester);
      expect(find.text('Demo Colors'), findsOneWidget);
      await tester.tap(find.text('Demo Colors'));
      await settle(tester);
      expect(find.textContaining('CC0-1.0'), findsOneWidget);
      expect(find.byType(StickerImage), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion resolves PNG preview by file hash', (
    tester,
  ) async {
    await tester.runAsync(() => store.install(testSourceUrl, testPackHash));
    final pack = store.installed.single;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StickerImage(
              hash: pack.hash,
              sticker: pack.manifest.stickers.last,
            ),
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as FileImage).file.path,
      endsWith(
        '/packs/$testPackHash/${pack.manifest.stickers.last.preview!.path}',
      ),
    );
  });

  testWidgets('compact dark layout handles large text and disabled source', (
    tester,
  ) async {
    sourceStates = (await tester.runAsync(() async {
      await sources.setBlocked(testSourceUrl, true);
      return sources.watchSources().first;
    }))!;
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        const StickerLibraryPage(),
        brightness: Brightness.dark,
        textScale: 1.6,
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Каталоги'));
    await settle(tester);
    expect(find.text('Источник отключён или заблокирован'), findsOneWidget);
    expect(http.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
