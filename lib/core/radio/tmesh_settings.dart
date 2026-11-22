import 'dart:async';

import 'package:protobuf/protobuf.dart' show InvalidProtocolBufferException;

import '../proto/mesh.dart';
import '../proto/tmesh/feature_flags.pb.dart' as tmesh;
import 'radio_session.dart';
import 'send_queue.dart';

enum TmeshError implements Exception {
  connectionChanged,
  noResponse,
  sendRejected,
  invalidConfig,
  storage,
  configChanged,
  writeInProgress,
  unverified,
}

extension TmeshConfigValues on tmesh.FeatureFlagsConfig {
  /// Nanopb omits scalar defaults from replies. Compare their values even
  /// when Dart encoded a default explicitly.
  Record get values => (
    restrictedRoutingMode,
    restrictedRoutingDisallowsPrivateText,
    hopDecrementMode,
    forceNextHopMode,
    forceNextHopRelay,
    favoriteRouterMode,
    favoriteRouterRelay,
  );
}

/// TMesh feature flags on one local connection. The firmware replies with a
/// TMesh envelope on ADMIN_APP, independently of Meshtastic delivery status.
class TmeshSettings {
  TmeshSettings(
    this._radio,
    this.nodeNum,
    this._connectedSince, {
    this.timeout = const Duration(seconds: 15),
  });

  final RadioSession _radio;
  final int nodeNum;
  final DateTime _connectedSince;
  final Duration timeout;
  bool _writing = false;

  bool get _isCurrent =>
      _radio.state == RadioState.ready &&
      _radio.myNodeNum == nodeNum &&
      identical(_radio.connectedSince, _connectedSince);

  /// Any recognized TMesh status confirms protocol support, including a
  /// storage error. Absence of a reply leaves support unknown.
  Future<bool> probe() async {
    try {
      await _request(tmesh.Request_Operation.GET);
      return true;
    } on TmeshError {
      return false;
    }
  }

  Future<tmesh.FeatureFlagsConfig?> read() async {
    final response = await _request(tmesh.Request_Operation.GET);
    _requireOk(response);
    return response.hasConfig() ? response.config : null;
  }

  /// SET replaces the config. Merge the user's edits into a fresh copy, or
  /// start with defaults when the editor opened without a stored config.
  Future<tmesh.FeatureFlagsConfig> save({
    required bool hadConfig,
    required void Function(tmesh.FeatureFlagsConfig) edit,
  }) => _runWrite(() async {
    final current = await read();
    if ((current != null) != hadConfig) throw TmeshError.configChanged;
    final next = current?.deepCopy() ?? tmesh.FeatureFlagsConfig();
    edit(next);
    if (!_validRelay(next.forceNextHopMode.value, next.forceNextHopRelay) ||
        !_validRelay(next.favoriteRouterMode.value, next.favoriteRouterRelay)) {
      throw TmeshError.invalidConfig;
    }
    return _write(next);
  });

  Future<T> _runWrite<T>(Future<T> Function() operation) async {
    if (_writing) throw TmeshError.writeInProgress;
    _writing = true;
    try {
      return await operation();
    } finally {
      _writing = false;
    }
  }

  static bool _validRelay(int mode, int relay) =>
      relay >= (mode == 0 ? 0 : 1) && relay <= 255;

  Future<tmesh.FeatureFlagsConfig> _write(
    tmesh.FeatureFlagsConfig config,
  ) async {
    try {
      _requireOk(await _request(tmesh.Request_Operation.SET, config));
    } on TmeshError catch (error) {
      // A lost reply can mean the write already reached storage. Check with
      // GET before reporting the outcome and never repeat the write here.
      if (error != TmeshError.noResponse) rethrow;
    }
    final tmesh.FeatureFlagsConfig? checked;
    try {
      checked = await read();
    } on TmeshError {
      throw TmeshError.unverified;
    }
    if (checked == null || checked.values != config.values) {
      throw TmeshError.unverified;
    }
    return checked;
  }

  static void _requireOk(tmesh.Response response) {
    switch (response.status) {
      case tmesh.Response_Status.OK:
        return;
      case tmesh.Response_Status.INVALID_ARGUMENT:
        throw TmeshError.invalidConfig;
      case tmesh.Response_Status.STORAGE_ERROR:
        throw TmeshError.storage;
      default:
        throw TmeshError.noResponse;
    }
  }

  Future<tmesh.Response> _request(
    tmesh.Request_Operation operation, [
    tmesh.FeatureFlagsConfig? config,
  ]) async {
    if (!_isCurrent) throw TmeshError.connectionChanged;
    final id = _radio.queue.nextId();
    final envelope = tmesh.Envelope(
      request: tmesh.Request(operation: operation, config: config),
    );
    final packet = MeshPacket(
      id: id,
      to: nodeNum,
      hopLimit: 0,
      wantAck: false,
      decoded: Data(
        portnum: PortNum.ADMIN_APP,
        wantResponse: true,
        payload: envelope.writeToBuffer(),
      ),
    );

    final reply = Completer<tmesh.Response>();
    void fail(TmeshError error) {
      if (!reply.isCompleted) reply.completeError(error);
    }

    void onConnectionChanged() {
      if (!_isCurrent) fail(TmeshError.connectionChanged);
    }

    _radio.addListener(onConnectionChanged);
    final incoming = _radio.packets.listen((frame) {
      if (reply.isCompleted || !_isCurrent || !frame.hasPacket()) return;
      final responsePacket = frame.packet;
      if (responsePacket.from != nodeNum || !responsePacket.hasDecoded()) {
        return;
      }
      final data = responsePacket.decoded;
      if (data.portnum != PortNum.ADMIN_APP || data.requestId != id) return;
      try {
        final decoded = tmesh.Envelope.fromBuffer(data.payload);
        if (decoded.hasResponse() &&
            decoded.response.hasStatus() &&
            decoded.response.status != tmesh.Response_Status.UNSPECIFIED) {
          reply.complete(decoded.response);
        }
      } on InvalidProtocolBufferException {
        // An ordinary admin response or malformed payload cannot complete RPC.
      }
    }, onDone: () => fail(TmeshError.connectionChanged));
    final timer = Timer(timeout, () => fail(TmeshError.noResponse));

    try {
      unawaited(
        _radio
            .sendPacket(
              packet,
              beforeWrite: () async {
                if (!_isCurrent || reply.isCompleted) {
                  throw TmeshError.connectionChanged;
                }
              },
            )
            .then((result) {
              switch (result.status) {
                case DeliveryStatus.disconnected:
                  fail(TmeshError.connectionChanged);
                case DeliveryStatus.rejected || DeliveryStatus.failed:
                  fail(TmeshError.sendRejected);
                case DeliveryStatus.acked || DeliveryStatus.timeout:
                  break;
              }
            }),
      );
      return await reply.future;
    } finally {
      timer.cancel();
      _radio.removeListener(onConnectionChanged);
      await incoming.cancel();
    }
  }
}
