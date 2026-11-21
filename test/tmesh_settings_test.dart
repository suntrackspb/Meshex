import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/link_badge.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/proto/tmesh/feature_flags.pb.dart' as tmesh;
import 'package:meshex/core/radio/journal.dart';
import 'package:meshex/core/radio/radio_session.dart';
import 'package:meshex/core/radio/tmesh_settings.dart';
import 'package:meshex/features/settings/radio/tmesh_settings_page.dart';

import 'support/fake_transport.dart';

const _nodeNum = 0x1234abcd;

void main() {
  late FakeTransport transport;
  late RadioSession radio;
  late TmeshSettings client;

  group('TMesh radio requests', () {
    setUp(() async {
      transport = FakeTransport();
      radio = await _connect(transport);
      await pumpEventQueue();
      expect(radio.state, RadioState.ready);
      client = TmeshSettings(
        radio,
        _nodeNum,
        radio.connectedSince!,
        timeout: const Duration(milliseconds: 100),
      );
    });

    tearDown(() async {
      transport.onSend = null;
      await radio.disconnect();
      radio.dispose();
    });

    test('local probe waits for the matching TMesh response', () async {
      transport.onSend = (message) {
        final packet = message.packet;
        _ack(transport, packet);
        transport.reply(
          FromRadio(
            packet: MeshPacket(
              from: _nodeNum,
              decoded: Data(
                portnum: PortNum.ROUTING_APP,
                requestId: packet.id,
                payload: Routing(
                  errorReason: Routing_Error.NONE,
                ).writeToBuffer(),
              ),
            ),
          ),
        );
        _reply(transport, packet.id + 1, tmesh.Response_Status.OK);
        _reply(transport, packet.id, tmesh.Response_Status.OK, from: 0x99);
        transport.reply(
          FromRadio(
            packet: MeshPacket(
              from: _nodeNum,
              decoded: Data(
                portnum: PortNum.ADMIN_APP,
                requestId: packet.id,
                payload: AdminMessage(
                  getRingtoneResponse: 'ring',
                ).writeToBuffer(),
              ),
            ),
          ),
        );
      };
      expect(await client.probe(), false);
      final request = transport.sent
          .where((message) => message.hasPacket())
          .single
          .packet;
      expect(request.id, isNonZero);
      expect(request.to, _nodeNum);
      expect(request.hopLimit, 0);
      expect(request.wantAck, false);
      expect(request.decoded.portnum, PortNum.ADMIN_APP);
      expect(request.decoded.wantResponse, true);
      expect(
        tmesh.Envelope.fromBuffer(request.decoded.payload).request.operation,
        tmesh.Request_Operation.GET,
      );

      transport.onSend = (message) {
        _ack(transport, message.packet);
        _reply(
          transport,
          message.packet.id,
          tmesh.Response_Status.STORAGE_ERROR,
        );
      };
      expect(await client.probe(), true);
      await expectLater(client.read(), throwsA(TmeshError.storage));
    });

    test('creation is explicit and SET and CLEAR are read back', () async {
      tmesh.FeatureFlagsConfig? stored;
      final operations = <tmesh.Request_Operation>[];
      transport.onSend = (message) {
        final packet = message.packet;
        final request = tmesh.Envelope.fromBuffer(
          packet.decoded.payload,
        ).request;
        operations.add(request.operation);
        _ack(transport, packet);
        switch (request.operation) {
          case tmesh.Request_Operation.SET:
            expect(request.hasConfig(), true);
            // Nanopb omits scalar defaults even if the client set them.
            stored = tmesh.FeatureFlagsConfig(
              forceNextHopRelay: request.config.forceNextHopRelay,
            );
          case tmesh.Request_Operation.CLEAR:
            stored = null;
          case tmesh.Request_Operation.GET:
          case tmesh.Request_Operation.UNSPECIFIED:
            break;
        }
        _reply(transport, packet.id, tmesh.Response_Status.OK, config: stored);
      };

      expect(await client.read(), isNull);
      await expectLater(
        client.save(initialize: false, edit: (_) {}),
        throwsA(TmeshError.configChanged),
      );
      expect(operations, everyElement(tmesh.Request_Operation.GET));

      final created = await client.save(
        initialize: true,
        edit: (config) => config
          ..forceNextHopRelay = 0xab
          ..restrictedRoutingDisallowsPrivateText = false,
      );
      expect(created.forceNextHopRelay, 0xab);
      expect(created.hasRestrictedRoutingDisallowsPrivateText(), false);
      expect(operations, [
        tmesh.Request_Operation.GET,
        tmesh.Request_Operation.GET,
        tmesh.Request_Operation.GET,
        tmesh.Request_Operation.SET,
        tmesh.Request_Operation.GET,
      ]);

      await expectLater(
        client.save(
          initialize: false,
          edit: (config) => config.favoriteRouterMode =
              tmesh.FeatureFlagsConfig_FavoriteRouterMode.PRESERVE_HOPS_ONLY,
        ),
        throwsA(TmeshError.invalidConfig),
      );

      await expectLater(
        client.save(
          initialize: false,
          edit: (config) => config.restrictedRoutingDisallowsPrivateText = true,
        ),
        throwsA(TmeshError.unverified),
      );

      await client.clear();
      expect(operations.sublist(operations.length - 2), [
        tmesh.Request_Operation.CLEAR,
        tmesh.Request_Operation.GET,
      ]);
      expect(stored, isNull);
    });

    test('lost SET reply is verified without sending a second SET', () async {
      var writes = 0;
      var stored = tmesh.FeatureFlagsConfig(favoriteRouterRelay: 0x83);
      transport.onSend = (message) {
        final packet = message.packet;
        final request = tmesh.Envelope.fromBuffer(
          packet.decoded.payload,
        ).request;
        _ack(transport, packet);
        if (request.operation == tmesh.Request_Operation.SET) {
          writes++;
          stored = request.config;
          return;
        }
        _reply(transport, packet.id, tmesh.Response_Status.OK, config: stored);
      };

      final write = client.save(
        initialize: false,
        edit: (config) => config.forceNextHopRelay = 0xab,
      );
      await expectLater(client.clear(), throwsA(TmeshError.writeInProgress));
      final verified = await write;
      expect(writes, 1);
      expect(verified.forceNextHopRelay, 0xab);
      expect(verified.favoriteRouterRelay, 0x83);
    });

    test('connection loss ends a pending request', () async {
      transport.onSend = (message) => _ack(transport, message.packet);
      final read = expectLater(
        client.read(),
        throwsA(TmeshError.connectionChanged),
      );
      await pumpEventQueue();
      transport.drop('lost');
      await read;
    });
  });

  testWidgets('legacy settings stay active while opening the create form', (
    tester,
  ) async {
    final transport = FakeTransport();
    final radio = await _connect(transport);
    await tester.pump();
    expect(radio.state, RadioState.ready);

    final operations = <tmesh.Request_Operation>[];
    transport.onSend = (message) {
      final packet = message.packet;
      final request = tmesh.Envelope.fromBuffer(packet.decoded.payload).request;
      operations.add(request.operation);
      _ack(transport, packet);
      _reply(transport, packet.id, tmesh.Response_Status.OK);
    };
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          radioProvider.overrideWith((_) => radio),
          mirrorRealtimeProvider.overrideWith((_) => null),
          linkNodeProvider.overrideWith((_) => Stream.value(null)),
        ],
        child: const MaterialApp(home: TmeshSettingsPage()),
      ),
    );
    // Let the probe resolve and build the editor, then load its settings.
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(find.text('Используются прежние настройки'), findsOneWidget);

    await tester.tap(find.text('Создать конфигурацию TMesh'));
    await tester.pumpAndSettle();
    expect(find.text('Разрешённые типы пакетов'), findsOneWidget);
    expect(operations, [
      tmesh.Request_Operation.GET,
      tmesh.Request_Operation.GET,
    ]);
    expect(tester.takeException(), isNull);

    transport.onSend = null;
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<RadioSession> _connect(FakeTransport transport) async {
  transport.onSend = (message) {
    if (!message.hasWantConfigId()) return;
    if (message.wantConfigId == RadioSession.configNonce) {
      transport.reply(FromRadio(myInfo: MyNodeInfo(myNodeNum: _nodeNum)));
    }
    transport.reply(FromRadio(configCompleteId: message.wantConfigId));
  };
  final radio = RadioSession(Journal())..autoReconnect = false;
  await radio.connect(RadioTarget('TMesh', (_) => transport));
  return radio;
}

void _ack(FakeTransport transport, MeshPacket request) {
  transport.reply(
    FromRadio(queueStatus: QueueStatus(meshPacketId: request.id)),
  );
}

void _reply(
  FakeTransport transport,
  int requestId,
  tmesh.Response_Status status, {
  tmesh.FeatureFlagsConfig? config,
  int from = _nodeNum,
}) {
  transport.reply(
    FromRadio(
      packet: MeshPacket(
        from: from,
        decoded: Data(
          portnum: PortNum.ADMIN_APP,
          requestId: requestId,
          payload: tmesh.Envelope(
            response: tmesh.Response(status: status, config: config),
          ).writeToBuffer(),
        ),
      ),
    ),
  );
}
