import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshex/mirror/mirror_api.dart';
import 'package:meshex/mirror/mirror_models.dart';
import 'package:meshex/mirror/mirror_realtime.dart';

/// Локальный WS-сервер: принимает подключение и сразу закрывает с [code].
Future<(HttpServer, Uri, int Function())> _server(int code) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var connects = 0;
  server.listen((req) async {
    connects++;
    final ws = await WebSocketTransformer.upgrade(req);
    await ws.close(code, 'client_outdated');
  });
  return (
    server,
    Uri.parse('ws://127.0.0.1:${server.port}/ws'),
    () => connects,
  );
}

void main() {
  test('4426 — устарело: без переподключений, onOutdated один раз', () async {
    final (server, url, connects) = await _server(wsCloseOutdated);
    final outdated = Completer<void>();
    var calls = 0;
    final rt = MirrorRealtime(
      url,
      (_) async {},
      onOutdated: () {
        calls++;
        if (!outdated.isCompleted) outdated.complete();
      },
    )..start();
    await outdated.future.timeout(const Duration(seconds: 5));
    expect(rt.state, MirrorState.outdated);
    // Обычный повтор был бы через 1 с — ждём дольше.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(connects(), 1);
    expect(calls, 1);
    await rt.stop();
    await server.close(force: true);
  });

  test('другой код закрытия — обычный повтор', () async {
    final (server, url, connects) = await _server(WebSocketStatus.goingAway);
    var calls = 0;
    final rt = MirrorRealtime(url, (_) async {}, onOutdated: () => calls++)
      ..start();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    expect(connects(), greaterThanOrEqualTo(2));
    expect(calls, 0);
    await rt.stop();
    await server.close(force: true);
  });

  test(
    '3 неудачи WS → переключение на SSE → фоновый возврат на WS',
    () async {
      var wsAllowed = false;
      var wsConnects = 0;
      var sseConnects = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        if (req.uri.path == '/ws') {
          wsConnects++;
          if (!wsAllowed) {
            req.response.statusCode = HttpStatus.badGateway;
            await req.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(req);
          ws.add(
            jsonEncode({
              'type': 'new_message',
              'message': {'id': 2, 'from_id': '!0000abcd', 'text': 'from-ws'},
            }),
          );
        } else if (req.uri.path == '/sse') {
          sseConnects++;
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('text', 'event-stream');
          req.response.bufferOutput = false;
          req.response.write(': keepalive\n\n');
          req.response.write(
            'data: ${jsonEncode({
              'type': 'init',
              'messages': [
                {'id': 1, 'from_id': '!0000abcd', 'text': 'from-sse'},
              ],
            })}\n\n',
          );
          await req.response.flush();
          // Держим поток открытым, пока клиент сам не закроет при переходе на WS.
          await req.response.done.catchError((_) {});
        }
      });

      final sseEvent = Completer<MirrorInit>();
      final wsEvent = Completer<MirrorNewMessage>();
      final transports = <MirrorTransport>[];

      final rt = MirrorRealtime(
        Uri.parse('ws://127.0.0.1:${server.port}/ws'),
        (e) async {
          if (e is MirrorInit && !sseEvent.isCompleted) {
            sseEvent.complete(e);
          } else if (e is MirrorNewMessage && !wsEvent.isCompleted) {
            wsEvent.complete(e);
          }
        },
        sseUrl: Uri.parse('http://127.0.0.1:${server.port}/sse'),
        onTransportChanged: transports.add,
        retryDelays: const [Duration(milliseconds: 20)],
        wsProbeInterval: const Duration(milliseconds: 60),
      )..start();
      addTearDown(rt.stop);

      final init = await sseEvent.future.timeout(const Duration(seconds: 5));
      expect(init.messages.single.text, 'from-sse');
      expect(wsConnects, 3);
      expect(sseConnects, 1);
      expect(rt.transport, MirrorTransport.sse);
      expect(transports, [MirrorTransport.sse]);

      // Включаем WS: фоновая проверка должна переключить обратно с SSE на WS.
      wsAllowed = true;
      final live = await wsEvent.future.timeout(const Duration(seconds: 5));
      expect(live.message.text, 'from-ws');
      expect(rt.transport, MirrorTransport.ws);
      expect(transports, [MirrorTransport.sse, MirrorTransport.ws]);
    },
  );

  test('чередование 3 WS → 3 SSE → 3 WS при недоступности обоих', () async {
    final attempts = <String>[];
    final done = Completer<void>();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    server.listen((req) async {
      attempts.add(req.uri.path);
      req.response.statusCode = HttpStatus.badGateway;
      await req.response.close();
      if (attempts.length >= 7 && !done.isCompleted) {
        done.complete();
      }
    });

    final rt = MirrorRealtime(
      Uri.parse('ws://127.0.0.1:${server.port}/ws'),
      (_) async {},
      sseUrl: Uri.parse('http://127.0.0.1:${server.port}/sse'),
      retryDelays: const [Duration(milliseconds: 15)],
    )..start();
    addTearDown(rt.stop);

    await done.future.timeout(const Duration(seconds: 5));
    expect(attempts.take(7).toList(), [
      '/ws',
      '/ws',
      '/ws',
      '/sse',
      '/sse',
      '/sse',
      '/ws',
    ]);
  });

  test('MirrorApi переключает базовый домен на резервный при сбое связи', () async {
    final hits = <String>[];
    final api = MirrorApi(
      Uri.parse('https://main.example.org'),
      fallbackBaseUrl: Uri.parse('https://sse.example.org'),
      client: MockClient((req) async {
        hits.add(req.url.host);
        if (req.url.host == 'main.example.org') {
          throw const SocketException('blocked');
        }
        return http.Response(jsonEncode({'nodes': []}), 200);
      }),
    );
    addTearDown(api.close);

    expect(await api.nodes(), isEmpty);
    expect(api.preferFallback, isTrue);
    expect(hits, ['main.example.org', 'sse.example.org']);

    // Следующий запрос идёт сразу на резервный домен без ожидания основного.
    hits.clear();
    expect(await api.nodes(), isEmpty);
    expect(hits, ['sse.example.org']);
  });
}
