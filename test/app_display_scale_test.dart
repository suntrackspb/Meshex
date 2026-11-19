import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/core/radio/journal.dart';
import 'package:meshex/core/radio/radio_session.dart';
import 'package:meshex/data/appearance.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/features/settings/app_settings_page.dart';
import 'package:meshex/l10n/l10n.dart';
import 'package:meshex/ui/app_display_scale.dart';
import 'package:meshex/ui/kit/kit.dart';

void main() {
  testWidgets('desktop zoom follows window metrics and scales hit targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3840, 2160);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final zoom = ValueNotifier(100);
    addTearDown(zoom.dispose);
    var presses = 0;
    late MediaQueryData media;
    late bool wide;
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: zoom,
        builder: (_, zoom, app) => AppDisplayScale(
          interfacePercent: zoom,
          textPercent: 125,
          child: app!,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                media = MediaQuery.of(context);
                wide = SplitView.isWide(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 100,
                    height: 40,
                    child: TextButton(
                      onPressed: () => presses++,
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(media.size, const Size(1920, 1080));
    expect(media.devicePixelRatio, 2);
    expect(media.textScaler.scale(16), closeTo(24, 0.001));

    zoom.value = 150;
    await tester.pump();
    expect(media.size, const Size(1280, 720));
    expect(media.devicePixelRatio, 3);
    expect(media.textScaler.scale(16), closeTo(24, 0.001));
    expect(wide, isTrue);
    await tester.tapAt(const Offset(140, 50));
    expect(presses, 1);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    await tester.pump();
    expect(media.size, const Size(1280, 720));
    expect(media.devicePixelRatio, 1.5);

    tester.view.physicalSize = const Size(1200, 900);
    await tester.pump();
    expect(media.size, const Size(800, 600));
    expect(wide, isFalse);
  });

  testWidgets('appearance choices update and save independently', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseProvider.overrideWithValue(db),
        radioProvider.overrideWith((_) => RadioSession(Journal())),
        mirrorRealtimeProvider.overrideWith((_) => null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.setSetting(AppSettingKeys.interfaceScale, '0');
      await db.setSetting(AppSettingKeys.textSize, '150');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, app) => AppDisplayScale(
            interfacePercent:
                ref.watch(interfaceScaleProvider).value ??
                defaultAppearanceScale,
            textPercent:
                ref.watch(textSizeProvider).value ?? defaultAppearanceScale,
            child: app!,
          ),
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AppSettingsPage(),
          ),
        ),
      ),
    );
    Future<void> waitForScale(StreamProvider<int> provider, int percent) async {
      for (
        var i = 0;
        i < 40 && container.read(provider).value != percent;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(container.read(provider).requireValue, percent);
    }

    await waitForScale(interfaceScaleProvider, 100);
    await waitForScale(textSizeProvider, 150);
    await tester.pumpAndSettle();
    final scale = find.text('Interface zoom');
    final text = find.text('Text size');
    expect(find.widgetWithText(ListTile, '100%'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '150%'), findsOneWidget);

    Future<void> choose(
      Finder setting,
      int percent,
      String key,
      StreamProvider<int> provider,
    ) async {
      await tester.tap(setting);
      await tester.pumpAndSettle();
      final choice = find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('$percent%'),
      );
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await waitForScale(provider, percent);
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => db.getSetting(key)), '$percent');
    }

    await choose(
      scale,
      200,
      AppSettingKeys.interfaceScale,
      interfaceScaleProvider,
    );
    expect(container.read(textSizeProvider).requireValue, 150);
    expect(MediaQuery.sizeOf(tester.element(scale)), const Size(400, 300));
    expect(
      tester
          .widget<SegmentedButton<AppTheme>>(
            find.byType(SegmentedButton<AppTheme>),
          )
          .direction,
      Axis.vertical,
    );

    await choose(text, 125, AppSettingKeys.textSize, textSizeProvider);
    expect(MediaQuery.textScalerOf(tester.element(text)).scale(16), 20);

    await choose(
      scale,
      100,
      AppSettingKeys.interfaceScale,
      interfaceScaleProvider,
    );
    expect(container.read(textSizeProvider).requireValue, 125);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
