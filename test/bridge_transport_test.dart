import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/bridges/bridge_config.dart';
import 'package:meshex/bridges/bridge_protocol.dart';
import 'package:meshex/bridges/external_bridge.dart';

void main() {
  test('HTTP endpoints are literal loopback URLs only', () {
    expect(bridgeHttpEndpoint('http://127.0.0.1:8765')?.path, '/rpc');
    expect(bridgeHttpEndpoint('http://[::1]:8765')?.path, '/rpc');
    for (final value in [
      'http://localhost:8765',
      'http://192.168.1.1:8765',
      'http://127.0.0.1:8765/elsewhere',
      'http://user@127.0.0.1:8765',
      'http://127.0.0.1:8765/?url=other',
      'http://127.0.0.1:8765/#fragment',
    ]) {
      expect(bridgeHttpEndpoint(value), isNull, reason: value);
    }
  });

  test(
    'HTTP sends events and receives command responses with a bearer token',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final event = Completer<BridgeJson>();
      final response = Completer<BridgeJson>();
      var requested = false;
      server.listen((request) async {
        expect(request.uri.path, '/rpc');
        expect(request.headers.value('authorization'), 'Bearer test-token');
        final res = request.response;
        res.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          if (requested) {
            res.statusCode = HttpStatus.noContent;
          } else {
            requested = true;
            res.write(
              jsonEncode(bridgeCall('mesh.listTargets', {}, id: 'request')),
            );
          }
        } else {
          final body = bridgeObject(
            jsonDecode(await utf8.decoder.bind(request).join()),
          );
          if (body['method'] == 'bridge.initialize') {
            res.write(
              jsonEncode(bridgeResult(body['id'] as String, {'apiVersion': 1})),
            );
          } else {
            if (body['method'] == 'mesh.messageReceived') {
              event.complete(body);
            } else {
              response.complete(body);
            }
            res.statusCode = HttpStatus.noContent;
          }
        }
        await res.close();
      });
      final link = HttpBridge(
        bridgeHttpEndpoint('http://127.0.0.1:${server.port}')!,
        'test-token',
      );
      addTearDown(() async {
        link.close();
        await server.close(force: true);
      });
      await link.open((method, params) async {
        expect(method, 'mesh.listTargets');
        return {'nodeId': '!11223344', 'targets': <Object>[]};
      }, () => fail('Unexpected disconnection'));
      await link.publish('mesh.messageReceived', {'text': 'hello'});
      expect((await event.future)['params'], {'text': 'hello'});
      final result = await response.future;
      expect(result['id'], 'request');
      expect(result['result'], containsPair('nodeId', '!11223344'));
    },
  );

  test(
    'stdio keeps executable arguments intact and exchanges JSON frames',
    () async {
      final link = ProcessBridge('/bin/sh', [
        '-c',
        r'''
        read -r init
        printf '%s\n' '{"jsonrpc":"2.0","id":"meshex-initialize","result":{"apiVersion":1}}'
        read -r event
        test "$1" = "spaces stay together" || exit 1
        printf '%s\n' '{"jsonrpc":"2.0","id":"r1","method":"mesh.listTargets","params":{}}'
        read -r result
        test "$result" = '{"jsonrpc":"2.0","id":"r1","result":{"targets":[]}}'
      ''',
        'bridge-test',
        'spaces stay together',
      ]);
      addTearDown(link.close);
      final called = Completer<String>();
      final disconnected = Completer<void>();
      await link.open((method, params) async {
        called.complete(method);
        return {'targets': []};
      }, disconnected.complete);
      await link.publish('mesh.messageReceived', {'text': 'test'});
      expect(await called.future, 'mesh.listTargets');
      await disconnected.future;
    },
    skip: Platform.isWindows,
  );
}
