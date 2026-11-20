import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum BridgeTransport { process, http }

enum BridgeChannelMode { mentions, all }

bool get bridgesSupported =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

String bridgeNonce() {
  final random = Random.secure();
  return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
}

Uri? bridgeHttpEndpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'http' ||
      !const {'127.0.0.1', '::1'}.contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return uri.replace(path: '/rpc');
}

class BridgeConfig {
  const BridgeConfig({
    this.id = '',
    this.transport = BridgeTransport.process,
    this.endpoint = '',
    this.arguments = const [],
    this.node = 0,
    this.direct = false,
    this.sendDirect = false,
    this.sendChannels = false,
    this.channels = const {},
  });

  final String id;
  final BridgeTransport transport;
  final String endpoint;
  final List<String> arguments;
  final int node;
  final bool direct;
  final bool sendDirect;
  final bool sendChannels;

  // The fingerprint ties the local slot to its current channel credentials.
  final Map<String, BridgeChannelMode> channels;

  factory BridgeConfig.decode(String? value) {
    if (value == null) return const BridgeConfig();
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final channels = (json['channels'] as Map<String, dynamic>?) ?? {};
      return BridgeConfig(
        id: json['id'] as String,
        transport: BridgeTransport.values.byName(json['transport'] as String),
        endpoint: json['endpoint'] as String,
        arguments: (json['arguments'] as List).cast<String>(),
        node: json['node'] as int,
        direct: json['direct'] == true,
        sendDirect: json['sendDirect'] == true,
        sendChannels: json['sendChannels'] == true,
        channels: channels.map(
          (key, mode) =>
              MapEntry(key, BridgeChannelMode.values.byName(mode as String)),
        ),
      );
    } on Object {
      return const BridgeConfig();
    }
  }

  String encode() => jsonEncode({
    'id': id,
    'transport': transport.name,
    'endpoint': endpoint,
    'arguments': arguments,
    'node': node,
    'direct': direct,
    'sendDirect': sendDirect,
    'sendChannels': sendChannels,
    'channels': channels.map((key, mode) => MapEntry(key, mode.name)),
  });
}
