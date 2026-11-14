import 'package:meshex/l10n/l10n.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

/// Полный выбор эмодзи для реакции. Возвращает эмодзи или null (закрыли).
/// Недавние ведём сами (быстрая панель), поэтому вкладки «недавние» нет.
Future<String?> pickEmoji(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final bg = scheme.surfaceContainerLow;
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: bg,
    builder: (ctx) => SafeArea(
      child: ChatEmojiPicker(onSelected: (emoji) => Navigator.pop(ctx, emoji)),
    ),
  );
}

/// Shared Unicode picker; glyphs are rendered with the platform's fonts.
class ChatEmojiPicker extends StatelessWidget {
  const ChatEmojiPicker({
    super.key,
    required this.onSelected,
    this.showRecents = false,
  });

  final ValueChanged<String> onSelected;
  final bool showRecents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surfaceContainerLow;
    return EmojiPicker(
      onEmojiSelected: (_, e) => onSelected(e.emoji),
      config: Config(
        height: 320,
        locale: Localizations.localeOf(context),
        emojiViewConfig: EmojiViewConfig(
          backgroundColor: bg,
          columns: 8,
          emojiSizeMax: 30,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: bg,
          initCategory: Category.SMILEYS,
          recentTabBehavior: showRecents
              ? RecentTabBehavior.RECENT
              : RecentTabBehavior.NONE,
          indicatorColor: scheme.primary,
          iconColor: scheme.onSurfaceVariant,
          iconColorSelected: scheme.primary,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          showBackspaceButton: false,
          backgroundColor: bg,
          buttonColor: bg,
          buttonIconColor: scheme.onSurfaceVariant,
        ),
        searchViewConfig: SearchViewConfig(
          backgroundColor: bg,
          buttonIconColor: scheme.onSurfaceVariant,
          hintText: context.l10n.search_6433b5,
        ),
      ),
    );
  }
}
