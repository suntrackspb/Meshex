import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/core/stickers/wire_codec.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_content.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/notify/alert_watcher.dart';
import 'package:meshex/data/notify/message_alerts.dart';
import 'package:meshex/data/stickers/pack_repository.dart';
import 'package:meshex/data/stickers/source_client.dart';
import 'package:meshex/data/stickers/source_repository.dart';

import 'sticker_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory dir;
  late StickerSourceRepository sources;
  late TestStickerHttp http;
  late StickerSourceClient client;
  late StickerPackRepository packs;
  final envelope = StickerEnvelope(
    sourceUrl: testSourceUrl,
    packSha256: testPackHash,
    stickerId: 'blue',
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('sticker-send-');
    sources = StickerSourceRepository(db);
    await sources.addManual(testSourceUrl);
    http = TestStickerHttp();
    client = StickerSourceClient(sources, http, currentMirror: () => null);
    packs = StickerPackRepository(client: client, directory: () async => dir);
  });
  tearDown(() async {
    packs.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'preferred source must be a confirmed copy, persists offline, and never silently changes on block',
    () async {
      const other = 'https://other.example/source.json';
      http.addSource(other);
      await sources.addManual(other);
      await packs.install(testSourceUrl, testPackHash);
      await packs.install(other, testPackHash);
      await packs.setPreferredSource(testPackHash, other);
      http.calls.clear();
      await expectLater(
        packs.setPreferredSource(
          testPackHash,
          'https://unconfirmed.example/source.json',
        ),
        throwsStateError,
      );
      packs.dispose();
      packs = StickerPackRepository(client: client, directory: () async => dir);
      await packs.initialize();
      expect((await packs.envelopeFor(testPackHash, 'blue')).sourceUrl, other);
      await sources.setBlocked(other, true);
      await expectLater(
        packs.envelopeFor(testPackHash, 'blue'),
        throwsStateError,
      );
      expect(packs.installed.single.preferredSourceUrl, other);
      await packs.setPreferredSource(testPackHash, testSourceUrl);
      await sources.setManualEnabled(testSourceUrl, false);
      expect(
        (await packs.envelopeFor(testPackHash, 'blue')).sourceUrl,
        testSourceUrl,
      );
      await sources.remove(testSourceUrl);
      expect(
        (await packs.envelopeFor(testPackHash, 'blue')).sourceUrl,
        testSourceUrl,
      );
      expect(http.calls, isEmpty);
      await expectLater(
        packs.envelopeFor(testPackHash, 'absent'),
        throwsStateError,
      );
    },
  );

  test(
    'send and retry check block before mutating the DB or sending radio data',
    () async {
      final sent = <MeshPacket>[];
      var id = 10;
      final sender = MessageSender(
        db,
        (packet) async {
          sent.add(packet);
          return const DeliveryResult(DeliveryStatus.timeout);
        },
        () => 42,
        () => id++,
        prepareSticker: (e) => sources.checkSendAllowed(e.sourceUrl),
      );
      await sources.setBlocked(testSourceUrl, true);
      await expectLater(
        sender.sendStickerToChannel(
          channel: 0,
          channelKey: 'test',
          sticker: envelope,
        ),
        throwsStateError,
      );
      expect(sent, isEmpty);
      expect(await db.select(db.messages).get(), isEmpty);
      await sources.setBlocked(testSourceUrl, false);
      await sender.sendStickerToChannel(
        channel: 0,
        channelKey: 'test',
        sticker: envelope,
        replyId: 7,
      );
      final original = await db.select(db.messages).getSingle();
      await sources.setBlocked(testSourceUrl, true);
      await expectLater(sender.retry(original), throwsStateError);
      final after = await db.select(db.messages).getSingle();
      expect(after.packetId, original.packetId);
      expect(after.ackState, original.ackState);
      expect(after.rawPayload, original.rawPayload);
      expect(sent.length, 1);
      expect(http.calls, isEmpty);
    },
  );

  Future<Message> sticker({
    int to = broadcastNum,
    int? replyId,
    bool outgoing = false,
    String body = '[Sticker]',
  }) async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: 100,
            fromNum: outgoing ? 42 : 123,
            toNum: to,
            channel: const Value(0),
            body: body,
            portnum: const Value(256),
            rawPayload: Value(StickerWireCodec.encode(envelope)),
            stickerContent: Value(jsonEncode(envelope.toJson())),
            rxTime: DateTime.now(),
            replyId: Value(replyId),
            isOutgoing: Value(outgoing),
          ),
        );
    return db.select(db.messages).getSingle();
  }

  test(
    'sticker alerts retain DM/reply permissions and never interpret fallback/source as mention',
    () async {
      final message = await sticker(body: '@example https://s.example');
      expect(
        MessageAlerts.classify(
          message,
          const AlertContext(me: 42, myShortName: 'example'),
        ),
        isNull,
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(replyId: const Value(7)),
          const AlertContext(me: 42, targetIsMine: true),
        ),
        AlertKind.reply,
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(toNum: 42),
          const AlertContext(me: 42),
        ),
        AlertKind.direct,
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(toNum: 42),
          const AlertContext(me: 42, senderMuted: true),
        ),
        isNull,
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(replyId: const Value(7)),
          const AlertContext(me: 42, targetIsMine: true, channelMuted: true),
        ),
        isNull,
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(rawPayload: Value(Uint8List.fromList([1]))),
          const AlertContext(me: 42),
        ),
        isNull,
      );
      expect(
        messageTextPreview(message, 'Unsupported', stickerLabel: 'Sticker'),
        'Sticker',
      );
      expect(
        MessageAlerts.content(
          AlertKind.direct,
          message,
          sender: 'Peer',
          stickerLabel: 'Sticker',
        ).body,
        'Sticker',
      );
    },
  );

  test(
    'reaction to a sticker uses a localized sticker label instead of raw content or URL',
    () async {
      await sticker(outgoing: true);
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              packetId: 101,
              fromNum: 123,
              toNum: broadcastNum,
              body: '👍',
              rxTime: DateTime.now(),
              replyId: const Value(100),
              emoji: const Value(1),
            ),
          );
      final reaction = await (db.select(
        db.messages,
      )..where((m) => m.packetId.equals(101))).getSingle();
      final watcher = AlertWatcher(
        db,
        me: () => 42,
        settings: () => const AlertSettings(),
        isChatVisible: (_) => false,
        onAlert: (_) {},
        stickerLabel: () => 'Sticker',
      );
      addTearDown(watcher.dispose);
      final notification = await watcher.check(reaction);
      expect(notification!.kind, AlertKind.reaction);
      expect(notification.body, contains('Sticker'));
      expect(notification.body, isNot(contains('source.json')));
    },
  );
}
