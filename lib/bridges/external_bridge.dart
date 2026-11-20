import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'bridge_protocol.dart';

const _initializeId = 'meshex-initialize';
const _handshakeTimeout = Duration(seconds: 8);

class ProcessBridge implements BridgeLink {
  ProcessBridge(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
  Process? _process;
  bool _closed = false;
  final _handshake = Completer<void>();

  @override
  Future<void> open(BridgeRequest request, void Function() onDisconnect) async {
    final path = executable.toLowerCase();
    if (!File(executable).isAbsolute ||
        (Platform.isWindows && !path.endsWith('.exe'))) {
      throw const BridgeError(-32000, 'Choose an absolute executable path');
    }
    final process = await Process.start(executable, arguments);
    if (_closed) {
      process.kill();
      return;
    }
    _process = process;
    process.stderr.listen((_) {});
    final initialized = _handshake.future.timeout(_handshakeTimeout);
    unawaited(
      process.stdin.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (_closed) return;
          if (_handshake.isCompleted) {
            onDisconnect();
          } else {
            _handshake.completeError(error, stack);
          }
        },
      ),
    );
    unawaited(_listen(process, request, onDisconnect));
    try {
      _write(bridgeHandshake(_initializeId));
    } catch (error, stack) {
      if (!_handshake.isCompleted) _handshake.completeError(error, stack);
    }
    await initialized;
  }

  Future<void> _listen(
    Process process,
    BridgeRequest request,
    void Function() onDisconnect,
  ) async {
    try {
      await for (final bytes in _frames(process.stdout)) {
        if (_closed) return;
        final frame = bridgeDecode(bytes);
        if (!_handshake.isCompleted) {
          checkBridgeHandshake(frame, _initializeId);
          _handshake.complete();
          continue;
        }
        final response = await handleBridgeRequest(frame, request);
        if (!_closed && response != null) _write(response);
      }
    } catch (error, stack) {
      if (!_handshake.isCompleted) _handshake.completeError(error, stack);
    } finally {
      if (!_handshake.isCompleted) {
        _handshake.completeError(const BridgeError(-32000, 'Module exited'));
      } else if (!_closed) {
        onDisconnect();
      }
    }
  }

  static Stream<List<int>> _frames(Stream<List<int>> input) async* {
    final frame = BytesBuilder(copy: false);
    await for (final chunk in input) {
      for (var start = 0; start < chunk.length;) {
        final end = chunk.indexOf(10, start);
        final stop = end < 0 ? chunk.length : end;
        if (frame.length + stop - start > bridgeFrameLimit) {
          throw const FormatException('Bridge frame too large');
        }
        frame.add(chunk.sublist(start, stop));
        if (end >= 0) yield frame.takeBytes();
        start = stop + 1;
      }
    }
  }

  void _write(BridgeJson frame) {
    final input = _process?.stdin;
    if (input != null && !_closed) {
      input.add(utf8.encode('${jsonEncode(frame)}\n'));
    }
  }

  @override
  Future<void> publish(String method, BridgeJson params) async {
    _write(bridgeCall(method, params));
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    final process = _process;
    if (process == null) return;
    unawaited(process.stdin.close().then<void>((_) {}, onError: (Object _) {}));
    process.kill();
  }
}

class HttpBridge implements BridgeLink {
  HttpBridge(this.endpoint, this.token);

  final Uri endpoint;
  final String token;
  final _client = HttpClient()..findProxy = (_) => 'DIRECT';
  bool _closed = false;

  @override
  Future<void> open(BridgeRequest request, void Function() onDisconnect) async {
    final response = await _exchange(
      'POST',
      bridgeHandshake(_initializeId),
    ).timeout(_handshakeTimeout);
    checkBridgeHandshake(bridgeObject(response), _initializeId);
    if (!_closed) unawaited(_poll(request, onDisconnect));
  }

  Future<void> _poll(BridgeRequest request, void Function() disconnect) async {
    var failures = 0;
    BridgeJson? reply;
    while (!_closed) {
      try {
        if (reply != null) {
          await _exchange('POST', reply).timeout(_handshakeTimeout);
          reply = null;
        }
        final frame = await _exchange(
          'GET',
          null,
        ).timeout(const Duration(seconds: 30));
        if (_closed) return;
        if (frame == null) {
          // Also avoid a busy loop with modules that return 204 immediately.
          await Future<void>.delayed(const Duration(milliseconds: 250));
        } else {
          reply = await handleBridgeRequest(frame, request);
        }
        failures = 0;
      } catch (_) {
        if (_closed) return;
        failures++;
        if (failures >= 4) {
          disconnect();
          return;
        }
        await Future<void>.delayed(Duration(seconds: failures));
      }
    }
  }

  Future<BridgeJson?> _exchange(String method, BridgeJson? body) async {
    final request = await _client.openUrl(method, endpoint);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    if (response.statusCode == 204) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200) {
      throw const BridgeError(-32000, 'Module returned an HTTP error');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > bridgeFrameLimit) {
        throw const FormatException('Bridge frame too large');
      }
      bytes.add(chunk);
    }
    return bridgeDecode(bytes.takeBytes());
  }

  @override
  Future<void> publish(String method, BridgeJson params) async {
    await _exchange(
      'POST',
      bridgeCall(method, params),
    ).timeout(_handshakeTimeout);
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
