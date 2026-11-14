import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/images_providers.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/journal.dart';
import 'package:meshex/core/radio/radio_session.dart';
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/core/stickers/wire_codec.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/message_split.dart';
import 'package:meshex/data/stickers/pack_repository.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';
import 'package:meshex/features/chat/chat_feed.dart';
import 'package:meshex/features/chat/sticker_picker.dart';
import 'package:meshex/l10n/l10n.dart';

import 'sticker_fixtures.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late StickerPackRepository packs;
  late TestStickerHttp http;
  late ProviderContainer container;
  late ProviderSubscription<AsyncValue<DateTime?>> readSubscription;
  late List<MeshPacket> sent;
  late Map<String, String> drafts;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sticker-composer-');
    db = AppDatabase(NativeDatabase.memory());
    final sources = StickerSourceRepository(db);
    http = TestStickerHttp();
    await sources.addManual(testSourceUrl);
    packs = StickerPackRepository(
      client: StickerSourceClient(sources, http, currentMirror: () => null),
      directory: () async => dir,
    );
    await packs.install(testSourceUrl, testPackHash);
    http.calls.clear();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: 7,
            fromNum: 123,
            toNum: broadcastNum,
            channel: const Value(0),
            channelKey: const Value('test'),
            body: 'Reply target',
            rxTime: DateTime.now(),
          ),
        );
    final target = await db.select(db.messages).getSingle();
    final radio = RadioSession(Journal())
      ..state = RadioState.ready
      ..myNodeNum = 42;
    var id = 100;
    sent = [];
    drafts = {'test': 'draft kept'};
    final sender = MessageSender(
      db,
      (packet) async {
        sent.add(packet);
        return const DeliveryResult(DeliveryStatus.acked);
      },
      () => 42,
      () => id++,
      prepareSticker: (e) => sources.checkSendAllowed(e.sourceUrl),
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseProvider.overrideWithValue(db),
        radioProvider.overrideWith((_) => radio),
        mirrorApiProvider.overrideWithValue(null),
        mirrorActiveProvider.overrideWithValue(false),
        imageUploadsProvider.overrideWithValue(null),
        messageSenderProvider.overrideWithValue(sender),
        chatDraftsProvider.overrideWithValue(drafts),
        stickerPackRepositoryProvider.overrideWithValue(packs),
        stickerHttpProvider.overrideWithValue(http),
        chatChannelsProvider.overrideWithValue(
          const AsyncData([ChatChannel(key: 'test', title: 'Test', index: 0)]),
        ),
        feedMessagesProvider(
          'test',
        ).overrideWith((_) => Stream.value([target])),
        feedReadProvider(
          'test',
        ).overrideWith((_) => Stream.value(DateTime.utc(2100))),
        unreadCountProvider('test').overrideWith((_) => Stream.value(0)),
      ],
    );
    readSubscription = container.listen(feedReadProvider('test'), (_, _) {});
  });
  tearDown(() async {
    readSubscription.close();
    container.dispose();
    packs.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChatFeed(id: 'test'),
    ),
  );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sticker from composer preserves draft and forwards the current reply in one radio packet',
    (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await tester.longPress(find.text('Reply target'));
      await settle(tester);
      await tester.tap(find.text('Ответить'));
      await settle(tester);
      expect(find.byTooltip('Отменить ответ'), findsOneWidget);
      await tester.tap(find.byTooltip('Стикеры'));
      await settle(tester);
      expect(
        find.text('Здесь появятся последние 20 использованных стикеров.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Demo Colors'));
      await settle(tester);
      await tester.tap(find.byTooltip('Blue square'));
      await settle(tester);
      expect(find.byType(StickerPicker), findsNothing);
      expect(sent.length, 1);
      expect(await container.read(recentStickersProvider.future), [
        (packSha256: testPackHash, stickerId: 'blue'),
      ]);
      await tester.tap(find.byTooltip('Стикеры'));
      await settle(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Недавние'))
            .selected,
        isTrue,
      );
      expect(find.byTooltip('Blue square'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await settle(tester);
      expect(sent.single.decoded.portnum, PortNum.PRIVATE_APP);
      expect(sent.single.decoded.replyId, 7);
      expect(sent.single.decoded.emoji, 0);
      expect(
        StickerWireCodec.decode(sent.single.decoded.payload)!.packSha256,
        testPackHash,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'draft kept',
      );
      expect(drafts['test'], 'draft kept');
      expect(http.calls, isEmpty);
      final messages = await tester.runAsync(
        () => db.select(db.messages).get(),
      );
      expect(messages!.length, 2);
      expect(messages.last.portnum, 256);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets('multipart text locks the picker until the sequence ends', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'long message ' * 30);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.sticky_note_2_outlined),
    );
    expect(button.onPressed, isNull);
    expect(
      sent.every((p) => p.decoded.portnum == PortNum.TEXT_MESSAGE_APP),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(MessageSplit.delay);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(tester.takeException(), isNull);
  });
}
