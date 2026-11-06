import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/notify/message_alerts.dart';
import 'package:meshex/data/packet_router.dart';
import 'package:meshex/data/stickers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'packs contain 49 static stickers and exactly 10 animated memes',
    () async {
      expect(StickerCatalog.packs.map((p) => p.emojis.length), [49, 10]);
      for (final pack in StickerCatalog.packs) {
        for (final sticker in pack.stickers) {
          expect(
            (await rootBundle.load(sticker.path)).lengthInBytes,
            greaterThan(0),
          );
          if (sticker.animated) {
            expect(
              (await rootBundle.load(
                sticker.path.replaceFirst('.webp', '.png'),
              )).lengthInBytes,
              greaterThan(0),
            );
          }
        }
      }
      expect(
        StickerCatalog.find(const StickerRef('MemeS1ick3r', '011')),
        isNull,
      );
    },
  );

  test(
    'strict envelope accepts unknown packs, rejects unrelated private data',
    () {
      const ref = StickerRef('future_pack', '001');
      expect(StickerProtocol.decode(ref.encode())?.wire, ref.wire);
      for (final text in [
        'hello',
        'sticker:other:s1:cats:01',
        'sticker:eto:s2:cats:01',
        'sticker:eto:s1:../cats:01',
        'sticker:eto:s1:cats:01\n',
        'sticker:eto:s1:cats:01 trailing',
        'sticker:eto:s1:${'a' * 49}:01',
      ]) {
        expect(StickerProtocol.decode(utf8.encode(text)), isNull, reason: text);
      }
      expect(StickerProtocol.decode([0xff, 0xfe]), isNull);
      expect(StickerProtocol.decode(List.filled(101, 65)), isNull);
      expect(
        () => const StickerRef('../bad', '001').encode(),
        throwsArgumentError,
      );
    },
  );

  group('radio and storage', () {
    late AppDatabase db;
    late PacketRouter router;
    late MessageSender sender;
    late List<MeshPacket> sent;
    var id = 100;
    const sticker = StickerRef('MemeS1ick3r', '007');

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      router = PacketRouter(db);
      sent = [];
      sender = MessageSender(
        db,
        (p) async {
          sent.add(p);
          return const DeliveryResult(DeliveryStatus.acked);
        },
        () => 0xaa,
        () => id++,
      );
      await router.handle(
        FromRadio(
          channel: Channel(
            index: 0,
            role: Channel_Role.PRIMARY,
            settings: ChannelSettings(name: 'MediumFast'),
          ),
        ),
      );
    });
    tearDown(() => db.close());

    test(
      'send and retry preserve PRIVATE_APP, reply and compact payload',
      () async {
        await sender.sendStickerToChannel(
          channel: 0,
          channelKey: 'mediumfast',
          sticker: sticker,
          replyId: 42,
        );
        final message = await db.select(db.messages).getSingle();
        expect(message.portnum, 256);
        expect(message.body, sticker.wire);
        expect(message.ackState, AckState.acked);
        expect(sent.single.decoded.payload, sticker.encode());
        expect(sent.single.decoded.portnum, PortNum.PRIVATE_APP);
        expect(sent.single.decoded.replyId, 42);
        expect(sent.single.decoded.emoji, 0);
        await sender.retry(message);
        expect(sent.last.id, isNot(sent.first.id));
        expect(sent.last.decoded.portnum, PortNum.PRIVATE_APP);
        expect(sent.last.decoded.payload, sent.first.decoded.payload);
        expect(sent.last.decoded.replyId, 42);
        expect(await db.select(db.messages).get(), hasLength(1));
      },
    );

    test(
      'direct stickers retain PKI encryption and cannot send without key',
      () async {
        await expectLater(
          sender.sendStickerDirect(to: 0xbb, sticker: sticker),
          throwsStateError,
        );
        expect(sent, isEmpty);
        await db
            .into(db.nodes)
            .insert(
              NodesCompanion.insert(
                num: const Value(0xbb),
                publicKey: Value(Uint8List.fromList(List.filled(32, 9))),
              ),
            );
        await sender.sendStickerDirect(to: 0xbb, sticker: sticker);
        expect(sent.single.pkiEncrypted, isTrue);
        expect(sent.single.decoded.portnum, PortNum.PRIVATE_APP);
        expect(sent.single.publicKey, List.filled(32, 9));
        expect((await db.watchDirectMessages(0xbb).first).single.portnum, 256);
      },
    );

    Future<void> receive(int packetId, PortNum port, List<int> bytes) =>
        router.handle(
          FromRadio(
            packet: MeshPacket(
              id: packetId,
              from: 0xbb,
              to: broadcastNum,
              channel: 0,
              decoded: Data(portnum: port, payload: bytes, replyId: 99),
            ),
          ),
        );

    test(
      'received sticker survives deduplication, unknown packs are retained',
      () async {
        await receive(1, PortNum.PRIVATE_APP, sticker.encode());
        await receive(1, PortNum.PRIVATE_APP, sticker.encode());
        final message =
            (await db.watchChannelMessages('mediumfast').first).single;
        expect(message.portnum, 256);
        expect(message.replyId, 99);
        expect(message.body, sticker.wire);
        expect(message.heardOnRadio, isTrue);
        await receive(
          2,
          PortNum.PRIVATE_APP,
          const StickerRef('not_installed', '004').encode(),
        );
        expect(await db.select(db.messages).get(), hasLength(2));
      },
    );

    test(
      'notification previews are readable and pack IDs never trigger mentions',
      () async {
        await receive(3, PortNum.PRIVATE_APP, sticker.encode());
        final message = await db.select(db.messages).getSingle();
        expect(
          MessageAlerts.classify(
            message.copyWith(replyId: const Value(null)),
            const AlertContext(me: 0xaa, myShortName: 'MemeS1ick3r'),
          ),
          isNull,
        );
        final notification = MessageAlerts.content(
          AlertKind.direct,
          message,
          sender: 'Node',
          stickerLabel: 'Sticker',
        );
        expect(notification.body, 'Sticker 😂');
        expect(
          StickerProtocol.preview(sticker.wire, 1, 'Sticker'),
          sticker.wire,
        );
      },
    );

    test(
      'unrelated or malformed PRIVATE_APP never becomes a chat message',
      () async {
        await receive(1, PortNum.PRIVATE_APP, utf8.encode('eto-port-test:006'));
        await receive(2, PortNum.PRIVATE_APP, [0xff]);
        expect(await db.select(db.messages).get(), isEmpty);
        // A marker typed as normal text stays text, including on retry.
        await sender.sendToChannel(
          channel: 0,
          channelKey: 'mediumfast',
          text: sticker.wire,
        );
        final message = await db.select(db.messages).getSingle();
        await sender.retry(message);
        expect(message.portnum, 1);
        expect(sent.last.decoded.portnum, PortNum.TEXT_MESSAGE_APP);
      },
    );
  });
}
