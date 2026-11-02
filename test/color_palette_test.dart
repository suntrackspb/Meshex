import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/appearance.dart';
import 'package:meshex/features/settings/color_palette.dart';
import 'package:meshex/l10n/l10n.dart';

void main() {
  for (final width in [320.0, 393.0, 430.0]) {
    for (final reset in [false, true]) {
      testWidgets('palette stays on one row: width $width, reset $reset', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Accent? selection = accents.first;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ColorPalette(
                  selected: selection,
                  defaultLabel: reset ? 'Default' : null,
                  onSelected: (a) => selection = a,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final buttons = find.descendant(
          of: find.byType(ColorPalette),
          matching: find.byType(InkWell),
        );
        expect(buttons, findsNWidgets(accents.length + (reset ? 1 : 0)));
        final centers = [
          for (var i = 0; i < buttons.evaluate().length; i++)
            tester.getCenter(buttons.at(i)),
        ];
        expect(centers.map((p) => p.dy).toSet(), hasLength(1));
        expect(
          tester.getRect(buttons.last).right,
          lessThanOrEqualTo(width - 32 + 0.001),
        );
        await tester.tap(buttons.at(accents.length - 1));
        expect(selection?.id, 'orange');
        if (reset) {
          await tester.tap(buttons.last);
          expect(selection, isNull);
        }
      });
    }
  }
}
