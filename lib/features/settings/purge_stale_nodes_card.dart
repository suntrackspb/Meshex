import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/toasts.dart';
import '../../data/database.dart';
import '../../l10n/l10n.dart';
import '../../ui/kit/kit.dart';

/// Editing the retention period must not enable destructive cleanup.
class PurgeStaleNodesCard extends ConsumerStatefulWidget {
  const PurgeStaleNodesCard({super.key});

  @override
  ConsumerState<PurgeStaleNodesCard> createState() =>
      _PurgeStaleNodesCardState();
}

class _PurgeStaleNodesCardState extends ConsumerState<PurgeStaleNodesCard> {
  int? _draftDays;
  int _lastDays = 7;
  bool _saving = false;

  Future<void> _apply(int days) async {
    final db = ref.read(databaseProvider);
    setState(() => _saving = true);
    try {
      await db.transaction(() async {
        await db.setSetting(AppSettingKeys.purgeStaleNodeDays, '$days');
        if (days > 0) await db.purgeStaleNodes();
      });
      if (mounted) setState(() => _draftDays = null);
    } catch (e) {
      toasts.error('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(purgeStaleNodeDaysProvider);
    final saved = setting.value ?? 0;
    final days = _draftDays ?? saved;
    final changed = _draftDays != null && days != saved;
    final editable = setting.hasValue && !_saving;
    return SectionCard(
      footer: context.l10n.favoriteAndIgnoredNodesAreAlways_f2c698,
      children: [
        SwitchListTile(
          title: Text(context.l10n.clearStaleNodes_968b4f),
          subtitle: changed ? Text(context.l10n.purgeStalePending) : null,
          value: days > 0,
          onChanged: !editable
              ? null
              : (on) => setState(() {
                  if (days > 0) _lastDays = days;
                  _draftDays = on ? _lastDays : 0;
                }),
        ),
        if (days > 0) ...[
          MeshTile(title: context.l10n.afterDays_00b005('$days')),
          Slider(
            value: days.clamp(1, 180).toDouble(),
            min: 1,
            max: 180,
            divisions: 179,
            label: '$days',
            onChanged: !editable
                ? null
                : (value) => setState(() {
                    _draftDays = value.round();
                    _lastDays = value.round();
                  }),
          ),
        ],
        if (changed)
          Padding(
            padding: const EdgeInsets.all(Tokens.s12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: !editable
                      ? null
                      : () => setState(() => _draftDays = null),
                  child: Text(context.l10n.cancel_0ec753),
                ),
                const SizedBox(width: Tokens.s8),
                FilledButton(
                  onPressed: !editable ? null : () => _apply(days),
                  child: Text(context.l10n.applyChanges),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
