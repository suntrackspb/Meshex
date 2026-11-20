import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef BridgeJson = Map<String, dynamic>;
typedef BridgeRequest =
    Future<BridgeJson> Function(String method, BridgeJson params);

class BridgeError implements Exception {
  const BridgeError(this.code, this.message);
  final int code;
  final String message;

  @override
  String toString() => message;
}

BridgeJson bridgeObject(Object? value) {
  if (value is BridgeJson) return value;
  throw const FormatException('Expected a JSON object');
}

const _frameLimit = 256 * 1024;

/// Adapter side of Meshex Bridge API v1 over standard input and output.
class StdioRpc {
  StdioRpc(this.input, this.write);

  final Stream<List<int>> input;
  final Future<void> Function(BridgeJson) write;
  final _requests = <String, Completer<BridgeJson>>{};
  bool _initialized = false;
  int _nextId = 0;
  Future<void> _events = Future.value();
  int _pendingEvents = 0;
  bool _closed = false;

  Future<void> listen({
    required Future<void> Function() onInitialize,
    required Future<void> Function(String, BridgeJson) onEvent,
    required void Function(Object) onEventError,
  }) async {
    try {
      await for (final frame in _readFrames()) {
        if (frame['jsonrpc'] != '2.0') {
          throw const FormatException('Expected JSON-RPC 2.0');
        }
        final id = frame['id'];
        final method = frame['method'];
        if (!_initialized) {
          if (method != 'bridge.initialize' || id is! String) {
            throw const FormatException('Expected bridge.initialize');
          }
          final params = bridgeObject(frame['params']);
          if (params['apiVersion'] != 1) {
            await write({
              'jsonrpc': '2.0',
              'id': id,
              'error': {'code': -32000, 'message': 'Bridge API v1 required'},
            });
            return;
          }
          _initialized = true;
          await write({
            'jsonrpc': '2.0',
            'id': id,
            'result': {'apiVersion': 1},
          });
          await onInitialize();
        } else if (method is String && id == null) {
          if (_pendingEvents >= 128) continue;
          final params = bridgeObject(frame['params']);
          _pendingEvents++;
          _events = _events.then((_) async {
            try {
              if (!_closed) await onEvent(method, params);
            } catch (error) {
              onEventError(error);
            } finally {
              _pendingEvents--;
            }
          });
        } else if (method == null && id is String) {
          final pending = _requests.remove(id);
          if (pending == null) continue;
          final error = frame['error'];
          if (error is BridgeJson) {
            pending.completeError(
              BridgeError(
                error['code'] as int? ?? -32603,
                error['message'] as String? ?? 'Meshex command failed',
              ),
            );
          } else {
            try {
              pending.complete(bridgeObject(frame['result']));
            } on FormatException {
              pending.completeError(
                const BridgeError(-32603, 'Invalid Meshex result'),
              );
            }
          }
        }
      }
    } finally {
      _closed = true;
      for (final pending in _requests.values) {
        pending.completeError(
          const BridgeError(-32000, 'Meshex closed the connection'),
        );
      }
      _requests.clear();
    }
  }

  Future<BridgeJson> request(String method, BridgeJson params) async {
    if (!_initialized || _closed) {
      throw const BridgeError(-32000, 'Meshex is unavailable');
    }
    final id = 'telegram-${++_nextId}';
    final pending = Completer<BridgeJson>();
    _requests[id] = pending;
    try {
      await write({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });
      return await pending.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw const BridgeError(-32000, 'Meshex did not respond'),
      );
    } finally {
      _requests.remove(id);
    }
  }

  Stream<BridgeJson> _readFrames() async* {
    final bytes = <int>[];
    await for (final chunk in input) {
      for (final byte in chunk) {
        if (byte == 10) {
          yield bridgeObject(jsonDecode(utf8.decode(bytes)));
          bytes.clear();
        } else {
          if (bytes.length == _frameLimit) {
            throw const FormatException('Meshex frame is too large');
          }
          bytes.add(byte);
        }
      }
    }
  }
}

Future<void> writeStdioFrame(BridgeJson frame) async {
  stdout.add(utf8.encode('${jsonEncode(frame)}\n'));
  await stdout.flush();
}
