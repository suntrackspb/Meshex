import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/link_badge.dart';
import '../../app/providers.dart';
import '../../data/appearance.dart';
import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../../ui/kit/kit.dart';
import 'chat_colors_preview.dart';
import 'color_palette.dart';

/// Цвета приложения и сообщений.
class AppColorsPage extends ConsumerWidget {
  const AppColorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider).value ?? accents.first;
    final infoAccent = ref.watch(messageInfoColorProvider).value;
    final incoming = ref.watch(incomingColorProvider).value;
    final mentionAv = ref.watch(mentionColorProvider);
    final mention = mentionAv.hasValue
        ? mentionAv.value
        : parseMentionColor(null);
    void save(String key, String value) => saveSetting(ref, key, value);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.appColors),
        actions: const [LinkBadge()],
      ),
      body: ListView(
        padding: pagePadding(context),
        children: [
          ChatColorsPreview(
            incoming: incoming,
            mention: mention,
            infoAccent: infoAccent,
          ),
          const SizedBox(height: Tokens.s16),
          SectionCard(
            title: context.l10n.appColors,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s16,
                  Tokens.s16,
                  Tokens.s16,
                  Tokens.s16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.accentColor_ff9b5d,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.s8),
                    ColorPalette(
                      selected: accent,
                      onSelected: (a) => save(AppSettingKeys.accent, a!.id),
                    ),
                    const SizedBox(height: Tokens.s16),
                    Text(
                      context.l10n.incomingMessageColor,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.s8),
                    ColorPalette(
                      selected: incoming,
                      defaultLabel: context.l10n.defaultMessageColor,
                      onSelected: (a) => save(
                        AppSettingKeys.incomingColor,
                        a?.id ?? 'default',
                      ),
                    ),
                    const SizedBox(height: Tokens.s16),
                    Text(
                      context.l10n.messageInfoColor,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.s8),
                    ColorPalette(
                      selected: infoAccent,
                      defaultLabel: context.l10n.defaultMessageColor,
                      onSelected: (a) => save(
                        AppSettingKeys.messageInfoColor,
                        a?.id ?? 'default',
                      ),
                    ),
                    const SizedBox(height: Tokens.s16),
                    Text(
                      context.l10n.mentionsAndReplies_209ee7,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      context.l10n.colorOfMessagesMentioningOrReplying_a39b9c,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Tokens.s8),
                    ColorPalette(
                      selected: mention,
                      defaultLabel: context.l10n.noHighlight_14736b,
                      onSelected: (a) => save(
                        AppSettingKeys.mentionColor,
                        a?.id ?? mentionOff,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
