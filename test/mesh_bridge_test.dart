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
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/packet_router.dart';

void main() {
  const own = 0xaabbccdd;
  const peer = 0x11223344;
  late AppDatabase db;
  late AppDatabase settings;
  late _Link link;
  late StreamController<IncomingMeshText> incoming;
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
  }) async {
    final packet = MeshPacket(from: from, to: to, id: 77, channel: 1);
    incoming.add((node: own, packet: packet, text: text));
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
        onIncomingText: (packet, text) {
          incoming.add((node: own, packet: packet, text: text));
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
