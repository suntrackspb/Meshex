import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/mirror_ingest.dart';
import 'package:meshex/mirror/mirror_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  MirrorMessage mm(int id, String channel) => MirrorMessage(
    id: id,
    fromId: '!0000aaaa',
    packetId: id,
    text: 'msg $id',
    channel: channel,
    receivedAt: DateTime(2026, 10, 22),
  );

  Future<List<String>> bodies() async =>
      (await db.select(db.messages).get()).map((m) => m.body).toList()..sort();

  test(
    'скрытие: удаляет только сообщения из зеркала, не подтягивает снова',
    () async {
      await MirrorIngest(db).messages([mm(1, 'spam'), mm(2, 'MediumFast')]);
      // Услышанное в эфире в том же канале — остаётся.
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              packetId: 50,
              fromNum: 0xbbbb,
              toNum: broadcastNum,
              channelKey: const Value('spam'),
              body: 'radio',
              rxTime: DateTime(2026, 10, 22),
              heardOnRadio: const Value(true),
            ),
          );

      await db.hideChannel('spam');
      expect(await db.hiddenChannels(), {'spam'});
      expect(await bodies(), ['msg 2', 'radio']);

      await MirrorIngest(db).messages([mm(3, 'Spam')]);
      expect(await bodies(), ['msg 2', 'radio']);

      await db.unhideChannel('spam');
      await MirrorIngest(db).messages([mm(3, 'Spam')]);
      expect(await bodies(), ['msg 2', 'msg 3', 'radio']);
    },
  );

  for (final outgoing in [false, true]) {
    test(
      'скрытый канал дополняет ${outgoing ? "своё" : "радио"} сообщение шлюзами',
      () async {
        await db.hideChannel('mediumfast');
        await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                packetId: 77,
                fromNum: 0xaaaa,
                toNum: broadcastNum,
                channelKey: const Value('mediumfast'),
                body: 'msg 77',
                rxTime: DateTime(2026, 11, 14),
                heardOnRadio: Value(!outgoing),
                isOutgoing: Value(outgoing),
              ),
            );
        final mirror = MirrorIngest(db);
        await mirror.messages([
          MirrorMessage(
            id: 700,
            packetId: 77,
            fromId: '!0000aaaa',
            text: 'msg 77',
            channel: 'MediumFast',
            relays: const [MirrorRelay(nodeId: '!00000001')],
          ),
          mm(78, 'MediumFast'),
        ]);
        final row = (await db.select(db.messages).get()).single;
        expect(row.mirrorId, 700);
        expect(row.relayCount, 1);
        expect(row.heardOnMirror, isTrue);
        expect(row.isOutgoing, outgoing);
        expect(row.heardOnRadio, !outgoing);
        await mirror.relay(700, const MirrorRelay(nodeId: '!00000002'));
        expect((await db.select(db.messages).get()).single.relayCount, 2);
        expect(await db.hiddenChannels(), {'mediumfast'});
      },
    );
  }

  test('скрытые каналы независимы у двух нод с общей базой настроек', () async {
    final a = AppDatabase(NativeDatabase.memory(), db);
    final b = AppDatabase(NativeDatabase.memory(), db);
    addTearDown(a.close);
    addTearDown(b.close);
    await a.hideChannel('mediumfast');
    expect(await a.watchHiddenChannels().first, {'mediumfast'});
    expect(await b.watchHiddenChannels().first, isEmpty);
    expect(await db.hiddenChannels(), isEmpty);
    await b.hideChannel('longfast');
    await a.unhideChannel('mediumfast');
    expect(await a.watchHiddenChannels().first, isEmpty);
    expect(await b.watchHiddenChannels().first, {'longfast'});
    // Остальные настройки по-прежнему общие.
    await a.setSetting(AppSettingKeys.theme, 'dark');
    expect(await b.getSetting(AppSettingKeys.theme), 'dark');
  });

  test('старый общий список не наследуется базами нод', () async {
    await db.setSetting('chat.hiddenChannels', '["mediumfast"]');
    final node = AppDatabase(NativeDatabase.memory(), db);
    addTearDown(node.close);
    // Старые копии общей базы тоже могут содержать прежний ключ.
    await node
        .into(node.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'chat.hiddenChannels',
            value: '["longfast"]',
          ),
        );
    expect(await node.hiddenChannels(), isEmpty);
    expect(await node.watchHiddenChannels().first, isEmpty);
    await MirrorIngest(node).messages([mm(77, 'MediumFast')]);
    expect(
      (await node.select(node.messages).get()).single.heardOnMirror,
      isTrue,
    );
  });

  test('список ноды сохраняется при закрытии и повторном открытии', () async {
    final dir = Directory.systemTemp.createTempSync('hidden_channels');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/node.sqlite';
    final first = AppDatabase(NativeDatabase(File(path)), db);
    await first.hideChannel('mediumfast');
    await first.close();
    final reopened = AppDatabase(NativeDatabase(File(path)), db);
    try {
      expect(await reopened.watchHiddenChannels().first, {'mediumfast'});
      await reopened.unhideChannel('mediumfast');
      expect(await reopened.hiddenChannels(), isEmpty);
    } finally {
      await reopened.close();
    }
  });

  test(
    'обновление удаляет старый список, сохраняя новые списки и настройки',
    () async {
      final dir = Directory.systemTemp.createTempSync('legacy_hidden_channels');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/app.sqlite';
      final old = AppDatabase(NativeDatabase(File(path)));
      // Имитируем файл прежней версии: ключ записывается после открытия.
      await old.setSetting('chat.hiddenChannels', '["mediumfast"]');
      await old.setSetting(AppSettingKeys.theme, 'dark');
      await old.hideChannel('longfast');
      await old.close();

      final updated = AppDatabase(NativeDatabase(File(path)));
      try {
        expect(await updated.getSetting('chat.hiddenChannels'), isNull);
        expect(await updated.getSetting(AppSettingKeys.theme), 'dark');
        expect(await updated.hiddenChannels(), {'longfast'});
        await updated.hideChannel('services');
      } finally {
        await updated.close();
      }
      // Следующий запуск не сбрасывает сделанный после обновления выбор.
      final next = AppDatabase(NativeDatabase(File(path)));
      try {
        expect(await next.getSetting('chat.hiddenChannels'), isNull);
        expect(await next.hiddenChannels(), {'longfast', 'services'});
      } finally {
        await next.close();
      }
    },
  );

  test('битая настройка — пустой список', () {
    expect(parseHiddenChannels(null), isEmpty);
    expect(parseHiddenChannels('{oops'), isEmpty);
    expect(parseHiddenChannels('["a", 1]'), {'a'});
  });
}
