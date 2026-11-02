import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/link_badge.dart';
import '../../app/providers.dart';
import '../../data/appearance.dart';
import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../../ui/kit/kit.dart';

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
                    Wrap(
                      spacing: Tokens.s8,
                      runSpacing: Tokens.s8,
                      children: [
                        for (final a in accents)
                          _AccentDot(
                            accent: a,
                            selected: a.id == accent.id,
                            onTap: () => save(AppSettingKeys.accent, a.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s16),
                    Text(
                      context.l10n.incomingMessageColor,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.s8),
                    Wrap(
                      spacing: Tokens.s8,
                      runSpacing: Tokens.s8,
                      children: [
                        for (final a in accents)
                          _AccentDot(
                            accent: a,
                            selected: a.id == incoming?.id,
                            onTap: () =>
                                save(AppSettingKeys.incomingColor, a.id),
                          ),
                        _AccentDot(
                          label: context.l10n.defaultMessageColor,
                          selected: incoming == null,
                          onTap: () =>
                              save(AppSettingKeys.incomingColor, 'default'),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s16),
                    Text(
                      context.l10n.messageInfoColor,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: Tokens.s8),
                    Wrap(
                      spacing: Tokens.s8,
                      runSpacing: Tokens.s8,
                      children: [
                        for (final a in accents)
                          _AccentDot(
                            accent: a,
                            selected: a.id == infoAccent?.id,
                            onTap: () =>
                                save(AppSettingKeys.messageInfoColor, a.id),
                          ),
                        _AccentDot(
                          label: context.l10n.defaultMessageColor,
                          selected: infoAccent == null,
                          onTap: () =>
                              save(AppSettingKeys.messageInfoColor, 'default'),
                        ),
                      ],
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
                    Wrap(
                      spacing: Tokens.s8,
                      runSpacing: Tokens.s8,
                      children: [
                        for (final a in accents)
                          _AccentDot(
                            accent: a,
                            selected: a.id == mention?.id,
                            onTap: () =>
                                save(AppSettingKeys.mentionColor, a.id),
                          ),
                        _AccentDot(
                          selected: mention == null,
                          onTap: () =>
                              save(AppSettingKeys.mentionColor, mentionOff),
                        ),
                      ],
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

/// Кружок цвета; выбранный — с галочкой. Без [accent] — «без подсветки».
class _AccentDot extends StatelessWidget {
  const _AccentDot({
    this.accent,
    this.label,
    required this.selected,
    required this.onTap,
  });

  final String? label;

  final Accent? accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = accent;
    final scheme = Theme.of(context).colorScheme;
    final title =
        label ??
        (a == null ? null : context.builtIn(a.title)) ??
        context.l10n.noHighlight_14736b;
    return Tooltip(
      message: title,
      child: Semantics(
        button: true,
        selected: selected,
        label: title,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: a?.color,
              shape: BoxShape.circle,
              border: selected || a == null
                  ? Border.all(
                      color: selected ? scheme.onSurface : scheme.outline,
                      width: selected ? 2 : 1,
                    )
                  : null,
            ),
            child: a == null
                ? Icon(Icons.block, color: scheme.onSurfaceVariant, size: 20)
                : selected
                ? Icon(
                    Icons.check,
                    color:
                        ThemeData.estimateBrightnessForColor(a.color) ==
                            Brightness.light
                        ? const Color(0xFF191D24)
                        : Colors.white,
                    size: 20,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
