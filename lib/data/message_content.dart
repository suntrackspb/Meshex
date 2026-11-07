import 'dart:convert';

import '../core/proto/mesh.dart';
import '../core/stickers/wire_codec.dart';
import 'database.dart';

sealed class MessageContent {
  const MessageContent();
}

final class TextMessageContent extends MessageContent {
  const TextMessageContent(this.text);
  final String text;
}

final class StickerMessageContent extends MessageContent {
  const StickerMessageContent(this.envelope);
  final StickerEnvelope envelope;
}

final class UnsupportedMessageContent extends MessageContent {
  const UnsupportedMessageContent();
}

/// Treat inconsistent stored fields as unsupported, never fall back to body.
MessageContent messageContent(Message message) {
  if (isTextMessage(message)) {
    return message.rawPayload == null && message.stickerContent == null
        ? TextMessageContent(message.body)
        : const UnsupportedMessageContent();
  }
  if (message.portnum != StickerWireCodec.portnum ||
      message.rawPayload == null ||
      message.stickerContent == null) {
    return const UnsupportedMessageContent();
  }
  final envelope = StickerWireCodec.decode(message.rawPayload!);
  if (envelope == null) return const UnsupportedMessageContent();
  try {
    final structured = StickerEnvelope.fromJson(
      (jsonDecode(message.stickerContent!) as Map).cast<String, dynamic>(),
    );
    if (jsonEncode(structured.toJson()) != jsonEncode(envelope.toJson())) {
      return const UnsupportedMessageContent();
    }
  } on Object {
    return const UnsupportedMessageContent();
  }
  return StickerMessageContent(envelope);
}

bool isTextMessage(Message message) =>
    message.portnum == PortNum.TEXT_MESSAGE_APP.value;

String messageTextPreview(Message message, String unsupportedLabel) =>
    isTextMessage(message) ? message.body : unsupportedLabel;
