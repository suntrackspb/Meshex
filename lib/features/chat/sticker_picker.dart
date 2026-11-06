import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/stickers.dart';
import '../../l10n/l10n.dart';

Future<StickerRef?> pickSticker(BuildContext context) =>
    showModalBottomSheet<StickerRef>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const StickerPicker(),
    );

/// Only the selected pack is built. Animation stays local to the device.
class StickerPicker extends StatefulWidget {
  const StickerPicker({super.key});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.l10n;
    final packs = StickerCatalog.packs;
    final pack = packs[_selected];
    final stickers = pack.stickers;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      strings.stickersTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final (index, item) in packs.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: index == _selected,
                        avatar: Icon(
                          item.animated
                              ? Icons.play_circle_outline
                              : Icons.emoji_emotions_outlined,
                          size: 18,
                        ),
                        label: Text('${item.title} · ${item.emojis.length}'),
                        onSelected: (_) => setState(() => _selected = index),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                strings.stickerSendHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                key: ValueKey(pack.id),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 112,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: stickers.length,
                itemBuilder: (context, index) {
                  final sticker = stickers[index];
                  final label =
                      '${strings.stickerLabel} ${sticker.emoji}, '
                      '${pack.title}, ${sticker.ref.id}';
                  return Semantics(
                    label: label,
                    button: true,
                    child: Tooltip(
                      message: label,
                      child: Material(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, sticker.ref),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: StickerImage(sticker: sticker),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StickerImage extends StatelessWidget {
  const StickerImage({super.key, required this.sticker});

  final StickerAsset sticker;

  @override
  Widget build(BuildContext context) {
    final still = sticker.animated && MediaQuery.disableAnimationsOf(context);
    final path = still
        ? sticker.path.replaceFirst('.webp', '.png')
        : sticker.path;
    return Image.asset(
      path,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }
}

/// A PRIVATE_APP envelope is a sticker only after protocol validation.
class StickerMessageBody extends StatelessWidget {
  const StickerMessageBody({super.key, required this.ref});

  final StickerRef ref;

  @override
  Widget build(BuildContext context) {
    final sticker = StickerCatalog.find(ref);
    if (sticker == null) {
      return SizedBox(
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sticky_note_2_outlined, size: 40),
            const SizedBox(height: 8),
            Text(context.l10n.stickerPackMissing, textAlign: TextAlign.center),
            Text(
              '${ref.pack} / ${ref.id}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      );
    }
    return Semantics(
      label: '${context.l10n.stickerLabel} ${sticker.emoji}',
      image: true,
      child: SizedBox.square(
        dimension: 200,
        child: StickerImage(sticker: sticker),
      ),
    );
  }
}

String messagePreview(BuildContext context, Message message) =>
    StickerProtocol.preview(
      message.body,
      message.portnum,
      context.l10n.stickerLabel,
    );
