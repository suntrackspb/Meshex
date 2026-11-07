import 'dart:convert';
import 'dart:typed_data';

import '../core/proto/generated/meshtastic/config.pb.dart';
import '../core/stickers/wire_codec.dart';
import 'avatar_frames.dart';

/// Модели API зеркала (`/api/nodes`, `/api/chat/history`, WS `/ws`).
/// Перенос 1:1 из iOS-клиента. JSON в snake_case; почти все поля опциональны.

class MirrorRelay {
  const MirrorRelay({this.nodeId, this.snr, this.rssi, this.hops});

  factory MirrorRelay.fromJson(Map<String, dynamic> j) => MirrorRelay(
    nodeId: _string(j['node_id']),
    snr: _double(j['snr']),
    rssi: _int(j['rssi']),
    hops: _int(j['hops']),
  );

  final String? nodeId;
  final double? snr;
  final int? rssi;
  final int? hops;
}

class MirrorMessage {
  const MirrorMessage({
    required this.id,
    required this.fromId,
    this.packetId,
    this.toId,
    this.text,
    this.kind = 'text',
    this.portnum = 1,
    this.sticker,
    this.replyToPacketId,
    this.emoji,
    this.snr,
    this.rssi,
    this.channel,
    this.receivedAt,
    this.sentAt,
    this.shortName,
    this.longName,
    this.isBot = false,
    this.relays = const [],
  });

  /// Invalid content is skipped, never downgraded to the fallback text. A
  /// malformed record must not prevent the next history/init row from parsing.
  static MirrorMessage? tryParse(Object? raw) {
    if (raw is! Map || raw['type'] == 'name_change') {
      return null;
    }
    final id = raw['id'], from = raw['from_id'];
    if (id is! int || id <= 0 || from is! String) return null;
    final kind = raw['kind'] ?? 'text';
    if (kind is! String) return null;
    final int portnum;
    StickerEnvelope? sticker;
    if (kind == 'sticker') {
      if (raw['portnum'] is! int ||
          raw['portnum'] != StickerWireCodec.portnum ||
          raw['sticker'] is! Map ||
          (raw['emoji'] != null &&
              (raw['emoji'] is! int || raw['emoji'] != 0)) ||
          !_packetNumber(raw['packet_id']) ||
          !_packetNumber(raw['reply_to_packet_id'])) {
        return null;
      }
      final to = raw['to_id'];
      if (nodeNumFromId(from) == null ||
          (to != null &&
              (to is! String || (to != '^all' && nodeNumFromId(to) == null)))) {
        return null;
      }
      try {
        sticker = StickerEnvelope.fromJson(
          (raw['sticker'] as Map).cast<String, dynamic>(),
        );
      } on FormatException {
        return null;
      }
      portnum = StickerWireCodec.portnum;
    } else if (kind == 'text') {
      if ((raw['portnum'] != null &&
              (raw['portnum'] is! int || raw['portnum'] != 1)) ||
          raw['sticker'] != null) {
        return null;
      }
      portnum = 1;
    } else {
      return null;
    }
    return MirrorMessage(
      id: id,
      fromId: from,
      kind: kind,
      portnum: portnum,
      sticker: sticker,
      packetId: _int(raw['packet_id']),
      toId: _string(raw['to_id']),
      text: _string(raw['text']),
      replyToPacketId: _int(raw['reply_to_packet_id']),
      emoji: _int(raw['emoji']),
      snr: _double(raw['snr']),
      rssi: _int(raw['rssi']),
      channel: _string(raw['channel']),
      receivedAt: parseMirrorDate(_string(raw['received_at'])),
      sentAt: parseMirrorDate(_string(raw['sent_at'])),
      shortName: _string(raw['short_name']),
      longName: _string(raw['long_name']),
      isBot: raw['is_bot'] == true,
      relays: [
        for (final r in _list(raw['relays']))
          if (r is Map<String, dynamic>) MirrorRelay.fromJson(r),
      ],
    );
  }

  bool get isSticker => kind == 'sticker';
  bool get hasValidContent => switch (kind) {
    'text' => portnum == 1 && sticker == null,
    'sticker' =>
      portnum == StickerWireCodec.portnum &&
          sticker != null &&
          (emoji == null || emoji == 0) &&
          nodeNumFromId(fromId) != null &&
          (toId == null || toId == '^all' || nodeNumFromId(toId!) != null) &&
          _packetNumber(packetId) &&
          _packetNumber(replyToPacketId),
    _ => false,
  };

  final String kind;
  final int portnum;
  final StickerEnvelope? sticker;

  final int id;
  final int? packetId;
  final String fromId;
  final String? toId;
  final String? text;
  final int? replyToPacketId;

  /// Data.emoji: не 0 — реакция на [replyToPacketId]. Старое зеркало
  /// поле не отдаёт — null.
  final int? emoji;
  final double? snr;
  final int? rssi;
  final String? channel;
  final DateTime? receivedAt;
  final DateTime? sentAt;
  final String? shortName;
  final String? longName;
  final bool isBot;
  final List<MirrorRelay> relays;
}

class MirrorNode {
  const MirrorNode({
    required this.nodeId,
    this.longName,
    this.shortName,
    this.hwModel,
    this.role,
    this.lastLat,
    this.lastLon,
    this.precisionBits,
    this.positionCorrected = false,
    this.positionAt,
    this.goodLat,
    this.goodLon,
    this.goodAt,
    this.lastSeenAt,
    this.batteryLevel,
    this.voltage,
    this.channelUtilization,
    this.airUtilTx,
    this.uptimeSeconds,
    this.isUnmessagable,
    this.lastSnr,
    this.modemPreset,
    this.publicKey,
    this.firmwareVersion,
  });

  static int? _role(Object? v) => switch (v) {
    int() => v,
    String() =>
      Config_DeviceConfig_Role.values
          .where((r) => r.name == v)
          .firstOrNull
          ?.value,
    _ => null,
  };

  static MirrorNode? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['node_id'];
    if (id is! String) return null;
    return MirrorNode(
      nodeId: id,
      longName: raw['long_name'] as String?,
      shortName: raw['short_name'] as String?,
      hwModel: _int(raw['hw_model']),
      role: _role(raw['role']),
      lastLat: _double(raw['last_lat']),
      lastLon: _double(raw['last_lon']),
      precisionBits: _int(raw['last_precision_bits']),
      positionCorrected: raw['position_corrected'] == true,
      positionAt: parseMirrorDate(raw['position_at'] as String?),
      goodLat: _double(raw['last_good_lat']),
      goodLon: _double(raw['last_good_lon']),
      goodAt: parseMirrorDate(raw['last_good_at'] as String?),
      lastSeenAt: parseMirrorDate(raw['last_seen_at'] as String?),
      batteryLevel: _int(raw['battery_level']),
      voltage: _double(raw['voltage']),
      channelUtilization: _double(raw['channel_utilization']),
      airUtilTx: _double(raw['air_util_tx']),
      uptimeSeconds: _int(raw['uptime_seconds']),
      isUnmessagable: raw['is_unmessagable'] is bool
          ? raw['is_unmessagable'] as bool
          : null,
      lastSnr: _double(raw['last_snr']),
      modemPreset: raw['modem_preset'] is String
          ? raw['modem_preset'] as String
          : null,
      publicKey: raw['public_key'] as String?,
      firmwareVersion: raw['firmware_version'] is String
          ? raw['firmware_version'] as String
          : null,
    );
  }

  final String nodeId;
  final String? longName;
  final String? shortName;
  final int? hwModel;

  /// Номер Config.DeviceConfig.Role; сервер отдаёт имя (`CLIENT_MUTE`).
  final int? role;
  final double? lastLat;
  final double? lastLon;
  final int? precisionBits;

  /// Зеркало подменило координаты исправленными по соседям.
  final bool positionCorrected;

  /// Время последней позиции из истории зеркала (не исправленной); null —
  /// истории нет (координаты могут быть сколь угодно старыми).
  final DateTime? positionAt;

  /// Последняя точка истории вне зон глушилок и её время.
  final double? goodLat;
  final double? goodLon;
  final DateTime? goodAt;
  final DateTime? lastSeenAt;
  final int? batteryLevel;

  // Телеметрия и флаг — только в карточке ноды, в общем списке их нет.
  final double? voltage;
  final double? channelUtilization;
  final double? airUtilTx;
  final int? uptimeSeconds;
  final bool? isUnmessagable;
  final double? lastSnr;
  final String? modemPreset;

  /// Из MapReport; в списке /api/nodes сервер пока не отдаёт, только в карточке.
  final String? firmwareVersion;

  /// Пока сервер не отдаёт — null; hex (64 символа) или base64 (32 байта).
  final String? publicKey;

  Uint8List? get publicKeyBytes {
    final k = publicKey;
    if (k == null || k.isEmpty) return null;
    if (k.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(k)) {
      return Uint8List.fromList([
        for (var i = 0; i < 64; i += 2)
          int.parse(k.substring(i, i + 2), radix: 16),
      ]);
    }
    try {
      final b = Uri.parse('data:;base64,$k').data?.contentAsBytes();
      if (b != null && b.length == 32) return b;
    } catch (_) {}
    return null;
  }
}

/// Кадры WebSocket `/ws`.
sealed class MirrorEvent {
  const MirrorEvent();

  static MirrorEvent parse(Map<String, dynamic> j) => switch (j['type']) {
    'init' => MirrorInit(
      _messages(j['messages']),
      ranks: j.containsKey('chatty_ranks')
          ? parseChattyRanks(j['chatty_ranks'])
          : null,
      frames: j.containsKey('avatar_frames')
          ? parseCustomFrames(j['avatar_frames'])
          : null,
    ),
    'chatty_ranks' => MirrorChattyRanks(parseChattyRanks(j['ranks'])),
    'avatar_frames' => MirrorAvatarFrames(parseCustomFrames(j['frames'])),
    'new_message' => switch (MirrorMessage.tryParse(j['message'])) {
      final m? => MirrorNewMessage(m),
      null => const MirrorOther(),
    },
    'relay_update'
        when j['message_id'] is int && j['relay'] is Map<String, dynamic> =>
      MirrorRelayUpdate(
        j['message_id'] as int,
        MirrorRelay.fromJson(j['relay'] as Map<String, dynamic>),
      ),
    'node_update' => switch (MirrorNode.tryParse(j['node'])) {
      final n? => MirrorNodeUpdate(n),
      null => const MirrorOther(),
    },
    _ => const MirrorOther(),
  };
}

class MirrorInit extends MirrorEvent {
  MirrorInit(this.messages, {this.ranks, this.frames});
  final List<MirrorMessage> messages;

  /// Старое зеркало полей не шлёт — null.
  final Map<int, ChattyRank>? ranks;
  final Map<int, CustomFrame>? frames;
}

/// Топ-3 болтливых изменился.
class MirrorChattyRanks extends MirrorEvent {
  MirrorChattyRanks(this.ranks);
  final Map<int, ChattyRank> ranks;
}

/// Рамки из админки изменились.
class MirrorAvatarFrames extends MirrorEvent {
  MirrorAvatarFrames(this.frames);
  final Map<int, CustomFrame> frames;
}

class MirrorNewMessage extends MirrorEvent {
  MirrorNewMessage(this.message);
  final MirrorMessage message;
}

class MirrorRelayUpdate extends MirrorEvent {
  MirrorRelayUpdate(this.messageId, this.relay);
  final int messageId;
  final MirrorRelay relay;
}

class MirrorNodeUpdate extends MirrorEvent {
  MirrorNodeUpdate(this.node);
  final MirrorNode node;
}

class MirrorOther extends MirrorEvent {
  const MirrorOther();
}

/// Нераспознанные элементы пропускаем, а не валим весь разбор.
List<MirrorMessage> _messages(Object? raw) => [
  for (final m in (raw is List ? raw : const [])) ?MirrorMessage.tryParse(m),
];

List<MirrorMessage> parseMirrorMessages(Object? raw) => _messages(raw);

/// Бэкенд отдаёт и `2026-10-09 19:20:32.127335+00:00`, и `2026-10-09T19:02:01.107651Z`.
/// DateTime.parse понимает оба (пробел и микросекунды), но не без зоны — такие считаем UTC.
DateTime? parseMirrorDate(String? s) {
  if (s == null || s.isEmpty) return null;
  var v = s.trim();
  final hasZone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(v);
  if (!hasZone) v = '${v}Z';
  return DateTime.tryParse(v)?.toLocal();
}

/// `!a1b2c3d4` → номер ноды.
int? nodeNumFromId(String id) {
  final s = id.startsWith('!') ? id.substring(1) : id;
  return s.length == 8 && RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(s)
      ? int.tryParse(s, radix: 16)
      : null;
}

String? _string(Object? v) => v is String ? v : null;
bool _packetNumber(Object? v) =>
    v == null || (v is int && v >= 0 && v <= 0xffffffff);
int? _int(Object? v) =>
    v is int ? v : (v is num && v.isFinite ? v.toInt() : null);
double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

/// Список из JSON; realtime зеркала бывает присылает его строкой с JSON.
List<Object?> _list(Object? v) {
  if (v is List) return v;
  if (v is String && v.isNotEmpty) {
    try {
      final d = jsonDecode(v);
      if (d is List) return d;
    } catch (_) {}
  }
  return const [];
}
