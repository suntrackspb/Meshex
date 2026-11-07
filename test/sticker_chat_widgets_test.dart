import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/core/stickers/wire_codec.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/stickers/pack_repository.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/features/chat/sticker_message.dart';
import 'package:meshex/features/chat/sticker_picker.dart';
import 'package:meshex/features/stickers/sticker_library_page.dart';
import 'package:meshex/features/stickers/sticker_offer_page.dart';
import 'package:meshex/l10n/l10n.dart';

import 'sticker_fixtures.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late StickerSourceRepository sources;
  late TestStickerHttp http;
  late StickerPackRepository packs;
  late ProviderContainer container;
  var syncCalls = 0;
  var online = true;
  final envelope = StickerEnvelope(
    sourceUrl: testSourceUrl,
    packSha256: testPackHash,
    stickerId: 'blue',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sticker-chat-');
    db = AppDatabase(NativeDatabase.memory());
    sources = StickerSourceRepository(db);
    http = TestStickerHttp();
    packs = StickerPackRepository(
      client: StickerSourceClient(sources, http, currentMirror: () => null),
      directory: () async => directory,
    );
    await packs.initialize();
    syncCalls = 0;
    online = true;
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        mirrorApiProvider.overrideWithValue(null),
        stickerPackRepositoryProvider.overrideWithValue(packs),
        stickerHttpProvider.overrideWithValue(http),
        canSendProvider.overrideWith((_) => online),
        stickerSourceSyncProvider.overrideWith((_) async {
          syncCalls++;
        }),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    packs.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  Widget app(
    Widget child, {
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      theme: ThemeData(brightness: brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 250; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (i >= 10 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          !tester.binding.hasScheduledFrame) {
        break;
      }
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  Future<void> installButton(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      180,
      scrollable: find
          .descendant(
            of: find.byType(StickerOfferPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text(label));
    await settle(tester);
  }

  Future<void> install(WidgetTester tester) async {
    await tester.runAsync(() async {
      await sources.addManual(testSourceUrl);
      await packs.install(testSourceUrl, testPackHash);
    });
    http.calls.clear();
  }

  testWidgets(
    'unknown message and offer page perform no HTTP or capabilities discovery before consent',
    (tester) async {
      await tester.pumpWidget(
        app(IntrinsicWidth(child: StickerMessageBody(envelope: envelope))),
      );
      await settle(tester);
      expect(find.text('Пак не установлен'), findsOneWidget);
      expect(find.text('s.example'), findsOneWidget);
      expect(http.calls, isEmpty);
      expect(syncCalls, 0);
      await tester.tap(find.text('Источник и пак'));
      await settle(tester);
      expect(find.byType(StickerOfferPage), findsOneWidget);
      expect(find.text('Открыть источник'), findsOneWidget);
      expect(http.calls, isEmpty);
      expect(
        await tester.runAsync(() => sources.watchSources().first),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview grants no trust; explicit install updates the existing message and quote, removal restores placeholders',
    (tester) async {
      await tester.pumpWidget(
        app(
          Column(
            children: [
              StickerMessageBody(envelope: envelope),
              StickerMessageBody(envelope: envelope, compact: true),
            ],
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Источник и пак'));
      await settle(tester);
      await tester.tap(find.text('Открыть источник'));
      await settle(tester);
      expect(find.text('Demo Colors'), findsOneWidget);
      expect(find.text('Добавить источник и установить пак'), findsOneWidget);
      expect(http.calls.length, 3);
      expect(http.calls.where((c) => c.url.path.contains('/media/')), isEmpty);
      expect(
        await tester.runAsync(() => sources.watchSources().first),
        isEmpty,
      );
      await installButton(tester, 'Добавить источник и установить пак');
      expect(find.byType(StickerOfferPage), findsNothing);
      expect(find.byType(StickerImage), findsNWidgets(2));
      expect(
        (await tester.runAsync(
          () => sources.watchSources().first,
        ))!.single.record.manualEnabled,
        isTrue,
      );
      await tester.runAsync(() => packs.remove(testPackHash));
      await settle(tester);
      expect(find.byType(StickerImage), findsNothing);
      expect(find.text('Пак не установлен'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'matching hash displays offline from any origin, including a blocked hint',
    (tester) async {
      await install(tester);
      await tester.runAsync(() => sources.setBlocked(testSourceUrl, true));
      final foreign = StickerEnvelope(
        sourceUrl: 'https://foreign.example/source.json',
        packSha256: testPackHash,
        stickerId: 'blue',
      );
      await tester.pumpWidget(
        app(
          Column(
            children: [
              StickerMessageBody(envelope: foreign),
              StickerMessageBody(envelope: envelope),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(StickerImage), findsNWidgets(2));
      expect(http.calls, isEmpty);
      expect(syncCalls, 0);
    },
  );

  testWidgets(
    'missing ID never looks for a newer revision or offers an installation',
    (tester) async {
      await install(tester);
      await tester.pumpWidget(
        app(
          StickerMessageBody(
            envelope: StickerEnvelope(
              sourceUrl: testSourceUrl,
              packSha256: testPackHash,
              stickerId: 'not-present',
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('Стикер отсутствует в этой ревизии'), findsOneWidget);
      expect(find.text('Источник и пак'), findsNothing);
      expect(http.calls, isEmpty);
    },
  );

  testWidgets(
    'picker is local and returns one hash/ID selection without fetching',
    (tester) async {
      await install(tester);
      StickerSelection? selected;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showStickerPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.byType(StickerPicker), findsOneWidget);
      await tester.tap(find.byTooltip('Blue square'));
      await settle(tester);
      expect(selected, (packSha256: testPackHash, stickerId: 'blue'));
      expect(http.calls, isEmpty);
      expect(syncCalls, 0);
    },
  );

  testWidgets(
    'blocked source disables picker send but preserves cached message image',
    (tester) async {
      await install(tester);
      await tester.runAsync(() => sources.setBlocked(testSourceUrl, true));
      StickerSelection? selected;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showStickerPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.textContaining('Источник заблокирован'), findsOneWidget);
      await tester.tap(find.byTooltip('Blue square'));
      await settle(tester);
      expect(selected, isNull);
      expect(find.byType(StickerPicker), findsOneWidget);
      expect(http.calls, isEmpty);
    },
  );

  testWidgets(
    'blocked unknown source cannot be previewed and is not unblocked by the offer',
    (tester) async {
      await tester.runAsync(() async {
        await sources.addManual(testSourceUrl);
        await sources.setBlocked(testSourceUrl, true);
      });
      await tester.pumpWidget(app(StickerMessageBody(envelope: envelope)));
      await settle(tester);
      await tester.tap(find.text('Источник и пак'));
      await settle(tester);
      expect(find.text('Открыть источник'), findsNothing);
      expect(find.textContaining('Источник заблокирован'), findsOneWidget);
      expect(http.calls, isEmpty);
      expect(
        (await tester.runAsync(
          () => sources.watchSources().first,
        ))!.single.record.blocked,
        isTrue,
      );
    },
  );

  testWidgets(
    'trusted alternative of the same hash is chosen explicitly, without changing the message reference',
    (tester) async {
      const other = 'https://other.example/source.json';
      await tester.runAsync(() async {
        await sources.addManual(other);
        http.addSource(other);
        await sources.cacheSnapshot(
          sourceUrl: other,
          descriptorBytes: http.bodies[Uri.parse(other)]!,
          catalogBytes: stickerFixture('catalog.json'),
        );
      });
      await tester.pumpWidget(app(StickerMessageBody(envelope: envelope)));
      await settle(tester);
      await tester.tap(find.text('Источник и пак'));
      await settle(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settle(tester);
      await tester.tap(find.text('other.example').last);
      await settle(tester);
      expect(http.calls, isEmpty);
      await tester.tap(find.text('Открыть источник'));
      await settle(tester);
      expect(http.calls.every((c) => c.url.host == 'other.example'), isTrue);
      await installButton(tester, 'Установить эту ревизию');
      expect(packs.installed.single.hash, envelope.packSha256);
      expect(packs.installed.single.preferredSourceUrl, other);
      expect(envelope.sourceUrl, testSourceUrl);
      expect(
        (await tester.runAsync(() => sources.watchSources().first))!.length,
        1,
      );
      expect(find.byType(StickerImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline picker permits management but cannot return a send selection',
    (tester) async {
      await install(tester);
      online = false;
      StickerSelection? selected;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showStickerPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.byTooltip('Blue square'));
      await settle(tester);
      expect(selected, isNull);
      expect(find.byType(StickerPicker), findsOneWidget);
      expect(find.byTooltip('Управление паками'), findsOneWidget);
      expect(http.calls, isEmpty);
    },
  );

  testWidgets(
    'leaving a pending preview cancels it without adding a source or continuing HTTP',
    (tester) async {
      final waiting = Completer<void>();
      http.beforeFetch = (_) => waiting.future;
      await tester.pumpWidget(app(StickerMessageBody(envelope: envelope)));
      await settle(tester);
      await tester.tap(find.text('Источник и пак'));
      await settle(tester);
      await tester.tap(find.text('Открыть источник'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(http.calls.length, 1);
      Navigator.of(tester.element(find.byType(StickerOfferPage))).pop();
      await settle(tester);
      http.beforeFetch = null;
      waiting.complete();
      await settle(tester);
      expect(http.calls.length, 1);
      expect(
        await tester.runAsync(() => sources.watchSources().first),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'management selects a confirmed unblocked origin and re-enables the open picker offline',
    (tester) async {
      const other = 'https://other.example/source.json';
      await install(tester);
      await tester.runAsync(() async {
        await sources.addManual(other);
        http.addSource(other);
        await packs.install(other, testPackHash);
        await sources.setBlocked(testSourceUrl, true);
      });
      http.calls.clear();
      StickerSelection? selected;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showStickerPicker(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.textContaining('Источник заблокирован'), findsOneWidget);
      await tester.tap(find.byTooltip('Управление паками'));
      await settle(tester);
      await tester.tap(find.text('Demo Colors'));
      await settle(tester);
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settle(tester);
      await tester.tap(find.text(other).last);
      await settle(tester);
      expect(packs.installed.single.preferredSourceUrl, other);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.textContaining('Источник заблокирован'), findsNothing);
      await tester.tap(find.byTooltip('Blue square'));
      await settle(tester);
      expect(selected, (packSha256: testPackHash, stickerId: 'blue'));
      expect(http.calls, isEmpty);
    },
  );

  testWidgets(
    'compact dark unknown message fits large text without activating a source',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          Center(
            child: IntrinsicWidth(
              child: StickerMessageBody(envelope: envelope),
            ),
          ),
          scale: 1.6,
          brightness: Brightness.dark,
        ),
      );
      await settle(tester);
      expect(http.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
