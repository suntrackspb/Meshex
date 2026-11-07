import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/core/radio/send_queue.dart';
import 'package:meshex/core/stickers/wire_codec.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/message_content.dart';
import 'package:meshex/data/message_sender.dart';
import 'package:meshex/data/mirror_ingest.dart';
import 'package:meshex/data/packet_router.dart';
import 'package:meshex/mirror/mirror_api.dart';
import 'package:meshex/mirror/mirror_models.dart';
import 'package:meshex/mirror/mirror_realtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> dto() =>
    (jsonDecode(
              File(
                'test/fixtures/stickers/mirror-message.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, dynamic>();
StickerEnvelope get envelope =>
    StickerEnvelope.fromJson(dto()['sticker'] as Map<String, dynamic>);
List<int> get payload => StickerWireCodec.encode(envelope);

void main() {
  group('mirror sticker DTO contract', () {
    test(
      'source fields reconstruct the shared exact v2 payload without fallback text',
      () {
        for (final text in [
          null,
          '',
          '[Sticker]',
          'https://wrong.example/ignored',
        ]) {
          final row = dto()..['text'] = text;
          final parsed = MirrorMessage.tryParse(row)!;
          expect(parsed.kind, 'sticker');
          expect(parsed.portnum, 256);
          expect(parsed.sticker, envelope);
          expect(parsed.hasValidContent, isTrue);
          expect(StickerWireCodec.encode(parsed.sticker!), payload);
        }
        final row = dto()..remove('text');
        expect(MirrorMessage.tryParse(row)!.sticker, envelope);
      },
    );

    test(
      'unsupported kinds, ports, versions and malformed identities are not downgraded to text',
      () {
        for (final patch in [
          {'kind': 'future'},
          {'kind': 'text'},
          {'kind': null},
          {'portnum': 1},
          {'portnum': '256'},
          {'portnum': 256.0},
          {'sticker': null},
          {'sticker': 'legacy'},
          {
            'sticker': {...dto()['sticker'], 'wire_version': 1},
          },
          {
            'sticker': {...dto()['sticker'], 'pack_sha256': 'a' * 63},
          },
          {
            'sticker': {
              ...dto()['sticker'],
              'source_url': 'http://127.0.0.1/source.json',
            },
          },
          {
            'sticker': {...dto()['sticker'], 'sticker_id': '../escape'},
          },
          {'emoji': 1},
          {'emoji': '0'},
          {'packet_id': 1.5},
          {'packet_id': -1},
          {'packet_id': 0x100000000},
          {'reply_to_packet_id': '7'},
          {'from_id': '!+0000001'},
          {'to_id': 'broken'},
        ]) {
          expect(
            MirrorMessage.tryParse({...dto(), ...patch}),
            isNull,
            reason: '$patch',
          );
        }
      },
    );

    test(
      'plain text and reply/emoji keep old API semantics with absent or explicit text kind',
      () {
        for (final extra in [
          {},
          {'kind': 'text', 'portnum': 1, 'sticker': null},
        ]) {
          final parsed = MirrorMessage.tryParse({
            'id': 1,
            'from_id': '!12345678',
            'text': '👍',
            'reply_to_packet_id': 7,
            'emoji': 1,
            ...extra,
          })!;
          expect(parsed.kind, 'text');
          expect(parsed.portnum, 1);
          expect(parsed.sticker, isNull);
          expect(parsed.replyToPacketId, 7);
          expect(parsed.emoji, 1);
        }
      },
    );

    test(
      'one malformed row or relay never poisons following init/history messages',
      () {
        final valid = dto()
          ..['relays'] = [
            {'node_id': 7, 'rssi': []},
            {'node_id': '!gateway', 'snr': 'bad'},
          ];
        final list = parseMirrorMessages([
          {'id': 'name-change', 'type': 'name_change'},
          {...dto(), 'sticker': {}},
          valid,
          {
            'id': 124,
            'from_id': '!00000001',
            'text': 'text',
            'short_name': {},
            'relays': 'bad',
          },
        ]);
        expect(list.length, 2);
        expect(list.first.sticker, envelope);
        expect(list.first.relays.last.nodeId, '!gateway');
        expect(list.last.text, 'text');
        expect(
          MirrorMessage.tryParse({...dto(), 'type': 'name_change'}),
          isNull,
        );
      },
    );

    test(
      'REST history, WS/SSE init and live frames use the same message parser',
      () async {
        var requests = 0;
        final api = MirrorApi(
          Uri.parse('https://mirror.example'),
          client: MockClient((request) async {
            requests++;
            expect(request.url.path, '/api/chat/history');
            expect(request.url.queryParameters['before_id'], '124');
            return http.Response(jsonEncode([dto()]), 200);
          }),
        );
        addTearDown(api.close);
        final history = (await api.chatHistory(beforeId: 124)).single;
        final wsInit =
            MirrorEvent.parse({
                  'type': 'init',
                  'messages': [dto()],
                })
                as MirrorInit;
        // The server's /sse emits this exact JSON in data: lines, not a second DTO.
        final sseData =
            'data: ${jsonEncode({
              'type': 'init',
              'messages': [dto()],
            })}\n\n';
        final sseInit =
            MirrorEvent.parse(
                  jsonDecode(sseData.substring(6).trim())
                      as Map<String, dynamic>,
                )
                as MirrorInit;
        final live =
            MirrorEvent.parse({'type': 'new_message', 'message': dto()})
                as MirrorNewMessage;
        for (final m in [
          history,
          wsInit.messages.single,
          sseInit.messages.single,
          live.message,
        ]) {
          expect(m.sticker, envelope);
          expect(m.portnum, 256);
        }
        expect(
          MirrorEvent.parse({
            'type': 'new_message',
            'message': {...dto(), 'sticker': null},
          }),
          isA<MirrorOther>(),
        );
        expect(requests, 1);
      },
    );
  });

  group('mirror/radio sticker persistence', () {
    late AppDatabase db;
    late PacketRouter radio;
    late MirrorIngest mirror;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      radio = PacketRouter(db);
      mirror = MirrorIngest(db);
      await radio.handle(
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
    Future<Message> only() => db.select(db.messages).getSingle();
    Future<void> receive({
      List<int>? bytes,
      int from = 0x12345678,
      int to = broadcastNum,
      int id = 456,
      int? reply = 7,
      bool signed = true,
      bool pki = false,
      double snr = 6.5,
    }) => radio.handle(
      FromRadio(
        packet: MeshPacket(
          id: id,
          from: from,
          to: to,
          channel: 0,
          rxSnr: snr,
          rxRssi: -60,
          hopStart: 3,
          hopLimit: 1,
          xeddsaSigned: signed,
          pkiEncrypted: pki,
          decoded: Data(
            portnum: PortNum.PRIVATE_APP,
            payload: bytes ?? payload,
            replyId: reply,
          ),
        ),
      ),
    );
    MirrorMessage parsed([Map<String, dynamic> patch = const {}]) =>
        MirrorMessage.tryParse({...dto(), 'reply_to_packet_id': 7, ...patch})!;

    test(
      'history with missing text persists typed content, exact reconstructed bytes and no source registration',
      () async {
        await mirror.messages([
          parsed({'text': null}),
        ]);
        final m = await only();
        expect(m.body, '[Sticker]');
        expect(m.portnum, 256);
        expect(m.rawPayload, payload);
        expect(messageContent(m), isA<StickerMessageContent>());
        expect(m.replyId, 7);
        expect(m.heardOnMirror, isTrue);
        expect(m.heardOnRadio, isFalse);
        expect(m.rxTime.toUtc(), DateTime.utc(2026, 11, 6));
        expect(await db.select(db.stickerSources).get(), isEmpty);
        expect(await db.select(db.stickerInstalls).get(), isEmpty);
      },
    );

    test(
      'radio then history/live/reconnect is one sticker with radio metrics and reply intact',
      () async {
        await receive();
        final first = await only();
        await mirror.messages([
          parsed({
            'snr': -12,
            'relays': [
              {'node_id': '!1'},
            ],
          }),
        ]);
        await mirror.messages([
          parsed({'text': '', 'relays': []}),
        ], live: true);
        await MirrorIngest(db).messages([parsed()]);
        final m = await only();
        expect(m.id, first.id);
        expect(m.rawPayload, payload);
        expect(m.stickerContent, first.stickerContent);
        expect(m.rxTime, first.rxTime);
        expect(m.rxSnr, 6.5);
        expect(m.hopStart, 3);
        expect(m.hopLimit, 1);
        expect(m.replyId, 7);
        expect(m.emoji, 0);
        expect(m.xeddsaSigned, isTrue);
        expect(m.heardOnRadio && m.heardOnMirror, isTrue);
        expect(m.relayCount, 1);
        expect(m.mirrorId, 123);
      },
    );

    test(
      'mirror then radio fills radio metadata and missing reply, never replaces payload',
      () async {
        await mirror.messages([
          parsed({'reply_to_packet_id': null}),
        ]);
        final original = await only();
        await receive(pki: true);
        final m = await only();
        expect(m.id, original.id);
        expect(m.rawPayload, original.rawPayload);
        expect(m.replyId, 7);
        expect(m.heardOnRadio && m.heardOnMirror, isTrue);
        expect(m.channel, 0);
        expect(m.xeddsaSigned, isTrue);
        expect(m.pkiEncrypted, isTrue);
        await receive(signed: false, pki: false);
        expect((await only()).xeddsaSigned, isTrue);
        expect((await only()).pkiEncrypted, isTrue);
      },
    );

    test(
      'twenty-one relays, duplicates and stale history keep a monotonic count',
      () async {
        await mirror.messages([
          parsed({
            'relays': [
              for (var i = 0; i < 21; i++) {'node_id': '!$i'},
            ],
          }),
        ]);
        for (var i = 0; i < 21; i++) {
          await mirror.relay(123, MirrorRelay(nodeId: '!$i'));
        }
        await mirror.relay(123, const MirrorRelay(nodeId: '!new'));
        await mirror.relay(123, const MirrorRelay(nodeId: '!new'));
        await MirrorIngest(db).messages([
          parsed({'relays': []}),
        ]);
        expect((await only()).relayCount, 22);
        expect((await db.select(db.messages).get()).length, 1);
      },
    );

    test('identity is sender/packet, not hash, source or pack title', () async {
      await mirror.messages([
        parsed(),
        parsed({'id': 124, 'packet_id': 457}),
        parsed({'id': 125, 'from_id': '!87654321'}),
      ]);
      expect(await db.select(db.messages).get(), hasLength(3));
    });

    test('missing packet IDs use distinct stable synthetic keys', () async {
      await mirror.messages([
        parsed({'packet_id': null}),
        parsed({'id': 124, 'packet_id': null}),
      ]);
      await mirror.messages([
        parsed({'packet_id': null}),
      ], live: true);
      final rows = await db.select(db.messages).get();
      expect(rows.map((m) => m.packetId).toSet(), {-123, -124});
      expect(
        rows.every((m) => messageContent(m) is StickerMessageContent),
        isTrue,
      );
    });

    test(
      'conflicting mirror content cannot replace radio sticker or mark it as a reaction',
      () async {
        await receive();
        final original = await only();
        await mirror.messages([
          MirrorMessage(
            id: 123,
            packetId: 456,
            fromId: '!12345678',
            channel: 'MediumFast',
            text: '👍',
            emoji: 1,
            replyToPacketId: 99,
          ),
        ]);
        await mirror.messages([
          parsed({
            'sticker': {...dto()['sticker'], 'sticker_id': 'pulse'},
          }),
        ]);
        final m = await only();
        expect(m.rawPayload, original.rawPayload);
        expect(m.body, '[Sticker]');
        expect(m.emoji, 0);
        expect(m.replyId, 7);
        expect(messageContent(m), isA<StickerMessageContent>());
      },
    );

    test(
      'conflicting signed radio payload cannot authenticate the retained mirror content',
      () async {
        await mirror.messages([parsed()]);
        final original = await only();
        final other = StickerEnvelope(
          sourceUrl: envelope.sourceUrl,
          packSha256: envelope.packSha256,
          stickerId: 'pulse',
        );
        await receive(
          bytes: StickerWireCodec.encode(other),
          signed: true,
          pki: true,
        );
        final m = await only();
        expect(m.rawPayload, original.rawPayload);
        expect(m.xeddsaSigned, isFalse);
        expect(m.pkiEncrypted, isFalse);
        expect(messageContent(m), isA<StickerMessageContent>());
      },
    );

    test(
      'different radio recipient cannot authenticate mirror content',
      () async {
        await mirror.messages([parsed()]);
        await receive(to: 42, pki: true);
        final m = await only();
        expect(m.toNum, broadcastNum);
        expect(m.xeddsaSigned, isFalse);
        expect(m.pkiEncrypted, isFalse);
      },
    );

    test(
      'simultaneous conflicting sources never produce a text/sticker/emoji hybrid',
      () async {
        await Future.wait([
          mirror.messages([parsed()]),
          radio.handle(
            FromRadio(
              packet: MeshPacket(
                id: 456,
                from: 0x12345678,
                to: broadcastNum,
                decoded: Data(
                  portnum: PortNum.TEXT_MESSAGE_APP,
                  payload: utf8.encode('👍'),
                  emoji: 1,
                  replyId: 7,
                ),
              ),
            ),
          ),
        ]);
        final m = await only();
        final content = messageContent(m);
        expect(content, isNot(isA<UnsupportedMessageContent>()));
        if (content is StickerMessageContent) {
          expect(m.emoji, 0);
          expect(m.rawPayload, payload);
        } else {
          expect(m.body, '👍');
          expect(m.portnum, 1);
          expect(m.emoji, 1);
          expect(m.rawPayload, isNull);
        }
      },
    );

    test(
      'outgoing ACK, PKI, channel and time survive mirror snapshots and radio echoes',
      () async {
        var next = 456;
        final sender = MessageSender(
          db,
          (_) async => const DeliveryResult(
            DeliveryStatus.acked,
            null,
            MeshPacket_AckProofStatus.ACK_PROOF_VALID,
          ),
          () => 0x12345678,
          () => next++,
        );
        await sender.sendStickerToChannel(
          channel: 0,
          channelKey: 'mediumfast',
          sticker: envelope,
          replyId: 7,
        );
        final first = await only();
        await mirror.messages([
          parsed({'text': null, 'received_at': '2020-01-01T00:00:00Z'}),
        ]);
        await receive();
        final m = await only();
        expect(m.isOutgoing, isTrue);
        expect(m.ackState, AckState.acked);
        expect(m.ackProof, first.ackProof);
        expect(m.rxTime, first.rxTime);
        expect(m.channel, first.channel);
        expect(m.replyId, 7);
        expect(m.rawPayload, first.rawPayload);
      },
    );

    test(
      'legacy text reaction metadata can be filled by radio without changing a sticker',
      () async {
        await mirror.messages([
          MirrorMessage(
            id: 123,
            packetId: 456,
            fromId: '!12345678',
            channel: 'MediumFast',
            text: '👍',
          ),
        ]);
        await radio.handle(
          FromRadio(
            packet: MeshPacket(
              id: 456,
              from: 0x12345678,
              to: broadcastNum,
              decoded: Data(
                portnum: PortNum.TEXT_MESSAGE_APP,
                payload: utf8.encode('👍'),
                emoji: 1,
                replyId: 7,
              ),
            ),
          ),
        );
        final message = await only();
        expect(message.emoji, 1);
        expect(message.replyId, 7);
        await mirror.messages([
          MirrorMessage(
            id: 123,
            packetId: 456,
            fromId: '!12345678',
            channel: 'MediumFast',
            text: '👍',
            emoji: 0,
          ),
        ]);
        expect((await only()).emoji, 1);
      },
    );

    test(
      'live WS init, malformed frame, relay updates and reconnect share the same persistence path',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        var connections = 0;
        final processed = StreamController<void>();
        server.listen((request) async {
          final ws = await WebSocketTransformer.upgrade(request);
          connections++;
          sockets.add(ws);
          ws.listen((_) {});
          ws.add(
            jsonEncode({
              'type': 'init',
              'messages': [
                dto(),
                {...dto(), 'sticker': null},
              ],
            }),
          );
          ws.add('{invalid json');
          ws.add(
            jsonEncode({
              'type': 'new_message',
              'message': {
                ...dto(),
                'sticker': {...dto()['sticker'], 'wire_version': 3},
              },
            }),
          );
          ws.add(jsonEncode({'type': 'new_message', 'message': dto()}));
          for (final n in [...List.generate(21, (i) => i), 20]) {
            ws.add(
              jsonEncode({
                'type': 'relay_update',
                'message_id': 123,
                'relay': {'node_id': '!gateway$n'},
              }),
            );
          }
          ws.add(
            jsonEncode({
              'type': 'new_message',
              'message': {
                'id': 999,
                'packet_id': 1000,
                'from_id': '!12345678',
                'to_id': '^all',
                'channel': 'MediumFast',
                'text': 'queue marker',
              },
            }),
          );
        });
        final rt = MirrorRealtime(
          Uri.parse('ws://127.0.0.1:${server.port}/ws'),
          (event) async {
            switch (event) {
              case MirrorInit(:final messages):
                await mirror.messages(messages);
              case MirrorNewMessage(:final message):
                await mirror.messages([message], live: true);
                if (message.packetId == 1000) processed.add(null);
              case MirrorRelayUpdate(:final messageId, :final relay):
                await mirror.relay(messageId, relay);
              default:
                break;
            }
          },
        );
        final markers = StreamIterator(processed.stream);
        try {
          rt.start();
          expect(
            await markers.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
          await receive();
          rt.reconnectNow();
          expect(
            await markers.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
          final rows = await db.select(db.messages).get();
          expect(rows.length, 2);
          final sticker = rows.singleWhere((m) => m.packetId == 456);
          expect(sticker.rawPayload, payload);
          expect(messageContent(sticker), isA<StickerMessageContent>());
          expect(sticker.relayCount, 21);
          expect(sticker.heardOnRadio && sticker.heardOnMirror, isTrue);
          expect(sticker.rxSnr, 6.5);
          expect(connections, 2);
          expect(await db.select(db.stickerSources).get(), isEmpty);
        } finally {
          await rt.stop();
          rt.dispose();
          await markers.cancel();
          await processed.close();
          for (final socket in sockets) {
            await socket.close();
          }
          await server.close(force: true);
        }
      },
    );

    test(
      'invalid programmatic models, hidden channels and reused mirror IDs do not poison following rows',
      () async {
        await mirror.messages([
          MirrorMessage(
            id: 1,
            fromId: '!12345678',
            channel: 'MediumFast',
            kind: 'sticker',
            portnum: 256,
            text: '[Sticker]',
          ),
          parsed(),
        ]);
        await mirror.messages([
          parsed({'packet_id': 999}),
          parsed({'id': 124, 'packet_id': 457}),
        ]);
        expect(await db.select(db.messages).get(), hasLength(2));
        await db.setSetting(AppSettingKeys.hiddenChannels, '["hidden"]');
        await mirror.messages([
          parsed({'id': 125, 'packet_id': 458, 'channel': 'Hidden'}),
        ]);
        expect(await db.select(db.messages).get(), hasLength(2));
      },
    );
  });
}
