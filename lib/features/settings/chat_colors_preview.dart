import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../data/appearance.dart';
import '../../l10n/l10n.dart';
import '../../ui/kit/kit.dart';
import '../../ui/theme.dart';

/// Static sample messages using the same color rules as the chat feed.
class ChatColorsPreview extends StatelessWidget {
  const ChatColorsPreview({
    super.key,
    required this.incoming,
    required this.mention,
    required this.infoAccent,
  });

  final Accent? incoming;
  final Accent? mention;
  final Accent? infoAccent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final incomingFill = incoming == null
        ? scheme.surfaceContainerHigh
        : mentionBubble(incoming!.color, theme.brightness);
    final mentionFill = mention == null
        ? incomingFill
        : mentionBubble(mention!.color, theme.brightness);
    final infoColor = infoAccent == null
        ? null
        : messageInfoTextColor(infoAccent!.color, theme.brightness);

    return Container(
      padding: const EdgeInsets.all(Tokens.s12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusL),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.chatColorsPreview,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.s8),
          _PreviewBubble(
            fill: incomingFill,
            body: context.l10n.colorPreviewIncoming,
            source: 'RX',
            infoColor: infoColor,
          ),
          const SizedBox(height: Tokens.s8),
          _PreviewBubble(
            fill: scheme.primaryContainer,
            body: context.l10n.colorPreviewOutgoing,
            source: 'TX',
            outgoing: true,
            infoColor: infoColor,
          ),
          const SizedBox(height: Tokens.s8),
          _PreviewBubble(
            fill: mentionFill,
            body: context.l10n.colorPreviewMention,
            source: 'NET',
            infoColor: infoColor,
          ),
        ],
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.fill,
    required this.body,
    required this.source,
    required this.infoColor,
    this.outgoing = false,
  });

  final Color fill;
  final String body;
  final String source;
  final Color? infoColor;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metadataColor = infoColor ?? scheme.outline;
    Widget label(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: metadataColor),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.labelSmall?.copyWith(color: metadataColor),
        ),
      ],
    );

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.s12,
            vertical: Tokens.s8,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(Tokens.radiusL),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!outgoing)
                Text(
                  'MESH',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              Text(body),
              const SizedBox(height: Tokens.s4),
              Wrap(
                spacing: Tokens.s8,
                runSpacing: Tokens.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  label(
                    source == 'NET'
                        ? CupertinoIcons.globe
                        : CupertinoIcons.dot_radiowaves_right,
                    source,
                  ),
                  if (source == 'RX') label(CupertinoIcons.arrow_branch, '2'),
                  if (!outgoing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: ShapeDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.08),
                        shape: const StadiumBorder(),
                      ),
                      child: label(
                        CupertinoIcons.antenna_radiowaves_left_right,
                        '3',
                      ),
                    ),
                  Text(
                    '12:34',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: infoColor,
                    ),
                  ),
                  if (outgoing)
                    Icon(Icons.done_all, size: 14, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
