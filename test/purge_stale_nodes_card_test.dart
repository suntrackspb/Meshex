import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/features/settings/purge_stale_nodes_card.dart';
import 'package:meshex/l10n/l10n.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> mount(WidgetTester tester, {int saved = 0}) async {
    await db.setSetting(AppSettingKeys.purgeStaleNodeDays, '$saved');
    for (final (num, days) in [(1, 10), (2, 40)]) {
      await db
          .into(db.nodes)
          .insert(
            NodesCompanion.insert(
              num: Value(num),
              lastHeard: Value(DateTime.now().subtract(Duration(days: days))),
              onMirror: const Value(true),
            ),
          );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: PurgeStaleNodesCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<List<int>> nodes() async =>
      (await db.select(db.nodes).get()).map((n) => n.num).toList()..sort();

  Future<void> choose(WidgetTester tester, int days) async {
    tester.widget<Slider>(find.byType(Slider)).onChanged!(days.toDouble());
    await tester.pumpAndSettle();
  }

  testWidgets('enable and adjust are drafts; Apply uses chosen 30 days', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '0');
    expect(
      await db.purgeStaleNodes(),
      0,
    ); // background cleanup remains disabled
    expect(await nodes(), [1, 2]);
    await choose(tester, 30);
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '0');
    expect(await nodes(), [1, 2]);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '30');
    expect(await nodes(), [1]);
    expect(find.text('Apply'), findsNothing);
    await unmount(tester);
  });

  testWidgets('Cancel discards activation without deleting nodes', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await choose(tester, 30);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.byType(Slider), findsNothing);
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '0');
    expect(await nodes(), [1, 2]);
    await unmount(tester);
  });

  testWidgets('existing period changes and disabling also wait for Apply', (
    tester,
  ) async {
    await mount(tester, saved: 60);
    await choose(tester, 7);
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '60');
    expect(await nodes(), [1, 2]);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 60);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(await db.getSetting(AppSettingKeys.purgeStaleNodeDays), '0');
    expect(await nodes(), [1, 2]);
    await unmount(tester);
  });
}
