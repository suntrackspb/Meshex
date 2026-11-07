import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/images_providers.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/journal.dart';
import 'package:meshex/core/radio/radio_session.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/features/chat/chat_feed.dart';
import 'package:meshex/l10n/l10n.dart';

DateTime at(int minute) =>
    DateTime.utc(2026, 10, 22, 12).add(Duration(minutes: minute));

Message message(int minute) => Message(
  id: minute,
  packetId: minute,
  fromNum: 2,
  toNum: broadcastNum,
  channel: 0,
  channelKey: 'test',
  portnum: 1,
  body: 'message $minute',
  rxTime: at(minute),
  isOutgoing: false,
  emoji: 0,
  viaMqtt: false,
  pkiEncrypted: false,
  xeddsaSigned: false,
  ackState: AckState.values.first,
  heardOnRadio: true,
  heardOnMirror: false,
  relayCount: 0,
  isBot: false,
);

void main() {
  for (final minute in [10, 80, 0]) {
    final hasMark = minute > 0;
    testWidgets(
      'opens unread and resumes after partial reading (mark: $minute)',
      (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        if (hasMark) {
          await db.setSetting(
            readSettingKey('test'),
            at(minute).toIso8601String(),
          );
        }
        final feed = [for (var i = 100; i > 0; i--) message(i)];
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appDatabaseProvider.overrideWithValue(db),
            radioProvider.overrideWith((_) => RadioSession(Journal())),
            mirrorApiProvider.overrideWithValue(null),
            mirrorActiveProvider.overrideWithValue(false),
            imageUploadsProvider.overrideWithValue(null),
            chatChannelsProvider.overrideWithValue(
              const AsyncData([
                ChatChannel(key: 'test', title: 'Test', index: 0),
              ]),
            ),
            feedMessagesProvider(
              'test',
            ).overrideWith((_) => Stream.value(feed)),
            unreadCountProvider(
              'test',
            ).overrideWith((_) => Stream.value(100 - minute)),
          ],
        );
        final subscription = container.listen(
          feedReadProvider('test'),
          (_, _) {},
        );
        addTearDown(() async {
          subscription.close();
          container.dispose();
          await db.close();
        });
        var open = true;
        late StateSetter update;
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return open ? const ChatFeed(id: 'test') : const SizedBox();
                },
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 40; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await t.pump(const Duration(milliseconds: 20));
          }
          await t.pumpAndSettle();
        }

        await settle();
        final scroll = find
            .descendant(
              of: find.byType(ChatFeed),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = t.state<ScrollableState>(scroll).position;
        expect(position.pixels, greaterThan(0));
        expect(find.text('Новые сообщения').hitTestable(), findsOneWidget);
        final dividerTop = t.getTopLeft(find.text('Новые сообщения')).dy;
        expect(dividerTop, lessThan(t.getTopLeft(scroll).dy + 120));
        final mark = await t.runAsync<String?>(
          () => db.getSetting(readSettingKey('test')),
        );
        expect(DateTime.parse(mark!).isBefore(at(100)), isTrue);
        await t.drag(scroll, const Offset(0, -100));
        await settle();
        final partial = DateTime.parse(
          (await t.runAsync<String?>(
            () => db.getSetting(readSettingKey('test')),
          ))!,
        );
        expect(partial.isBefore(at(100)), isTrue);
        expect(partial.isAfter(DateTime.parse(mark)), isTrue);
        final onScreen = find
            .byWidgetPredicate(
              (w) => w is Text && (w.data?.startsWith('message ') ?? false),
            )
            .hitTestable();
        final anchorText = (t.widget<Text>(onScreen.first)).data!;
        final stoppedTop = t.getTopLeft(find.text(anchorText)).dy;
        update(() => open = false);
        await settle();
        // Новые сообщения во время отсутствия не сдвигают место чтения.
        feed.insertAll(0, [message(102), message(101)]);
        container.invalidate(feedMessagesProvider('test'));
        update(() => open = true);
        await settle();
        expect(t.getTopLeft(find.text(anchorText)).dy, closeTo(stoppedTop, 2));
        expect(find.text('message 100').hitTestable(), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
