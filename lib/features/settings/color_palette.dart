import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/appearance.dart';
import '../../l10n/l10n.dart';

/// Fits the full palette, including reset, on one row.
class ColorPalette extends StatelessWidget {
  const ColorPalette({
    super.key,
    required this.selected,
    required this.onSelected,
    this.defaultLabel,
  });

  final Accent? selected;
  final ValueChanged<Accent?> onSelected;
  final String? defaultLabel;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 396),
    child: Row(
      children: [
        for (final a in accents)
          Expanded(
            child: _ColorDot(
              accent: a,
              label: context.builtIn(a.title),
              selected: selected?.id == a.id,
              onTap: () => onSelected(a),
            ),
          ),
        if (defaultLabel != null)
          Expanded(
            child: _ColorDot(
              label: defaultLabel!,
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
          ),
      ],
    ),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    this.accent,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Accent? accent;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent?.color;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(
                  28.0,
                  math.max(0.0, constraints.maxWidth - 4),
                );
                return Center(
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: selected || color == null
                          ? Border.all(
                              color: selected
                                  ? scheme.onSurface
                                  : scheme.outline,
                              width: selected ? 2 : 1,
                            )
                          : null,
                    ),
                    child: color == null
                        ? Icon(
                            Icons.block,
                            color: scheme.onSurfaceVariant,
                            size: size * 0.57,
                          )
                        : selected
                        ? Icon(
                            Icons.check,
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                    Brightness.light
                                ? const Color(0xFF191D24)
                                : Colors.white,
                            size: size * 0.57,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
