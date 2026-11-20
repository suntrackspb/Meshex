import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/bridges/bridge_config.dart';
import 'package:meshex/bridges/bridge_protocol.dart';
import 'package:meshex/bridges/mesh_bridge.dart';
import 'package:meshex/core/proto/mesh.dart' hide User;
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/core/stickers/wire_codec.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/packet_router.dart';

void main() {
  const own = 0xaabbccdd;
  const peer = 0x11223344;
  late AppDatabase db;
  late AppDatabase settings;
  late _Link link;
  late StreamController<IncomingMeshMessage> incoming;
  late MeshBridge bridge;
  late List<MeshPacket> sent;
  late int? connected;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    settings = AppDatabase(NativeDatabase.memory());
    link = _Link();
    incoming = StreamController.broadcast();
    sent = [];
    connected = own;
    await db
        .into(db.channels)
        .insert(
          ChannelsCompanion.insert(
            index: const Value(1),
            name: const Value('Local'),
            role: Value(Channel_Role.SECONDARY.value),
          ),
        );
    await db
        .into(db.nodes)
        .insert(
          NodesCompanion.insert(
            num: const Value(peer),
            longName: const Value('Sender'),
            publicKey: Value(Uint8List.fromList(List.filled(32, 1))),
          ),
        );
    final channels = await bridgeChannels(db);
    var next = 100;
    bridge = MeshBridge(
      config: BridgeConfig(
        id: 'test',
        node: own,
        direct: true,
        sendDirect: true,
        sendChannels: true,
        channels: {channels.single.fingerprint: BridgeChannelMode.mentions},
      ),
      db: () => db,
      settings: settings,
      connectedNode: () => connected,
      sender: () => MessageSender(
        db,
        (packet) async {
          sent.add(packet);
          return const DeliveryResult(DeliveryStatus.acked, null, null, true);
        },
        () => connected,
        () => next++,
      ),
      link: link,
      onDisconnect: () => fail('Unexpected bridge disconnect'),
      stickerMedia: (sticker, offset) async => offset == 0
          ? {'size': 3, 'animated': false, 'dataBase64': 'AAEC'}
          : null,
    );
    await bridge.start(incoming.stream);
  });

  tearDown(() async {
    bridge.close();
    await incoming.close();
    await db.close();
    await settings.close();
  });

  Future<BridgeJson> receive({
    int to = broadcastNum,
    String text = 'hello !aabbccdd',
    int from = peer,
    MeshPacket? packet,
  }) async {
    incoming.add((
      node: own,
      packet: packet ?? MeshPacket(from: from, to: to, id: 77, channel: 1),
      text: text,
      sticker: null,
    ));
    return link.events.stream
        .firstWhere((event) => event['method'] == 'mesh.messageReceived')
        .then((e) => e['params'] as BridgeJson);
  }

  BridgeJson command(BridgeJson event) => {
    'nodeId': event['nodeId'],
    'replyRef': event['replyRef'],
    'text': 'response',
    'commandId': 'test-command',
  };

  test('exposes radio metadata, including valid zero readings', () async {
    final event = await receive(
      packet: MeshPacket(
        from: peer,
        to: broadcastNum,
        id: 77,
        channel: 1,
        rxRssi: 0,
        rxSnr: 0,
        hopStart: 3,
        hopLimit: 1,
        relayNode: 52,
        nextHop: 86,
        viaMqtt: true,
        transportMechanism: MeshPacket_TransportMechanism.TRANSPORT_LORA,
        decoded: Data(portnum: PortNum.TEXT_MESSAGE_APP, replyId: 42),
      ),
    );
    expect(event['radio'], {
      'packetId': 77,
      'destinationId': '!ffffffff',
      'channelIndex': 1,
      'rxRssi': 0,
      'rxSnr': 0,
      'hopStart': 3,
      'hopLimit': 1,
      'hops': 2,
      'relayNode': 52,
      'nextHop': 86,
      'transportMechanism': 'TRANSPORT_LORA',
      'viaMqtt': true,
      'wantAck': false,
      'pkiEncrypted': false,
      'xeddsaSigned': false,
      'portNum': PortNum.TEXT_MESSAGE_APP.value,
      'replyId': 42,
    });
  });

  test('passes the full packet, including unknown protobuf fields', () async {
    final packet = MeshPacket(
      from: peer,
      to: broadcastNum,
      id: 77,
      channel: 1,
      txAfter: 123,
      decoded: Data(
        portnum: PortNum.TEXT_MESSAGE_APP,
        payload: utf8.encode('hello !aabbccdd'),
        requestId: 45,
      ),
    );
    // Protobuf field 127 (varint), which this schema does not know.
    final full = MeshPacket.fromBuffer([
      ...packet.writeToBuffer(),
      0xf8,
      7,
      42,
    ]);
    final event = await receive(packet: full);
    final envelope = event['packet'] as BridgeJson;
    final json = envelope['json'] as BridgeJson;
    expect(json['txAfter'], 123);
    expect(json['decoded'], containsPair('requestId', 45));
    expect(
      (json['decoded'] as BridgeJson)['payload'],
      base64Encode(packet.decoded.payload),
    );
    final decoded = MeshPacket.fromBuffer(
      base64Decode(envelope['protobufBase64'] as String),
    );
    expect(decoded, full);
    expect(decoded.unknownFields, isNot(packet.unknownFields));
  });

  test(
    'omits unknown measurements and distinguishes known zero hops',
    () async {
      final packet = MeshPacket(
        from: peer,
        to: broadcastNum,
        id: 77,
        channel: 1,
        hopStart: 0,
        rxSnr: double.nan,
        decoded: Data(portnum: PortNum.TEXT_MESSAGE_APP),
      );
      final legacyEvent = await receive(packet: packet);
      expect(() => jsonEncode(legacyEvent), returnsNormally);
      final legacy = legacyEvent['radio'] as BridgeJson;
      for (final field in ['rxRssi', 'rxSnr', 'hops']) {
        expect(legacy.containsKey(field), isFalse, reason: field);
      }

      packet.decoded.bitfield = 0;
      final modern = (await receive(packet: packet))['radio'] as BridgeJson;
      expect(modern, containsPair('hops', 0));
    },
  );

  test(
    'allows a channel reply once and publishes the actual radio status',
    () async {
      final event = await receive();
      final reply = {...command(event), 'mentionAuthor': true};
      final delivered = link.events.stream.firstWhere(
        (event) => event['method'] == 'mesh.deliveryChanged',
      );
      final result = await link.request('mesh.sendMessage', reply);
      expect(result, {'status': 'queued', 'packetId': 100});
      expect(await link.request('mesh.sendMessage', reply), result);
      final packet = sent.single;
      expect(packet.channel, 1);
      expect(packet.to, broadcastNum);
      expect(packet.decoded.replyId, 77);
      expect(utf8.decode(packet.decoded.payload), '!11223344 response');
      expect((await delivered)['params'], containsPair('status', 'acked'));
      await expectLater(
        link.request('mesh.sendMessage', {...reply, 'text': 'changed'}),
        throwsA(
          isA<BridgeError>().having((error) => error.code, 'code', -32006),
        ),
      );
    },
  );

  test(
    'routes a direct reply to the sender and retains its packet reference',
    () async {
      final event = await receive(to: own, text: 'private message');
      await link.request('mesh.sendMessage', command(event));
      expect(sent.single.to, peer);
      expect(sent.single.decoded.replyId, 77);
      expect(sent.single.pkiEncrypted, isTrue);
    },
  );

  test(
    'never retargets a reply after the channel or own node changes',
    () async {
      final event = await receive();
      await (db.update(db.channels)
            ..where((channel) => channel.index.equals(1)))
          .write(ChannelsCompanion(psk: Value(Uint8List.fromList([2]))));
      await expectLater(
        link.request('mesh.sendMessage', command(event)),
        throwsA(
          isA<BridgeError>().having((error) => error.code, 'code', -32002),
        ),
      );
      connected = 123;
      await expectLater(
        link.request('mesh.sendMessage', {
          ...command(event),
          'commandId': 'new',
        }),
        throwsA(
          isA<BridgeError>().having((error) => error.code, 'code', -32001),
        ),
      );
      expect(sent, isEmpty);
    },
  );

  test(
    'filters channel messages and hands off each received packet once',
    () async {
      final router = PacketRouter(
        db,
        onIncomingMessage: (packet, text, sticker) {
          incoming.add((
            node: own,
            packet: packet,
            text: text,
            sticker: sticker,
          ));
        },
      );
      final seen = <BridgeJson>[];
      final subscription = link.events.stream.listen(seen.add);
      addTearDown(subscription.cancel);
      MeshPacket packet(int id, String text, {int from = peer}) => MeshPacket(
        from: from,
        to: broadcastNum,
        id: id,
        channel: 1,
        decoded: Data(
          portnum: PortNum.TEXT_MESSAGE_APP,
          payload: utf8.encode(text),
        ),
      );
      final selected = packet(3, '!aabbccdd selected');
      for (final p in [
        packet(1, 'ordinary text'),
        packet(2, 'own !aabbccdd', from: own),
        selected,
        selected,
      ]) {
        await router.handle(FromRadio(packet: p));
      }
      await pumpEventQueue();
      expect(seen, hasLength(1));
      expect(seen.single['params'], containsPair('text', '!aabbccdd selected'));
    },
  );

  test(
    'links an incoming reaction and sends a mesh reaction on reply',
    () async {
      final original = await receive(to: own);
      final received = link.events.stream.firstWhere(
        (event) => event['method'] == 'mesh.reactionReceived',
      );
      final router = PacketRouter(
        db,
        onIncomingMessage: (packet, text, sticker) {
          incoming.add((
            node: own,
            packet: packet,
            text: text,
            sticker: sticker,
          ));
        },
      );
      await router.handle(
        FromRadio(
          packet: MeshPacket(
            from: peer,
            to: own,
            id: 89,
            decoded: Data(
              portnum: PortNum.TEXT_MESSAGE_APP,
              payload: utf8.encode('👍'),
              replyId: 77,
              emoji: 1,
            ),
          ),
        ),
      );
      final reaction = (await received)['params'] as BridgeJson;
      expect(reaction['emoji'], '👍');
      expect(reaction['originalRef'], original['replyRef']);

      await link.request('mesh.sendMessage', {
        ...command(original),
        'text': '👍',
        'reaction': true,
      });
      expect(sent.single.decoded.emoji, 1);
      expect(sent.single.decoded.replyId, 77);
      await expectLater(
        link.request('mesh.sendMessage', {
          ...command(original),
          'commandId': 'invalid-reaction',
          'text': 'reply',
          'reaction': true,
        }),
        throwsA(
          isA<BridgeError>().having((error) => error.code, 'code', -32602),
        ),
      );
    },
  );

  test(
    'publishes validated sticker identity and scopes media reads to its reference',
    () async {
      final sticker = StickerEnvelope(
        sourceUrl: 'https://stickers.example.org/source.json',
        packSha256: 'a' * 64,
        stickerId: 'example',
      );
      final received = link.events.stream.firstWhere(
        (event) => event['method'] == 'mesh.stickerReceived',
      );
      final router = PacketRouter(
        db,
        onIncomingMessage: (packet, text, sticker) {
          incoming.add((
            node: own,
            packet: packet,
            text: text,
            sticker: sticker,
          ));
        },
      );
      await router.handle(
        FromRadio(
          packet: MeshPacket(
            from: peer,
            to: own,
            id: 89,
            decoded: Data(
              portnum: StickerWireCodec.port,
              payload: StickerWireCodec.encode(sticker),
            ),
          ),
        ),
      );
      final event = (await received)['params'] as BridgeJson;
      expect(event['sticker'], sticker.toJson());
      expect(
        await link.request('mesh.getStickerMedia', {
          'replyRef': event['replyRef'],
          'offset': 0,
        }),
        {'size': 3, 'animated': false, 'dataBase64': 'AAEC'},
      );
      final text = await receive(to: own);
      await expectLater(
        link.request('mesh.getStickerMedia', {'replyRef': text['replyRef']}),
        throwsA(
          isA<BridgeError>().having((error) => error.code, 'code', -32003),
        ),
      );
    },
  );

  test('enforces byte limit before attempting to send', () async {
    final event = await receive();
    await expectLater(
      link.request('mesh.sendMessage', {...command(event), 'text': 'я' * 101}),
      throwsA(isA<BridgeError>().having((error) => error.code, 'code', -32004)),
    );
    expect(sent, isEmpty);
  });
}

class _Link implements BridgeLink {
  final events = StreamController<BridgeJson>.broadcast();
  late BridgeRequest request;

  @override
  Future<void> open(BridgeRequest handler, void Function() onDisconnect) async {
    request = handler;
  }

  @override
  Future<void> publish(String method, BridgeJson params) async {
    events.add(bridgeCall(method, params));
  }

  @override
  void close() => unawaited(events.close());
}
