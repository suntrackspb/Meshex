import '../../core/notify/notify_channels.dart';
import '../database.dart';
import '../mentions.dart';
import '../message_content.dart';

/// Повод уведомить о сообщении.
enum AlertKind { direct, reaction, reply, mention }

/// Канал уведомлений Android для вида уведомления.
NotifyChannel notifyChannelFor(AlertKind k) => switch (k) {
  AlertKind.direct => NotifyChannel.direct,
  AlertKind.reaction => NotifyChannel.reactions,
  AlertKind.reply || AlertKind.mention => NotifyChannel.replies,
};

/// Какие уведомления включены (настройки приложения, по умолчанию все).
class AlertSettings {
  const AlertSettings({
    this.direct = true,
    this.reaction = true,
    this.reply = true,
    this.mention = true,
  });

  final bool direct;
  final bool reaction;
  final bool reply;
  final bool mention;

  bool allows(AlertKind k) => switch (k) {
    AlertKind.direct => direct,
    AlertKind.reaction => reaction,
    AlertKind.reply => reply,
    AlertKind.mention => mention,
  };
}

/// Всё, что нужно знать о сообщении, кроме него самого.
class AlertContext {
  const AlertContext({
    required this.me,
    this.myShortName = '',
    this.myLongName = '',
    this.myUserId = '',
    this.targetIsMine = false,
    this.senderIgnored = false,
    this.channelMuted = false,
    this.senderMuted = false,
  });

  final int me;
  final String myShortName;
  final String myLongName;
  final String myUserId;

  /// Сообщение, на которое ответили или отреагировали, — наше.
  final bool targetIsMine;
  final bool senderIgnored;
  final bool channelMuted;

  /// Уведомления от этой ноды отключены в её карточке.
  final bool senderMuted;
}

/// Решение «уведомлять ли» — чистая функция, без UI и платформы.
abstract final class MessageAlerts {
  /// Сообщение старше этого при появлении в базе — история (зеркало,
  /// повтор ноды), не уведомляем.
  static const maxAge = Duration(minutes: 10);

  static AlertKind? classify(Message m, AlertContext c) {
    final content = messageContent(m);
    if (content is UnsupportedMessageContent) return null;
    if (m.isOutgoing || m.fromNum == c.me || c.senderIgnored || c.senderMuted) {
      return null;
    }
    final direct = m.toNum == c.me;
    // Личка от этого не «замолкает»: mute — настройка канала.
    if (!direct && c.channelMuted) return null;
    if (content is TextMessageContent && m.emoji != 0) {
      return m.replyId != null && c.targetIsMine ? AlertKind.reaction : null;
    }
    if (direct) return AlertKind.direct;
    if (m.replyId != null && c.targetIsMine) return AlertKind.reply;
    if (content is TextMessageContent &&
        NodeMentions.mentions(
          content.text,
          c.me,
          shortName: c.myShortName,
          longName: c.myLongName,
          userId: c.myUserId,
        )) {
      return AlertKind.mention;
    }
    return null;
  }

  /// [name] встречается в тексте отдельным словом (без учёта регистра;
  /// буквы, цифры и `_` рядом — часть другого слова). `@` перед именем
  /// допускается.
  static bool mentions(String text, String name) {
    return NodeMentions.matches(text, [name]);
  }

  /// Заголовок и текст уведомления. [sender] — имя отправителя,
  /// [channel] — имя канала (для общих), [target] — текст нашего сообщения.
  static ({String title, String body}) content(
    AlertKind k,
    Message m, {
    required String sender,
    String channel = '',
    String target = '',
    String Function(String)? replyTitle,
    String Function(String, String)? reactionBody,
    String unsupportedLabel = 'Неподдерживаемое сообщение',
    String stickerLabel = 'Стикер',
  }) {
    final where = channel.isEmpty ? sender : '$sender · #$channel';
    final body = messageTextPreview(
      m,
      unsupportedLabel,
      stickerLabel: stickerLabel,
    );
    return switch (k) {
      AlertKind.direct => (title: sender, body: body),
      // Android: notification_reaction_to «%1$s к %2$s”».
      AlertKind.reaction => (
        title: where,
        body:
            reactionBody?.call(m.body, snippet(target)) ??
            '${m.body} к «${snippet(target)}»',
      ),
      AlertKind.reply => (
        title: replyTitle?.call(where) ?? '$where · ответ',
        body: body,
      ),
      AlertKind.mention => (title: where, body: body),
    };
  }

  static String snippet(String s, [int max = 40]) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final r = t.runes.toList();
    return r.length <= max ? t : '${String.fromCharCodes(r.take(max))}…';
  }
}
