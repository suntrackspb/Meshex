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
import 'package:meshex/data/packet_router.dart';

void main() {
  final json =
      (jsonDecode(File('test/fixtures/stickers/wire.json').readAsStringSync())
              as Map)
          .cast<String, dynamic>();
  final sticker = StickerEnvelope.fromJson({...json, 'wire_version': 2});
  final bytes = StickerWireCodec.encode(sticker);
  late AppDatabase db;
  late List<MeshPacket> sent;
  late MessageSender sender;
  var nextId = 100;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sent = [];
    sender = MessageSender(
      db,
      (packet) async {
        sent.add(packet);
        return const DeliveryResult(DeliveryStatus.timeout);
      },
      () => 42,
      () => nextId++,
    );
  });
  tearDown(() => db.close());

  Future<Message> only() => db.select(db.messages).getSingle();

  test(
    'send and retry preserve exact envelope, reply and delivery state',
    () async {
      await sender.sendStickerToChannel(
        channel: 1,
        channelKey: 'test',
        sticker: sticker,
        replyId: 7,
      );
      final first = await only();
      expect(first.portnum, 256);
      expect(first.rawPayload, bytes);
      expect(first.body, '[Sticker]');
      expect(messageContent(first), isA<StickerMessageContent>());
      expect(first.ackState, AckState.timeout);
      expect(sent.single.decoded.payload, bytes);
      expect(sent.single.decoded.emoji, 0);
      expect(sent.single.decoded.replyId, 7);
      await sender.retry(first);
      final second = await only();
      expect(second.id, first.id);
      expect(second.packetId, isNot(first.packetId));
      expect(second.rawPayload, bytes);
      expect(sent.last.decoded.payload, bytes);
      expect(sent.last.decoded.portnum, PortNum.PRIVATE_APP);
      expect(sent.last.decoded.replyId, 7);
    },
  );

  test('budget failure makes no DB change and sends nothing', () async {
    await expectLater(
      sender.sendStickerToChannel(
        channel: 0,
        channelKey: '',
        sticker: sticker,
        payloadBudget: bytes.length - 1,
      ),
      throwsFormatException,
    );
    expect(await db.select(db.messages).get(), isEmpty);
    expect(sent, isEmpty);
  });

  test(
    'retry rechecks the current transport budget before changing history',
    () async {
      var budget = 200;
      sender = MessageSender(
        db,
        (packet) async {
          sent.add(packet);
          return const DeliveryResult(DeliveryStatus.timeout);
        },
        () => 42,
        () => nextId++,
        stickerPayloadBudget: (_) => budget,
      );
      await sender.sendStickerToChannel(
        channel: 0,
        channelKey: '',
        sticker: sticker,
      );
      final before = await only();
      budget = bytes.length - 1;
      await expectLater(sender.retry(before), throwsFormatException);
      expect((await only()).packetId, before.packetId);
      expect(sent.length, 1);
    },
  );

  test('direct stickers use normal PKI path', () async {
    await db
        .into(db.nodes)
        .insert(
          NodesCompanion.insert(
            num: const Value(123),
            publicKey: Value(Uint8List.fromList(List.filled(32, 1))),
          ),
        );
    await sender.sendStickerDirect(to: 123, sticker: sticker, replyId: 9);
    expect(sent.single.pkiEncrypted, isTrue);
    expect(sent.single.publicKey, List.filled(32, 1));
    expect(sent.single.decoded.replyId, 9);
    expect((await only()).pkiEncrypted, isTrue);
  });

  test('unknown direct key creates no pending sticker', () async {
    await expectLater(
      sender.sendStickerDirect(to: 123, sticker: sticker),
      throwsStateError,
    );
    expect(await db.select(db.messages).get(), isEmpty);
    expect(sent, isEmpty);
  });

  test('corrupt or inconsistent content cannot mutate retry state', () async {
    await sender.sendStickerToChannel(
      channel: 0,
      channelKey: '',
      sticker: sticker,
    );
    final before = await only();
    await db
        .update(db.messages)
        .write(
          MessagesCompanion(
            stickerContent: Value(
              jsonEncode({...sticker.toJson(), 'sticker_id': 'other'}),
            ),
          ),
        );
    final corrupt = await only();
    expect(messageContent(corrupt), isA<UnsupportedMessageContent>());
    await expectLater(sender.retry(corrupt), throwsStateError);
    expect((await only()).packetId, before.packetId);
    expect(sent.length, 1);
  });

  test(
    'radio inserts typed content, ignores malformed private, keeps stream alive',
    () async {
      final router = PacketRouter(db);
      MeshPacket packet(int id, List<int> payload) => MeshPacket(
        id: id,
        from: 123,
        to: broadcastNum,
        channel: 0,
        decoded: Data(
          portnum: PortNum.PRIVATE_APP,
          payload: payload,
          replyId: 7,
        ),
      );
      await router.handle(FromRadio(packet: packet(1, [1, 2, 3])));
      expect(await db.select(db.messages).get(), isEmpty);
      await router.handle(FromRadio(packet: packet(2, bytes)));
      final message = await only();
      expect(message.rawPayload, bytes);
      expect(messageContent(message), isA<StickerMessageContent>());
      expect(message.replyId, 7);
      expect(message.heardOnRadio, isTrue);
      await router.handle(FromRadio(packet: packet(2, bytes)..rxRssi = -55));
      expect((await only()).rxRssi, -55);
      expect((await only()).rawPayload, bytes);
    },
  );

  test(
    'duplicate with different content never overwrites original type',
    () async {
      final router = PacketRouter(db);
      await router.handle(
        FromRadio(
          packet: MeshPacket(
            id: 7,
            from: 123,
            to: broadcastNum,
            decoded: Data(portnum: PortNum.PRIVATE_APP, payload: bytes),
          ),
        ),
      );
      await router.handle(
        FromRadio(
          packet: MeshPacket(
            id: 7,
            from: 123,
            to: broadcastNum,
            decoded: Data(
              portnum: PortNum.TEXT_MESSAGE_APP,
              payload: utf8.encode('conflicting text'),
            ),
          ),
        ),
      );
      final message = await only();
      expect(message.portnum, 256);
      expect(message.rawPayload, bytes);
      expect(messageContent(message), isA<StickerMessageContent>());
    },
  );

  test(
    'typed content persists across database reopen without network',
    () async {
      final temp = await Directory.systemTemp.createTemp('sticker-message-');
      final file = File('${temp.path}/history.sqlite');
      try {
        final disk = AppDatabase(NativeDatabase(file));
        await disk
            .into(disk.messages)
            .insert(
              MessagesCompanion.insert(
                packetId: 8,
                fromNum: 123,
                toNum: broadcastNum,
                body: '[Sticker]',
                rxTime: DateTime.now(),
                portnum: const Value(256),
                rawPayload: Value(bytes),
                stickerContent: Value(jsonEncode(sticker.toJson())),
              ),
            );
        await disk.close();
        final reopened = AppDatabase(NativeDatabase(file));
        try {
          final message = await reopened.select(reopened.messages).getSingle();
          expect(message.rawPayload, bytes);
          expect(messageContent(message), isA<StickerMessageContent>());
        } finally {
          await reopened.close();
        }
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
}
