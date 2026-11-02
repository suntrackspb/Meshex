import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/appearance.dart';
import 'package:meshex/features/settings/chat_colors_preview.dart';
import 'package:meshex/l10n/l10n.dart';
import 'package:meshex/ui/theme.dart';

void main() {
  for (final locale in ['ru', 'en']) {
    for (final mode in AppTheme.values.where((v) => v != AppTheme.system)) {
      testWidgets('preview fits narrow screen, large text: $locale $mode', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(320, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final brightness = mode == AppTheme.light
            ? Brightness.light
            : Brightness.dark;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(brightness, black: mode == AppTheme.black),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ChatColorsPreview(
                    incoming: parseAccent('orange'),
                    mention: parseMentionColor(null),
                    infoAccent: parseAccent('purple'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('RX'), findsOneWidget);
        expect(find.text('NET'), findsOneWidget);
        expect(find.text('TX'), findsOneWidget);
      });
    }
  }
}
