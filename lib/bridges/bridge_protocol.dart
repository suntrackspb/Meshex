import 'dart:async';
import 'dart:convert';

typedef BridgeJson = Map<String, dynamic>;
const bridgeApiVersion = 1;
const bridgeFrameLimit = 256 * 1024;

class BridgeError implements Exception {
  const BridgeError(this.code, this.message);
  final int code;
  final String message;
}

BridgeJson bridgeObject(Object? value) {
  if (value is! BridgeJson) {
    throw const BridgeError(-32602, 'Expected a JSON object');
  }
  return value;
}

String bridgeString(BridgeJson data, String key, {int max = 200}) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw BridgeError(-32602, 'Invalid $key');
  }
  return value;
}

BridgeJson bridgeDecode(List<int> value) {
  if (value.length > bridgeFrameLimit) {
    throw const FormatException('Bridge frame too large');
  }
  return bridgeObject(jsonDecode(utf8.decode(value)));
}

BridgeJson bridgeCall(String method, BridgeJson params, {String? id}) => {
  'jsonrpc': '2.0',
  'id': ?id,
  'method': method,
  'params': params,
};

BridgeJson bridgeResult(String id, Object? result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

BridgeJson bridgeFailure(String? id, BridgeError error) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': error.code, 'message': error.message},
};

typedef BridgeRequest =
    Future<BridgeJson> Function(String method, BridgeJson params);

abstract interface class BridgeLink {
  Future<void> open(BridgeRequest request, void Function() onDisconnect);
  Future<void> publish(String method, BridgeJson params);
  void close();
}

Future<BridgeJson?> handleBridgeRequest(
  BridgeJson frame,
  BridgeRequest handler,
) async {
  final id = frame['id'];
  final method = frame['method'];
  if (frame['jsonrpc'] != '2.0' ||
      method is! String ||
      (id != null && id is! String)) {
    return bridgeFailure(null, const BridgeError(-32600, 'Invalid request'));
  }
  if (id == null) return null;
  try {
    final result = await handler(
      method,
      bridgeObject(frame['params'] ?? <String, dynamic>{}),
    );
    return bridgeResult(id as String, result);
  } on BridgeError catch (error) {
    return bridgeFailure(id as String, error);
  } catch (_) {
    return bridgeFailure(
      id as String,
      const BridgeError(-32603, 'Internal error'),
    );
  }
}

void checkBridgeHandshake(BridgeJson response, String id) {
  if (response['jsonrpc'] != '2.0' ||
      response['id'] != id ||
      (response['result'] as Object?) is! BridgeJson ||
      (response['result'] as BridgeJson)['apiVersion'] != bridgeApiVersion) {
    throw const BridgeError(-32000, 'Incompatible bridge API');
  }
}

BridgeJson bridgeHandshake(String id) => bridgeCall('bridge.initialize', {
  'apiVersion': bridgeApiVersion,
  'maxTextBytes': 200,
}, id: id);
