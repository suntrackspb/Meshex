import 'package:flutter/material.dart';
import 'package:meshex/l10n/l10n.dart';

import 'emoji_sheet.dart';

/// Desktop emoji menu. Inserting text preserves the composer's selection.
class EmojiButton extends StatelessWidget {
  const EmojiButton({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.menuController,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final MenuController menuController;

  void _insert(String emoji) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: menuController,
    consumeOutsideTap: false,
    menuChildren: [
      SizedBox(
        width: 360,
        child: ChatEmojiPicker(onSelected: _insert, showRecents: true),
      ),
    ],
    builder: (context, menu, child) => IconButton(
      tooltip: context.l10n.moreEmoji_2bfd6b,
      icon: const Icon(Icons.sentiment_satisfied_alt),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: enabled
          ? () => menu.isOpen ? menu.close() : menu.open()
          : null,
    ),
  );
}
