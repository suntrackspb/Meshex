import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../examples/bridges/telegram/dart/bot.dart';
import '../examples/bridges/telegram/dart/protocol.dart';

void main() {
  test(
    'Telegram pairs with a confirmation and authorizes both sender and chat',
    () async {
      final batches = StreamController<List<BridgeJson>>();
      final updates = StreamIterator(batches.stream);
      final posts = <BridgeJson>[];
      final mediaCalls = <String>[];
      Future<Object?> requestApi(
        String method,
        BridgeJson params,
        Duration timeout,
      ) async {
        return switch (method) {
          'getMe' => {'username': 'test_bot'},
          'getWebhookInfo' => {'url': ''},
          'getUpdates' => await updates.moveNext() ? updates.current : [],
          'sendMessage' || 'sendSticker' => () {
            if (method == 'sendSticker') mediaCalls.add(method);
            posts.add(params);
            return {'message_id': posts.length};
          }(),
          _ => throw StateError('Unexpected Telegram method'),
        };
      }

      final paired = Completer<void>();
      final sent = <BridgeJson>[];
      final module = TelegramBot(
        '123456:long_example_token_for_testing',
        owner: null,
        onPairingChanged: () {
          if (!paired.isCompleted) paired.complete();
        },
        requestApi: requestApi,
      );
      addTearDown(() async {
        module.close();
        await batches.close();
        await updates.cancel();
      });
      await module.open((method, params) async {
        if (method == 'mesh.getStickerMedia') {
          expect(params, {'replyRef': 'sticker-1', 'offset': 0});
          return {'size': 3, 'animated': false, 'dataBase64': 'AAEC'};
        }
        expect(method, 'mesh.sendMessage');
        sent.add(params);
        return {'status': 'queued', 'packetId': 7};
      }, () => fail('Unexpected disconnect'));

      BridgeJson update(
        int id,
        int sender,
        int chat,
        String text, {
        int? reply,
      }) => {
        'update_id': id,
        'message': {
          'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'chat': {'type': 'private', 'id': chat},
          'from': {'id': sender},
          'text': text,
          if (reply != null) 'reply_to_message': {'message_id': reply},
        },
      };

      final code = module.pairingUrl!.queryParameters['start'];
      batches.add([
        update(1, 99, 99, '/start'),
        update(2, 42, 42, '/start $code'),
      ]);
      await paired.future;
      await pumpEventQueue();
      expect(module.owner, isNull);
      expect(module.candidate, (user: 42, chat: 42));
      expect(posts.single['chat_id'], 42);
      module.pair(module.candidate!);

      await module.publish('mesh.messageReceived', {
        'nodeId': '!11223344',
        'replyRef': 'original',
        'target': {'kind': 'channel', 'name': 'Local'},
        'author': {'name': 'Mesh user', 'id': '!55667788'},
        'text': 'mesh text',
      });
      batches.add([
        update(3, 99, 42, 'wrong sender', reply: 2),
        update(4, 42, 99, 'wrong chat', reply: 2),
        update(5, 42, 42, '/mention OK', reply: 2),
      ]);
      await pumpEventQueue();
      expect(posts.map((post) => post['chat_id']), everyElement(42));
      expect(sent.single, {
        'commandId': 'telegram:5',
        'nodeId': '!11223344',
        'replyRef': 'original',
        'text': 'OK',
        'mentionAuthor': true,
      });

      const context = {
        'nodeId': '!11223344',
        'target': {'kind': 'channel', 'name': 'Local'},
        'author': {'name': 'Mesh user', 'id': '!55667788'},
      };
      await module.publish('mesh.reactionReceived', {
        ...context,
        'originalRef': 'original',
        'emoji': '👍',
      });
      expect(posts.last['text'], contains('Reaction 👍'));
      expect(posts.last['reply_parameters'], containsPair('message_id', 2));
      await module.publish('mesh.stickerReceived', {
        ...context,
        'replyRef': 'sticker-1',
        'sticker': {'pack_sha256': 'a' * 64, 'sticker_id': 'blue'},
      });
      expect(mediaCalls, ['sendSticker']);
      expect(posts.last['reply_parameters'], containsPair('message_id', 5));
      batches.add([update(6, 42, 42, '/react 🫶', reply: 6)]);
      await pumpEventQueue();
      expect(sent.last, {
        'commandId': 'telegram:6',
        'nodeId': '!11223344',
        'replyRef': 'sticker-1',
        'text': '🫶',
        'reaction': true,
      });
    },
  );
  test('standalone stdio exchanges the public API with Meshex', () async {
    final input = StreamController<List<int>>();
    final writes = <BridgeJson>[];
    final called = Completer<BridgeJson>();
    void send(BridgeJson message) =>
        input.add(utf8.encode('${jsonEncode(message)}\n'));
    final rpc = StdioRpc(input.stream, (frame) async {
      writes.add(frame);
      if (frame['method'] == 'mesh.sendMessage') {
        send({
          'jsonrpc': '2.0',
          'id': frame['id'],
          'result': {'status': 'queued', 'packetId': 7},
        });
      }
    });
    final listen = rpc.listen(
      onInitialize: () async {},
      onEvent: (method, params) async {
        expect(method, 'mesh.messageReceived');
        final result = await rpc.request('mesh.sendMessage', {
          'commandId': 'one',
          'nodeId': params['nodeId'],
          'replyRef': params['replyRef'],
          'text': 'reply',
        });
        called.complete(result);
      },
      onEventError: (error) => fail(error.toString()),
    );
    send({
      'jsonrpc': '2.0',
      'method': 'bridge.initialize',
      'id': 'init',
      'params': {'apiVersion': 1},
    });
    send({
      'jsonrpc': '2.0',
      'method': 'mesh.messageReceived',
      'params': {'nodeId': '!a1b2c3d4', 'replyRef': 'reply-target'},
    });
    expect(await called.future, {'status': 'queued', 'packetId': 7});
    expect(writes.first, {
      'jsonrpc': '2.0',
      'id': 'init',
      'result': {'apiVersion': 1},
    });
    expect(writes.last['params'], containsPair('replyRef', 'reply-target'));
    await input.close();
    await listen;
  });
}
