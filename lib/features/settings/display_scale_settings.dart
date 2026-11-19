import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/appearance.dart';
import '../../data/database.dart';
import '../../l10n/l10n.dart';

class DisplayScaleSettings extends ConsumerWidget {
  const DisplayScaleSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.l10n;
    final percent = NumberFormat.percentPattern(strings.localeName);

    Widget scaleTile({
      required String title,
      required IconData icon,
      required String key,
      required int value,
      required List<int> options,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(percent.format(value / defaultAppearanceScale)),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        final selected = await showDialog<int>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text(title),
            children: [
              for (final option in options)
                ListTile(
                  title: Text(percent.format(option / defaultAppearanceScale)),
                  selected: option == value,
                  trailing: option == value ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(dialogContext, option),
                ),
            ],
          ),
        );
        if (context.mounted && selected != null && selected != value) {
          await ref.read(appDatabaseProvider).setSetting(key, '$selected');
        }
      },
    );

    return Column(
      children: [
        scaleTile(
          title: strings.interfaceScale,
          icon: Icons.zoom_in,
          key: AppSettingKeys.interfaceScale,
          value:
              ref.watch(interfaceScaleProvider).value ?? defaultAppearanceScale,
          options: interfaceScaleOptions,
        ),
        scaleTile(
          title: strings.textSize,
          icon: Icons.format_size,
          key: AppSettingKeys.textSize,
          value: ref.watch(textSizeProvider).value ?? defaultAppearanceScale,
          options: textSizeOptions,
        ),
      ],
    );
  }
}
