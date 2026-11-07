import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/proto/mesh.dart';
import '../core/radio/send_queue.dart';
import '../core/stickers/wire_codec.dart';
import 'database.dart';
import 'message_content.dart';

/// Лимит текста в байтах UTF-8 — как в официальном iOS-клиенте.
const maxMessageBytes = 200;

int messageBytes(String text) => utf8.encode(text).length;

/// Почему нельзя написать ноде лично.
enum DirectBlock {
  /// Ключ ещё не пришёл (NodeInfo не получен) — прошивка откажет с PKI_SEND_FAIL_PUBLIC_KEY.
  noKey,

  /// Нода сама не принимает сообщения.
  unmessagable,
}

/// Можно ли написать ноде лично (как `canDirectMessage` в официальном iOS).
DirectBlock? directBlock(Node? n) {
  if (n == null || n.publicKey == null || n.publicKey!.isEmpty) {
    return DirectBlock.noKey;
  }
  if (n.isUnmessagable) return DirectBlock.unmessagable;
  return null;
}

/// Отправка текстовых сообщений: запись в БД сразу (статус «ждём»),
/// затем статус по итогу очереди отправки.
class MessageSender {
  MessageSender(
    this.db,
    this._send,
    this._myNum,
    this._nextId, {
    this.prepareDirect,
    this.prepareSticker,
    this.stickerPayloadBudget,
  });

  final Future<void> Function(int)? prepareDirect;
  final Future<void> Function(StickerEnvelope)? prepareSticker;

  /// Transport-specific limit (PKI/signing/firmware), rechecked on retry.
  /// Until measured for the connected transport, 200 is only a software cap.
  final int Function(bool direct)? stickerPayloadBudget;

  final AppDatabase db;
  final Future<DeliveryResult> Function(MeshPacket p) _send;
  final int? Function() _myNum;
  final int Function() _nextId;

  /// Сообщение в канал [channel] (индекс на своей ноде).
  /// [emoji] — реакция на [replyId] (текст — сам эмодзи).
  Future<void> sendToChannel({
    required int channel,
    required String channelKey,
    required String text,
    int? replyId,
    bool emoji = false,
  }) => _new(
    to: broadcastNum,
    channel: channel,
    channelKey: channelKey,
    text: text,
    replyId: replyId,
    emoji: emoji,
  );

  /// Личное сообщение ноде [to]: шифруется её публичным ключом (PKI).
  Future<void> sendDirect({
    required int to,
    required String text,
    int? replyId,
    bool emoji = false,
  }) => _new(to: to, channel: 0, text: text, replyId: replyId, emoji: emoji);

  Future<void> sendStickerToChannel({
    required int channel,
    required String channelKey,
    required StickerEnvelope sticker,
    int? replyId,
    int payloadBudget = maxMessageBytes,
  }) => _new(
    to: broadcastNum,
    channel: channel,
    channelKey: channelKey,
    text: '[Sticker]',
    replyId: replyId,
    emoji: false,
    sticker: sticker,
    payloadBudget: payloadBudget,
  );

  Future<void> sendStickerDirect({
    required int to,
    required StickerEnvelope sticker,
    int? replyId,
    int payloadBudget = maxMessageBytes,
  }) => _new(
    to: to,
    channel: 0,
    text: '[Sticker]',
    replyId: replyId,
    emoji: false,
    sticker: sticker,
    payloadBudget: payloadBudget,
  );

  Future<void> _new({
    required int to,
    required int channel,
    String channelKey = '',
    required String text,
    int? replyId,
    required bool emoji,
    StickerEnvelope? sticker,
    int payloadBudget = maxMessageBytes,
  }) async {
    final me = _myNum();
    if (me == null) throw StateError('нет соединения с нодой');
    final payload = sticker == null
        ? Uint8List.fromList(utf8.encode(text))
        : StickerWireCodec.encode(sticker, payloadBudget: payloadBudget);
    final port = sticker == null
        ? PortNum.TEXT_MESSAGE_APP
        : PortNum.PRIVATE_APP;
    if (payload.length > maxMessageBytes) {
      throw ArgumentError('длиннее $maxMessageBytes байт');
    }
    if (sticker != null &&
        payload.length >
            (stickerPayloadBudget?.call(to != broadcastNum) ??
                maxMessageBytes)) {
      throw const FormatException('Sticker exceeds transport payload budget');
    }
    final key = to == broadcastNum ? null : await _publicKey(to);
    if (_myNum() != me) throw StateError('соединение с нодой изменилось');
    if (sticker != null) await prepareSticker?.call(sticker);
    if (_myNum() != me) throw StateError('соединение с нодой изменилось');
    final id = _nextId();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: id,
            fromNum: me,
            toNum: to,
            channel: Value(channel),
            channelKey: Value(channelKey),
            body: text,
            portnum: Value(port.value),
            rawPayload: Value(sticker == null ? null : payload),
            stickerContent: Value(
              sticker == null ? null : jsonEncode(sticker.toJson()),
            ),
            rxTime: DateTime.now(),
            isOutgoing: const Value(true),
            replyId: Value(replyId),
            emoji: Value(emoji ? 1 : 0),
            pkiEncrypted: Value(key != null),
            ackState: const Value(AckState.pending),
          ),
        );
    await _transmit(id, to, channel, key, payload, port, replyId, emoji);
  }

  /// Повторить неотправленное/неподтверждённое: новый id пакета, та же запись.
  Future<void> retry(Message m) async {
    if (!m.isOutgoing || m.channel == null) return;
    final content = messageContent(m);
    final Uint8List payload;
    final PortNum port;
    switch (content) {
      case TextMessageContent(:final text):
        payload = Uint8List.fromList(utf8.encode(text));
        port = PortNum.TEXT_MESSAGE_APP;
      case StickerMessageContent():
        payload = m.rawPayload!;
        port = PortNum.PRIVATE_APP;
      case UnsupportedMessageContent():
        throw StateError('тип сообщения не поддерживается');
    }
    if (payload.length > maxMessageBytes) {
      throw ArgumentError('длиннее $maxMessageBytes байт');
    }
    if (port == PortNum.PRIVATE_APP &&
        payload.length >
            (stickerPayloadBudget?.call(m.toNum != broadcastNum) ??
                maxMessageBytes)) {
      throw const FormatException('Sticker exceeds transport payload budget');
    }
    // Ключ мог появиться (или смениться) с прошлой попытки.
    final key = m.toNum == broadcastNum ? null : await _publicKey(m.toNum);
    if (content is StickerMessageContent) {
      await prepareSticker?.call(content.envelope);
    }
    final id = _nextId();
    await (db.update(db.messages)..where((r) => r.id.equals(m.id))).write(
      MessagesCompanion(
        packetId: Value(id),
        rxTime: Value(DateTime.now()),
        pkiEncrypted: Value(key != null),
        ackState: const Value(AckState.pending),
        ackError: const Value(null),
        ackProof: const Value(null),
      ),
    );
    await _transmit(
      id,
      m.toNum,
      m.channel!,
      key,
      payload,
      port,
      m.replyId,
      port == PortNum.TEXT_MESSAGE_APP && m.emoji != 0,
    );
  }

  /// Ключ получателя; без него личное не отправляем (прошивка всё равно откажет).
  Future<Uint8List> _publicKey(int num) async {
    await prepareDirect?.call(num);
    final n = await (db.select(
      db.nodes,
    )..where((r) => r.num.equals(num))).getSingleOrNull();
    switch (directBlock(n)) {
      case DirectBlock.noKey:
        throw StateError('нет публичного ключа ноды — дождитесь её NodeInfo');
      case DirectBlock.unmessagable:
        throw StateError('нода не принимает личные сообщения');
      case null:
        return n!.publicKey!;
    }
  }

  Future<void> _transmit(
    int id,
    int to,
    int channel,
    Uint8List? publicKey,
    Uint8List payload,
    PortNum port,
    int? replyId,
    bool emoji,
  ) async {
    final r = await _send(
      MeshPacket(
        id: id,
        to: to,
        channel: channel,
        wantAck: true,
        pkiEncrypted: publicKey != null,
        publicKey: publicKey,
        decoded: Data(
          portnum: port,
          payload: payload,
          replyId: replyId,
          emoji: emoji ? 1 : 0,
        ),
      ),
    );
    final (state, error) = switch (r.status) {
      DeliveryStatus.acked => (AckState.acked, null),
      DeliveryStatus.failed => (AckState.failed, r.error?.value),
      DeliveryStatus.timeout => (AckState.timeout, null),
      DeliveryStatus.rejected ||
      DeliveryStatus.disconnected => (AckState.notSent, null),
    };
    await (db.update(
      db.messages,
    )..where((m) => m.packetId.equals(id) & m.isOutgoing.equals(true))).write(
      MessagesCompanion(
        ackState: Value(state),
        ackError: Value(error),
        ackProof: Value(r.ackProof?.value),
      ),
    );
  }
}
