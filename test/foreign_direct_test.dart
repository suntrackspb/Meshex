import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/providers.dart';
import 'package:meshex/core/proto/mesh.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/packet_router.dart';

void main() {
  test('чужая личка из зеркала не попадает в «Личные»', () async {
    final db = AppDatabase(NativeDatabase.memory());
    var id = 0;
    Future<void> msg(int from, int to) => db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: ++id,
            fromNum: from,
            toNum: to,
            body: 'm$id',
            rxTime: DateTime(2026, 1, 1, 0, id),
          ),
        );
    const me = 0x75ffff00;
    await msg(0x0407d2ec, 0x123ab8e8); // R-TKK4-F4FD: обе ноды чужие
    await msg(5, me);
    await msg(me, 6);

    // Своя нода ещё неизвестна — показываем всё.
    expect(await db.watchAllDirect().first, hasLength(3));

    await db.into(db.myNode).insert(MyNodeCompanion.insert(myNodeNum: me));
    final all = await db.watchAllDirect().first;
    expect(all.map((m) => m.body), ['m3', 'm2']);
    expect(await db.watchDirectMessages(0x0407d2ec).first, isEmpty);
    expect(await db.watchDirectUnread(0x0407d2ec, null).first, 0);
    expect(await db.watchDirectMessages(5).first, hasLength(1));
    await db.close();
  });

  test('личка с общей ноды попадает в диалог с получателем', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final router = PacketRouter(db);
    const me = 0x75feffff;
    const recipient = 5;
    const sender = 6;
    final time = DateTime(2026, 11, 17);
    final legacy = await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            packetId: 1,
            fromNum: me,
            toNum: recipient,
            body: 'earlier',
            rxTime: time,
          ),
        );

    final all = StreamIterator(db.watchAllDirect());
    addTearDown(all.cancel);
    expect(await all.moveNext(), isTrue);
    expect(all.current.single.isOutgoing, isFalse);
    final updated = all.moveNext();
    await router.handle(FromRadio(myInfo: MyNodeInfo(myNodeNum: me)));
    expect(await updated, isTrue);
    expect(all.current.single.isOutgoing, isTrue);
    await all.cancel();

    Future<void> receive(int id, int from, int to, String text) =>
        router.handle(
          FromRadio(
            packet: MeshPacket(
              id: id,
              from: from,
              to: to,
              rxTime: time.millisecondsSinceEpoch ~/ 1000 + id,
              decoded: Data(
                portnum: PortNum.TEXT_MESSAGE_APP,
                payload: utf8.encode(text),
              ),
            ),
          ),
        );

    await receive(2, me, recipient, 'sent on another client');
    await receive(3, sender, me, 'received from another node');
    await receive(4, recipient, me, 'reply');

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(conversationsProvider, (_, _) {});
    addTearDown(subscription.close);
    final conversations = await container.read(conversationsProvider.future);
    expect(conversations.map((d) => d.peer), [recipient, sender]);

    final chat = await db.watchDirectMessages(recipient).first;
    expect(chat.map((m) => m.packetId), [4, 2, 1]);
    expect(chat.map((m) => m.isOutgoing), [false, true, true]);
    expect(chat[1].ackState, AckState.none);
    final stored = await (db.select(
      db.messages,
    )..where((m) => m.id.equals(legacy))).getSingle();
    expect(stored.isOutgoing, isFalse);
    expect(await db.watchDirectUnread(recipient, null).first, 1);
    expect(await db.watchDirectUnread(me, null).first, 0);

    expect(await db.watchDirectMessages(me).first, isEmpty);
    expect(await db.feedForSearch(peer: me), isEmpty);
    expect(await db.feedCountSince(time, peer: me), 0);
    expect(await db.deleteDirectChat(me), 0);
    final results = await db.feedForSearch(peer: recipient);
    expect(results.map((m) => m.packetId), [4, 2, 1]);
    expect(results[1].isOutgoing, isTrue);
    expect(await db.feedCountSince(time, peer: recipient), 3);
    expect(await db.deleteDirectChat(recipient), 3);
    expect((await db.watchDirectMessages(sender).first).single.packetId, 3);
  });
}
