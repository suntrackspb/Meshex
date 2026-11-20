import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../bridges/bridge_config.dart';
import '../bridges/bridge_protocol.dart';
import '../bridges/external_bridge.dart';
import '../bridges/mesh_bridge.dart';
import '../core/radio/radio_session.dart';
import 'providers.dart';

final bridgeConfigProvider = StreamProvider<BridgeConfig>(
  (ref) => ref
      .watch(appDatabaseProvider)
      .watchSetting(bridgeSettingsKey)
      .map(BridgeConfig.decode),
);

final bridgeChannelsProvider = FutureProvider<List<BridgeChannel>>((ref) {
  ref.watch(channelsProvider);
  ref.watch(ownPresetProvider);
  return bridgeChannels(ref.watch(databaseProvider));
});

final bridgeControllerProvider = ChangeNotifierProvider<BridgeController>(
  BridgeController.new,
);

enum BridgeState { stopped, connecting, running, failed }

class BridgeController extends ChangeNotifier {
  BridgeController(this._ref);

  final Ref _ref;
  final _secrets = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  MeshBridge? _bridge;
  BridgeState state = BridgeState.stopped;
  String? detail;
  bool _disposed = false;
  int _generation = 0;

  static String _secretKey(String id) => 'meshex.bridge.$id';

  Future<BridgeConfig> save(BridgeConfig form, String secret) async {
    final db = _ref.read(appDatabaseProvider);
    final old = BridgeConfig.decode(await db.getSetting(bridgeSettingsKey));
    final sameConnection =
        old.id.isNotEmpty &&
        old.transport == form.transport &&
        old.endpoint == form.endpoint &&
        listEquals(old.arguments, form.arguments);
    final needsSecret = form.transport == BridgeTransport.http;
    final value = secret.isNotEmpty
        ? secret
        : sameConnection && needsSecret
        ? await _secrets.read(key: _secretKey(old.id))
        : null;
    if (needsSecret && (value == null || value.isEmpty)) {
      throw const BridgeError(-32000, 'Enter a connection token');
    }
    final id = sameConnection && secret.isEmpty ? old.id : bridgeNonce();
    if (needsSecret && id != old.id) {
      await _secrets.write(key: _secretKey(id), value: value);
    }
    final config = BridgeConfig(
      id: id,
      transport: form.transport,
      endpoint: form.endpoint,
      arguments: List.unmodifiable(form.arguments),
      node: form.node,
      direct: form.direct,
      sendDirect: form.sendDirect,
      sendChannels: form.sendChannels,
      channels: Map.unmodifiable(form.channels),
    );
    try {
      await db.setSetting(bridgeSettingsKey, config.encode());
    } catch (_) {
      if (needsSecret && id != old.id) {
        await _secrets.delete(key: _secretKey(id));
      }
      rethrow;
    }
    stop();
    if (old.id.isNotEmpty && id != old.id) {
      try {
        await db.deleteSetting('bridge.commands.${old.id}');
        if (old.transport == BridgeTransport.http) {
          await _secrets.delete(key: _secretKey(old.id));
        }
      } catch (_) {
        // The new connection was committed and cannot load the old credentials.
      }
    }
    return config;
  }

  Future<void> start(BridgeConfig config) async {
    if (!bridgesSupported ||
        config.id.isEmpty ||
        config.node == 0 ||
        _disposed) {
      return;
    }
    _bridge?.close();
    _bridge = null;
    final generation = ++_generation;
    _set(BridgeState.connecting);
    try {
      final store = _ref.read(appDatabaseProvider);
      final radio = _ref.read(radioProvider);
      final incoming = _ref.read(radioTextEventsProvider).stream;
      final secret = config.transport == BridgeTransport.process
          ? null
          : await _secrets.read(key: _secretKey(config.id));
      if (!_isCurrent(generation)) return;
      if (config.transport == BridgeTransport.http &&
          (secret == null || secret.isEmpty)) {
        throw const BridgeError(-32000, 'Save a connection token first');
      }
      final BridgeLink link;
      switch (config.transport) {
        case BridgeTransport.process:
          link = ProcessBridge(config.endpoint, config.arguments);
        case BridgeTransport.http:
          final endpoint = bridgeHttpEndpoint(config.endpoint);
          if (endpoint == null) {
            throw const BridgeError(
              -32000,
              'Enter a loopback HTTP address and port',
            );
          }
          link = HttpBridge(endpoint, secret!);
      }
      final bridge = MeshBridge(
        config: config,
        db: () => _ref.read(databaseProvider),
        settings: store,
        connectedNode: () =>
            _isCurrent(generation) &&
                radio.state == RadioState.ready &&
                _ref.read(activeNodeDbProvider) == radio.myNodeNum
            ? radio.myNodeNum
            : null,
        sender: () => _ref.read(messageSenderProvider),
        link: link,
        onDisconnect: () {
          if (_isCurrent(generation)) _fail('Connection to the module closed');
        },
      );
      _bridge = bridge;
      await bridge.start(incoming);
      if (_isCurrent(generation)) _set(BridgeState.running);
    } on BridgeError catch (error) {
      if (_isCurrent(generation)) _fail(error.message);
    } catch (_) {
      if (_isCurrent(generation)) {
        _fail(
          'Could not connect to the module. Check its settings and API version.',
        );
      }
    }
  }

  bool _isCurrent(int generation) => !_disposed && _generation == generation;

  void _set(BridgeState value, [String? message]) {
    state = value;
    detail = message;
    if (!_disposed) notifyListeners();
  }

  void _fail(String reason) {
    ++_generation;
    _bridge?.close();
    _bridge = null;
    _set(BridgeState.failed, reason);
  }

  void stop() {
    ++_generation;
    _bridge?.close();
    _bridge = null;
    _set(BridgeState.stopped);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
