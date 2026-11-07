import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:meshex/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';

/// Снимки схем — drift_schemas/; новая версия: `dart run drift_dev schema
/// dump lib/data/database.dart drift_schemas/drift_schema_vN.json`, затем
/// `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]) {
    test('миграция $from → 19 даёт текущую схему', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 19);
      await db.close();
    });
  }

  test('15 → 19 сохраняет текстовую историю с портом 1', () async {
    final schema = await verifier.schemaAt(15);
    schema.rawDatabase.execute(
      "INSERT INTO messages (packet_id, from_num, to_num, body, rx_time) "
      "VALUES (7, 42, 4294967295, 'история', '2023-11-14T22:13:20.000Z')",
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 19);
    final old = await db.select(db.messages).getSingle();
    expect(old.body, 'история');
    expect(old.portnum, 1);
    await db.close();
  });

  test('16 → 19 сохраняет историю, ACK и настройки без sticker content', () async {
    final schema = await verifier.schemaAt(16);
    schema.rawDatabase.execute(
      "INSERT INTO messages (packet_id, from_num, to_num, body, rx_time, ack_state, ack_proof) "
      "VALUES (77, 42, 4294967295, 'история v16', '2023-11-14T22:13:20.000Z', 2, 1)",
    );
    schema.rawDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('app.theme', 'dark')",
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 19);
    final old = await db.select(db.messages).getSingle();
    expect(old.body, 'история v16');
    expect(old.portnum, 1);
    expect(old.rawPayload, isNull);
    expect(old.stickerContent, isNull);
    expect(old.ackState, AckState.acked);
    expect(old.ackProof, 1);
    expect(await db.getSetting(AppSettingKeys.theme), 'dark');
    await db.close();
  });

  test('17 → 19 сохраняет sticker bytes и structured content', () async {
    final schema = await verifier.schemaAt(17);
    final fixture =
        jsonDecode(File('test/fixtures/stickers/wire.json').readAsStringSync())
            as Map;
    final content = jsonEncode({
      'wire_version': 2,
      'source_url': fixture['source_url'],
      'pack_sha256': fixture['pack_sha256'],
      'sticker_id': fixture['sticker_id'],
    });
    final hex = fixture['payload_hex'] as String;
    schema.rawDatabase.execute(
      "INSERT INTO messages (packet_id, from_num, to_num, body, rx_time, portnum, raw_payload, sticker_content) "
      "VALUES (78, 42, 4294967295, '[Sticker]', '2023-11-14T22:13:20.000Z', 256, X'$hex', ?)",
      [content],
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 19);
    final old = await db.select(db.messages).getSingle();
    expect(old.portnum, 256);
    expect(old.stickerContent, content);
    expect(
      old.rawPayload!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      hex,
    );
    expect(await db.select(db.stickerSources).get(), isEmpty);
    expect(await db.select(db.stickerSourceBindings).get(), isEmpty);
    await db.close();
  });

  test('18 → 19 сохраняет реестр и удаляет только настройку прототипа', () async {
    final schema = await verifier.schemaAt(18);
    schema.rawDatabase.execute(
      "INSERT INTO sticker_sources (source_url, manual_enabled, blocked) VALUES ('https://s.example/source.json', 1, 1)",
    );
    schema.rawDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('stickers.catalogUrl', 'https://old.example/catalog.json')",
    );
    schema.rawDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('app.theme', 'dark')",
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 19);
    final source = await db.select(db.stickerSources).getSingle();
    expect(source.manualEnabled, isTrue);
    expect(source.blocked, isTrue);
    expect(await db.getSetting('stickers.catalogUrl'), isNull);
    expect(await db.getSetting('app.theme'), 'dark');
    expect(await db.select(db.stickerInstalls).get(), isEmpty);
    await db.close();
  });

  test('данные переживают миграцию 5 → текущая', () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('app.theme', 'dark')",
    );
    schema.rawDatabase.execute('INSERT INTO my_node (my_node_num) VALUES (42)');
    final db = AppDatabase(schema.newConnection());
    expect(await db.getSetting(AppSettingKeys.theme), 'dark');
    expect((await db.select(db.myNode).getSingle()).myNodeNum, 42);
    await db.close();
  });

  test(
    'обрыв посреди шага — откат целиком, повторный запуск проходит',
    () async {
      final schema = await verifier.schemaAt(7);
      final broken = _BrokenStep(schema.newConnection());
      await expectLater(
        broken.getSetting(AppSettingKeys.theme),
        throwsA(isA<StateError>()),
      );
      await broken.close();

      expect(schema.rawDatabase.userVersion, 7);
      final cols = schema.rawDatabase
          .select('PRAGMA table_info(nodes)')
          .map((r) => r['name'])
          .toList();
      expect(cols, isNot(contains('rssi')));

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 19);
      await db.close();
    },
  );

  test('колонка уже есть при старой версии — миграция проходит', () async {
    // iPhone 7, 0.1.12: macaddr есть, а user_version = 13.
    final schema = await verifier.schemaAt(13);
    schema.rawDatabase.execute(
      'ALTER TABLE nodes ADD COLUMN "macaddr" BLOB NULL',
    );
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 19);
    await db.close();
  });

  test('база новее сборки — не стирается', () async {
    final schema = await verifier.schemaAt(8);
    schema.rawDatabase.execute(
      "INSERT INTO app_settings (key, value) VALUES ('app.theme', 'dark')",
    );
    schema.rawDatabase.userVersion = 99;
    final db = AppDatabase(schema.newConnection());
    expect(await db.getSetting(AppSettingKeys.theme), 'dark');
    await db.close();
  });
}

/// Шаг к 8-й падает после первой колонки — как убитый посреди миграции
/// процесс.
class _BrokenStep extends AppDatabase {
  _BrokenStep(super.executor);

  @override
  Map<int, Future<void> Function(Migrator m)> get upgradeSteps => {
    ...super.upgradeSteps,
    8: (m) async {
      await m.addColumn(nodes, nodes.rssi);
      throw StateError('обрыв');
    },
  };
}
