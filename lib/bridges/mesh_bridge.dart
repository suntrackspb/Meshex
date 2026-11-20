import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

import '../core/proto/channel_names.dart';
import '../core/proto/mesh.dart';
import '../core/radio/send_queue.dart';
import '../data/database.dart';
import '../data/mentions.dart';
import '../data/message_sender.dart';
import '../data/packet_router.dart' show senderTime;
import 'bridge_config.dart';
import 'bridge_protocol.dart';

typedef IncomingMeshText = ({int node, MeshPacket packet, String text});
const bridgeSettingsKey = 'bridge.config';
const _maxCommands = 2048;
const _commandLifetime = Duration(hours: 24);

class BridgeChannel {
  const BridgeChannel(this.index, this.title, this.fingerprint);
  final int index;
  final String title;
  final String fingerprint;
}

Future<List<BridgeChannel>> bridgeChannels(AppDatabase db) async {
  final rows = await db.select(db.channels).get();
  final lora = await (db.select(
    db.configBlobs,
  )..where((b) => b.key.equals('config.lora'))).getSingleOrNull();
  final preset = lora == null
      ? 'LongFast'
      : modemPresetName(Config.fromBuffer(lora.data).lora);
  final result = <BridgeChannel>[];
  for (final row in rows) {
    if (row.role == Channel_Role.DISABLED.value) continue;
    final name = channelDisplayName(
      row.name,
      primary: row.role == Channel_Role.PRIMARY.value,
      presetName: preset,
    );
    if (name.isEmpty) continue;
    final data = jsonEncode([row.index, row.role, name, row.psk]);
    final digest = await Sha256().hash(utf8.encode(data));
    result.add(BridgeChannel(row.index, name, base64UrlEncode(digest.bytes)));
  }
  return result;
}

class MeshBridge {
  MeshBridge({
    required this.config,
    required this.db,
    required AppDatabase settings,
    required this.connectedNode,
    required this.sender,
    required this.link,
    required this.onDisconnect,
  }) : _commands = _BridgeCommands(settings, config.id),
       _channelIds = {
         for (final fingerprint in config.channels.keys)
           fingerprint: bridgeNonce(),
       };

  final BridgeConfig config;
  final AppDatabase Function() db;
  final int? Function() connectedNode;
  final MessageSender Function() sender;
  final BridgeLink link;
  final void Function() onDisconnect;
  final _BridgeCommands _commands;
  final Map<String, String> _channelIds;
  final _replies = <String, ({String target, int packetId, int author})>{};
  final _outbound = Queue<({String method, BridgeJson data})>();
  StreamSubscription<void>? _subscription;
  bool _closed = false;
  bool _publishing = false;

  String get _nodeId => nodeIdString(config.node);

  Future<void> start(Stream<IncomingMeshText> incoming) async {
    await link.open(_handle, onDisconnect);
    if (_closed) return;
    _subscription = incoming
        .asyncMap(_onText)
        .listen((_) {}, onError: (Object _) => onDisconnect());
  }

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription?.cancel());
    _outbound.clear();
    _replies.clear();
    link.close();
  }

  AppDatabase _connectedDb() {
    if (_closed || connectedNode() != config.node) {
      throw const BridgeError(-32001, 'Connect the bridge node in Meshex');
    }
    return db();
  }

  Future<void> _onText(IncomingMeshText event) async {
    final (node: node, packet: packet, text: text) = event;
    if (_closed ||
        node != config.node ||
        connectedNode() != node ||
        packet.from == node ||
        packet.from == 0 ||
        text.trim().isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    final received = DateTime.fromMillisecondsSinceEpoch(
      senderTime(packet.rxTime, now.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
    if (now.difference(received) > const Duration(minutes: 10)) return;
    final currentDb = db();
    final direct = packet.to == node;
    BridgeChannel? channel;
    if (direct) {
      if (!config.direct) return;
    } else {
      if (packet.to != broadcastNum || config.channels.isEmpty) return;
      channel = (await bridgeChannels(
        currentDb,
      )).where((c) => c.index == packet.channel).firstOrNull;
      final mode = config.channels[channel?.fingerprint];
      if (mode == null) return;
      if (mode == BridgeChannelMode.mentions) {
        final me = await _node(currentDb, node);
        if (!NodeMentions.mentions(
          text,
          node,
          longName: me?.longName ?? '',
          shortName: me?.shortName ?? '',
          userId: me?.userId ?? '',
        )) {
          return;
        }
      }
    }
    final author = await _node(currentDb, packet.from);
    if (_closed || connectedNode() != node || author?.isIgnored == true) return;
    final target = direct
        ? _directTarget(packet.from, _name(author, packet.from))
        : _channelTarget(channel!);
    final reply = bridgeNonce();
    if (_replies.length >= 512) _replies.remove(_replies.keys.first);
    _replies[reply] = (
      target: target['id'] as String,
      packetId: packet.id,
      author: packet.from,
    );
    _publish('mesh.messageReceived', {
      'nodeId': _nodeId,
      'messageId': '${nodeIdString(packet.from)}:${packet.id}',
      'author': {
        'id': nodeIdString(packet.from),
        'name': _name(author, packet.from),
      },
      'target': target,
      'replyRef': reply,
      'text': text,
      'receivedAt': received.toIso8601String(),
      'radio': _radioMetadata(packet),
      'packet': {
        'json': packet.toProto3Json(),
        'protobufBase64': base64Encode(packet.writeToBuffer()),
      },
    });
  }

  static BridgeJson _radioMetadata(MeshPacket packet) {
    final data = packet.decoded;
    final start = packet.hopStart;
    final limit = packet.hopLimit;
    // Older senders left hopStart at zero. A decoded bitfield distinguishes
    // an intentional zero on newer firmware, even if the header value is omitted.
    final hopsKnown =
        (start > 0 || data.hasBitfield()) &&
        start <= 7 &&
        limit >= 0 &&
        limit <= start;
    return {
      'packetId': packet.id,
      'destinationId': nodeIdString(packet.to),
      if (packet.to == broadcastNum || packet.hasChannel())
        'channelIndex': packet.channel,
      if (packet.hasRxTime()) 'rxTime': packet.rxTime,
      if (packet.hasRxRssi()) 'rxRssi': packet.rxRssi,
      if (packet.hasRxSnr() && packet.rxSnr.isFinite) 'rxSnr': packet.rxSnr,
      if (packet.hasHopStart()) 'hopStart': start,
      if (packet.hasHopLimit()) 'hopLimit': limit,
      if (hopsKnown) 'hops': start - limit,
      if (packet.hasRelayNode()) 'relayNode': packet.relayNode,
      if (packet.hasNextHop()) 'nextHop': packet.nextHop,
      if (packet.hasTransportMechanism())
        'transportMechanism': packet.transportMechanism.name,
      if (packet.hasDelayed()) 'delayed': packet.delayed.name,
      if (packet.hasPriority()) 'priority': packet.priority.name,
      'viaMqtt': packet.viaMqtt,
      'wantAck': packet.wantAck,
      'pkiEncrypted': packet.pkiEncrypted,
      'xeddsaSigned': packet.xeddsaSigned,
      'portNum': data.portnum.value,
      if (data.replyId != 0) 'replyId': data.replyId,
      if (data.hasBitfield()) 'bitfield': data.bitfield,
    };
  }

  Future<BridgeJson> _handle(String method, BridgeJson params) async {
    return switch (method) {
      'mesh.listTargets' => _targets(params),
      'mesh.sendMessage' => _send(params),
      _ => throw const BridgeError(-32601, 'Unknown method'),
    };
  }

  Future<BridgeJson> _targets(BridgeJson params) async {
    final currentDb = _connectedDb();
    final query = params['query'] == null
        ? ''
        : bridgeString(params, 'query', max: 80).toLowerCase();
    final result = <BridgeJson>[];
    if (config.sendChannels) {
      for (final channel in await bridgeChannels(currentDb)) {
        if (_channelIds.containsKey(channel.fingerprint) &&
            channel.title.toLowerCase().contains(query)) {
          result.add(_channelTarget(channel));
        }
      }
    }
    if (config.sendDirect) {
      final nodes = await (currentDb.select(
        currentDb.nodes,
      )..orderBy([(n) => OrderingTerm.asc(n.longName)])).get();
      for (final node in nodes) {
        if (result.length == 100) break;
        if (node.num != config.node &&
            !node.isIgnored &&
            directBlock(node) == null &&
            [
              node.longName,
              node.shortName,
              nodeIdString(node.num),
            ].any((value) => value.toLowerCase().contains(query))) {
          result.add(_directTarget(node.num, _name(node, node.num)));
        }
      }
    }
    _connectedDb();
    return {'nodeId': _nodeId, 'targets': result};
  }

  Future<BridgeJson> _send(BridgeJson params) async {
    final command = bridgeString(params, 'commandId', max: 128);
    final text = bridgeString(params, 'text', max: bridgeFrameLimit);
    if (messageBytes(text) > maxMessageBytes) {
      throw const BridgeError(-32004, 'Text exceeds 200 UTF-8 bytes');
    }
    if (bridgeString(params, 'nodeId', max: 9) != _nodeId) {
      throw const BridgeError(-32001, 'Target belongs to another bridge node');
    }
    final isReply = params.containsKey('replyRef');
    if (isReply == params.containsKey('targetId')) {
      throw const BridgeError(-32602, 'Provide targetId or replyRef');
    }
    final key = bridgeString(
      params,
      isReply ? 'replyRef' : 'targetId',
      max: 80,
    );
    final mention = params.containsKey('mentionAuthor');
    if (mention && (!isReply || params['mentionAuthor'] is! bool)) {
      throw const BridgeError(-32602, 'mentionAuthor requires replyRef');
    }
    final digest = await Sha256().hash(
      utf8.encode(
        jsonEncode([
          _nodeId,
          isReply,
          key,
          params['mentionAuthor'] == true,
          text,
        ]),
      ),
    );
    final previous = await _commands.claim(
      command,
      base64UrlEncode(digest.bytes),
    );
    if (previous != null) return previous;

    final BridgeJson result;
    try {
      result = await _dispatch(
        command,
        text,
        key,
        isReply,
        params['mentionAuthor'] == true,
      );
    } catch (error) {
      final failure = error is BridgeError
          ? error
          : const BridgeError(-32005, 'Meshex could not queue the message');
      await _commands.finish(command, {
        'status': 'rejected',
        'code': failure.code,
        'message': failure.message,
      });
      throw failure;
    }
    await _commands.finish(command, result);
    return result;
  }

  Future<BridgeJson> _dispatch(
    String command,
    String text,
    String key,
    bool isReply,
    bool mentionAuthor,
  ) async {
    _connectedDb();
    final reply = isReply ? _replies[key] : null;
    if (isReply && reply == null) {
      throw const BridgeError(-32003, 'Reply is no longer available');
    }
    final target = reply?.target ?? key;
    if (mentionAuthor) {
      if (!target.startsWith('channel:')) {
        throw const BridgeError(-32602, 'Mentions require a channel reply');
      }
      text = '${nodeIdString(reply!.author)} $text';
      if (messageBytes(text) > maxMessageBytes) {
        throw const BridgeError(
          -32004,
          'Text with mention exceeds 200 UTF-8 bytes',
        );
      }
    }
    final submitted = Completer<BridgeJson>();
    void queued(int id) =>
        submitted.complete({'status': 'queued', 'packetId': id});
    void delivery(int id, DeliveryResult result) {
      _publish('mesh.deliveryChanged', {
        'nodeId': _nodeId,
        'commandId': command,
        'packetId': id,
        'status': result.status.name,
        if (result.accepted ||
            result.status == DeliveryStatus.acked ||
            result.status == DeliveryStatus.failed)
          'accepted': true,
        if (result.status == DeliveryStatus.rejected) 'accepted': false,
        if (result.error != null) 'error': result.error!.name,
        if (result.ackProof != null) 'ackProof': result.ackProof!.name,
      });
    }

    Future<void> sending;
    if (target.startsWith('dm:')) {
      final id = target.substring(3);
      final peer = RegExp(r'^![a-f0-9]{8}$').hasMatch(id)
          ? int.parse(id.substring(1), radix: 16)
          : null;
      Future<void> validate() async {
        final database = _connectedDb();
        final node = peer == null ? null : await _node(database, peer);
        if (!config.sendDirect ||
            peer == config.node ||
            node?.isIgnored == true ||
            directBlock(node) != null) {
          throw const BridgeError(-32002, 'Direct target is unavailable');
        }
        _connectedDb();
      }

      await validate();
      sending = sender().sendDirect(
        to: peer!,
        text: text,
        replyId: reply?.packetId,
        onQueued: queued,
        onDelivery: delivery,
        validateTarget: validate,
      );
    } else {
      Future<BridgeChannel> resolve() async {
        final database = _connectedDb();
        final channel = (await bridgeChannels(database))
            .where(
              (c) =>
                  _channelIds.containsKey(c.fingerprint) &&
                  _channelTarget(c)['id'] == target,
            )
            .firstOrNull;
        if (!config.sendChannels || channel == null) {
          throw const BridgeError(-32002, 'Channel target is unavailable');
        }
        _connectedDb();
        return channel;
      }

      final channel = await resolve();
      sending = sender().sendToChannel(
        channel: channel.index,
        channelKey: channelKey(channel.title),
        text: text,
        replyId: reply?.packetId,
        onQueued: queued,
        onDelivery: delivery,
        validateTarget: () async {
          await resolve();
        },
      );
    }
    unawaited(
      sending.catchError((Object error, StackTrace stack) {
        if (!submitted.isCompleted) {
          submitted.completeError(
            error is BridgeError
                ? error
                : const BridgeError(
                    -32005,
                    'Meshex could not queue the message',
                  ),
            stack,
          );
        } else {
          _publish('mesh.deliveryChanged', {
            'nodeId': _nodeId,
            'commandId': command,
            'status': 'unknown',
          });
        }
      }),
    );
    return submitted.future;
  }

  void _publish(String method, BridgeJson data) {
    if (_closed || _outbound.length >= 128) return;
    _outbound.add((method: method, data: data));
    if (!_publishing) unawaited(_flush());
  }

  Future<void> _flush() async {
    _publishing = true;
    try {
      while (!_closed && _outbound.isNotEmpty) {
        final event = _outbound.removeFirst();
        await link.publish(event.method, event.data);
      }
    } catch (_) {
      if (!_closed) onDisconnect();
    } finally {
      _publishing = false;
    }
  }

  BridgeJson _channelTarget(BridgeChannel channel) => {
    'id': 'channel:${_channelIds[channel.fingerprint]}',
    'kind': 'channel',
    'name': channel.title,
  };

  static BridgeJson _directTarget(int node, String title) => {
    'id': 'dm:${nodeIdString(node)}',
    'kind': 'direct',
    'name': title,
  };

  static Future<Node?> _node(AppDatabase db, int num) =>
      (db.select(db.nodes)..where((n) => n.num.equals(num))).getSingleOrNull();

  static String _name(Node? node, int num) =>
      [node?.longName, node?.shortName]
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .firstOrNull ??
      nodeIdString(num);
}

class _BridgeCommands {
  _BridgeCommands(this.db, String id) : key = 'bridge.commands.$id';
  final AppDatabase db;
  final String key;

  Future<BridgeJson> _read() async =>
      bridgeObject(jsonDecode(await db.getSetting(key) ?? '{}'));

  Future<BridgeJson?> claim(String id, String digest) => db.transaction(
    () async {
      final all = await _read();
      final now = DateTime.now().millisecondsSinceEpoch;
      all.removeWhere((_, value) => (value['expires'] as int) <= now);
      final existing = all[id] as BridgeJson?;
      if (existing != null) {
        if (existing['digest'] != digest) {
          throw const BridgeError(
            -32006,
            'commandId was reused with different parameters',
          );
        }
        final result = existing['result'] as BridgeJson;
        if (result['status'] == 'rejected') {
          throw BridgeError(result['code'] as int, result['message'] as String);
        }
        return result;
      }
      if (all.length >= _maxCommands) {
        throw const BridgeError(-32007, 'Daily bridge command limit reached');
      }
      all[id] = {
        'digest': digest,
        'expires': now + _commandLifetime.inMilliseconds,
        'result': {'status': 'unknown'},
      };
      await db.setSetting(key, jsonEncode(all));
      return null;
    },
  );

  Future<void> finish(String id, BridgeJson result) async {
    try {
      await db.transaction(() async {
        final all = await _read();
        final existing = all[id] as BridgeJson?;
        if (existing == null) return;
        existing['result'] = result;
        await db.setSetting(key, jsonEncode(all));
      });
    } catch (_) {
      // The durable reservation already prevents a second send.
    }
  }
}
