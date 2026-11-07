import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_content.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/notify/message_alerts.dart';
import 'package:meshex/data/packet_router.dart';

void main() {
  late AppDatabase db;
  late List<MeshPacket> sent;
  late MessageSender sender;
  late PacketRouter router;
  var nextId = 100;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sent = [];
    router = PacketRouter(db);
    sender = MessageSender(
      db,
      (p) async {
        sent.add(p);
        return const DeliveryResult(DeliveryStatus.acked);
      },
      () => 0xaa,
      () => nextId++,
    );
  });
  tearDown(() => db.close());

  const retiredPayload = 'sticker:eto:s1:test_pack:001';

  test('retired sticker payload is ignored on PRIVATE_APP', () async {
    await router.handle(
      FromRadio(
        packet: MeshPacket(
          id: 1,
          from: 0xbb,
          to: broadcastNum,
          decoded: Data(
            portnum: PortNum.PRIVATE_APP,
            payload: utf8.encode(retiredPayload),
          ),
        ),
      ),
    );
    expect(await db.select(db.messages).get(), isEmpty);
    expect(sent, isEmpty);
  });

  test(
    'ordinary text is neither interpreted nor converted into a sticker',
    () async {
      await sender.sendToChannel(
        channel: 0,
        channelKey: 'test',
        text: retiredPayload,
      );
      final message = await db.select(db.messages).getSingle();
      expect(isTextMessage(message), isTrue);
      expect(messageTextPreview(message, 'Unsupported'), retiredPayload);
      await sender.retry(message);
      expect(sent.last.decoded.portnum, PortNum.TEXT_MESSAGE_APP);
      expect(utf8.decode(sent.last.decoded.payload), retiredPayload);
    },
  );

  Future<Message> unsupported() async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: 42,
            fromNum: 0xaa,
            toNum: broadcastNum,
            channel: const Value(0),
            body: 'opaque retired data',
            portnum: const Value(256),
            rxTime: DateTime.now(),
            isOutgoing: const Value(true),
            ackState: const Value(AckState.failed),
          ),
        );
    return db.select(db.messages).getSingle();
  }

  test('retry cannot transmit retired or unknown message types', () async {
    final message = await unsupported();
    await expectLater(sender.retry(message), throwsStateError);
    expect(sent, isEmpty);
    final after = await db.select(db.messages).getSingle();
    expect(after.packetId, 42);
    expect(after.ackState, AckState.failed);
  });

  test(
    'unsupported content has a safe preview and produces no notification',
    () async {
      final message = await unsupported();
      expect(isTextMessage(message), isFalse);
      expect(
        messageTextPreview(message, 'Unsupported message'),
        'Unsupported message',
      );
      expect(
        MessageAlerts.classify(
          message.copyWith(fromNum: 0xbb, toNum: 0xaa, isOutgoing: false),
          const AlertContext(me: 0xaa),
        ),
        isNull,
      );
    },
  );
}
