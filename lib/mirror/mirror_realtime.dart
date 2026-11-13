import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/client_version.dart';
import 'mirror_models.dart';

enum MirrorState { idle, connecting, connected, waiting, outdated }

enum MirrorTransport { ws, sse }

/// Код закрытия WebSocket: зеркало отказало этой версии приложения.
const wsCloseOutdated = 4426;

/// Realtime-подписка на зеркало (WebSocket с резервным SSE) и переподключением.
/// При недоступности WS после [maxTransportAttempts] неудачных попыток
/// переключается на [sseUrl] (если объявлен в capabilities) и чередует
/// транспорты по [maxTransportAttempts] попыток. Во время работы по SSE
/// периодически проверяет доступность WS в фоне и возвращается на него без
/// разрыва ленты.
class MirrorRealtime extends ChangeNotifier {
  MirrorRealtime(
    this.url,
    this.onEvent, {
    Uri? sseUrl,
    this.log,
    this.onOutdated,
    this.onTransportChanged,
    this.maxTransportAttempts = 3,
    this.connectTimeout = const Duration(seconds: 8),
    this.sseReadTimeout = const Duration(seconds: 45),
    this.wsProbeInterval = const Duration(minutes: 2),
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
    http.Client Function()? httpClientFactory,
  }) : _sseUrl = sseUrl,
       _httpClientFactory = httpClientFactory ?? VersionedClient.new;

  final Uri url;
  final Future<void> Function(MirrorEvent e) onEvent;
  final void Function(String)? log;

  /// Зеркало отказало этой версии ([wsCloseOutdated] или HTTP 426).
  /// Переподключений нет до [reconnectNow] (возврат в приложение).
  final void Function()? onOutdated;

  /// Вызывается при смене активного транспорта (WS ↔ SSE).
  final void Function(MirrorTransport)? onTransportChanged;

  final int maxTransportAttempts;
  final Duration connectTimeout;
  final Duration sseReadTimeout;
  final Duration wsProbeInterval;
  final List<Duration> retryDelays;
  final http.Client Function() _httpClientFactory;

  MirrorState state = MirrorState.idle;
  int retryIn = 0;
  String? lastError;

  MirrorTransport _transport = MirrorTransport.ws;
  MirrorTransport get transport => _transport;

  Uri? _sseUrl;
  Uri? get sseUrl => _sseUrl;
  set sseUrl(Uri? value) {
    if (_sseUrl == value) return;
    _sseUrl = value;
    if (value == null && _transport == MirrorTransport.sse) {
      _setTransport(MirrorTransport.ws);
      if (_running) reconnectNow();
    } else if (value != null &&
        _transport == MirrorTransport.ws &&
        state != MirrorState.connected &&
        _transportFailures >= maxTransportAttempts) {
      _transportFailures = 0;
      _attempt = 0;
      _setTransport(MirrorTransport.sse);
      if (_running && state == MirrorState.waiting) {
        _retry?.cancel();
        _countdown?.cancel();
        _connect();
      }
    }
  }

  WebSocket? _ws;
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  Timer? _retry;
  Timer? _countdown;
  Timer? _wsProbe;
  bool _probingWs = false;
  int _attempt = 0;
  int _transportFailures = 0;
  bool _receivedEvent = false;
  bool _running = false;
  Future<void> _queue = Future.value();

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  /// Переподключиться сразу (возврат в приложение, смена сети).
  void reconnectNow() {
    if (!_running) return;
    _attempt = 0;
    _transportFailures = 0;
    _retry?.cancel();
    _countdown?.cancel();
    _closeWs();
    _closeSse();
    _setTransport(MirrorTransport.ws);
    _connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _countdown?.cancel();
    _closeSse();
    final ws = _ws;
    _ws = null;
    await ws?.close(WebSocketStatus.goingAway);
    _set(MirrorState.idle);
  }

  Future<void> _connect() async {
    if (!_running) return;
    _set(MirrorState.connecting);
    if (_transport == MirrorTransport.sse && _sseUrl != null) {
      await _connectSse(_sseUrl!);
    } else {
      if (_transport != MirrorTransport.ws) {
        _setTransport(MirrorTransport.ws);
      }
      await _connectWs();
    }
  }

  Future<void> _connectWs() async {
    try {
      final ws = await WebSocket.connect(
        url.toString(),
        headers: clientHeaders(),
      ).timeout(connectTimeout);
      if (!_running || _transport != MirrorTransport.ws) {
        await ws.close();
        return;
      }
      _attachWs(ws);
    } catch (e) {
      if (!_running || _transport != MirrorTransport.ws) return;
      lastError = '$e';
      _onAttemptFailed();
    }
  }

  void _attachWs(WebSocket ws, {bool fromProbe = false}) {
    // Пинг каждые 15 с; без понга сокет закроется сам — не ждём системного таймаута.
    ws.pingInterval = const Duration(seconds: 15);
    _ws = ws;
    _receivedEvent = false;
    _attempt = 0;
    lastError = null;
    _set(MirrorState.connected);
    log?.call(
      fromProbe
          ? 'Зеркало: переключено с SSE на WebSocket'
          : 'Зеркало: подключено',
    );
    ws.listen(
      _onData,
      onError: (Object e) => lastError = '$e',
      onDone: () => _onWsClosed(ws),
      cancelOnError: true,
    );
  }

  Future<void> _connectSse(Uri target) async {
    final client = _httpClientFactory();
    _sseClient = client;
    try {
      final req = http.Request('GET', target)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final res = await client.send(req).timeout(connectTimeout);
      if (!_running || !identical(client, _sseClient)) {
        client.close();
        return;
      }
      if (res.statusCode == 426) {
        _sseClient = null;
        client.close();
        log?.call('Зеркало: версия приложения устарела');
        _set(MirrorState.outdated);
        onOutdated?.call();
        return;
      }
      if (res.statusCode != 200) {
        _sseClient = null;
        client.close();
        lastError = 'HTTP ${res.statusCode}';
        _onAttemptFailed();
        return;
      }
      _receivedEvent = false;
      _attempt = 0;
      lastError = null;
      _set(MirrorState.connected);
      log?.call('Зеркало: подключено (SSE)');
      _startWsProbe();

      final dataLines = <String>[];
      _sseSub = res.stream
          .timeout(sseReadTimeout)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) {
                if (dataLines.isNotEmpty) {
                  final data = dataLines.join('\n');
                  dataLines.clear();
                  _onData(data);
                }
              } else if (line.startsWith('data:')) {
                final v = line.substring(5);
                dataLines.add(v.startsWith(' ') ? v.substring(1) : v);
              }
            },
            onError: (Object e) => lastError = '$e',
            onDone: () => _onSseClosed(client),
            cancelOnError: true,
          );
    } catch (e) {
      if (!identical(client, _sseClient)) {
        client.close();
        return;
      }
      _sseClient = null;
      client.close();
      if (!_running) return;
      lastError = '$e';
      _onAttemptFailed();
    }
  }

  void _startWsProbe() {
    _wsProbe?.cancel();
    _wsProbe = Timer.periodic(wsProbeInterval, (_) => _probeWs());
  }

  Future<void> _probeWs() async {
    if (!_running ||
        _transport != MirrorTransport.sse ||
        state != MirrorState.connected ||
        _probingWs) {
      return;
    }
    _probingWs = true;
    try {
      final ws = await WebSocket.connect(
        url.toString(),
        headers: clientHeaders(),
      ).timeout(connectTimeout);
      if (!_running ||
          _transport != MirrorTransport.sse ||
          state != MirrorState.connected) {
        await ws.close(WebSocketStatus.goingAway);
        return;
      }
      _closeSse();
      _transportFailures = 0;
      _setTransport(MirrorTransport.ws);
      _attachWs(ws, fromProbe: true);
    } catch (_) {
      // WS всё ещё недоступен — остаёмся на SSE без разрыва.
    } finally {
      _probingWs = false;
    }
  }

  void _onData(dynamic data) {
    final Object? j;
    try {
      j = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
    } catch (_) {
      return;
    }
    if (j is! Map<String, dynamic>) return;
    _receivedEvent = true;
    _transportFailures = 0;
    final e = MirrorEvent.parse(j);
    if (e is MirrorOther) return;
    // По порядку: init должен лечь в БД раньше new_message.
    _queue = _queue.then((_) => onEvent(e)).catchError((Object err) {
      log?.call('Зеркало: ошибка обработки ${e.runtimeType}: $err');
    });
  }

  void _onWsClosed(WebSocket ws) {
    if (!identical(ws, _ws)) return; // закрыли сами при reconnectNow/stop
    _ws = null;
    if (ws.closeCode == wsCloseOutdated) {
      log?.call('Зеркало: версия приложения устарела');
      _set(MirrorState.outdated);
      onOutdated?.call();
      return;
    }
    log?.call(
      'Зеркало: соединение закрыто${lastError == null ? '' : ' ($lastError)'}',
    );
    if (_receivedEvent) {
      _scheduleRetry();
    } else {
      _onAttemptFailed();
    }
  }

  void _onSseClosed(http.Client client) {
    if (!identical(client, _sseClient)) return;
    _sseSub = null;
    _sseClient = null;
    client.close();
    _wsProbe?.cancel();
    log?.call(
      'Зеркало: SSE закрыто${lastError == null ? '' : ' ($lastError)'}',
    );
    if (_receivedEvent) {
      _scheduleRetry();
    } else {
      _onAttemptFailed();
    }
  }

  void _onAttemptFailed() {
    if (!_running) return;
    _transportFailures++;
    if (_sseUrl != null && _transportFailures >= maxTransportAttempts) {
      final next = _transport == MirrorTransport.ws
          ? MirrorTransport.sse
          : MirrorTransport.ws;
      _transportFailures = 0;
      _attempt = 0;
      _setTransport(next);
      log?.call(
        'Зеркало: переключение на ${next == MirrorTransport.sse ? 'SSE' : 'WebSocket'}',
      );
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running) return;
    _attempt++;
    final d = retryDelays[(_attempt - 1).clamp(0, retryDelays.length - 1)];
    retryIn = (d.inMilliseconds / 1000).ceil().clamp(1, 999);
    _set(MirrorState.waiting);
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (retryIn > 1) {
        retryIn--;
        notifyListeners();
      }
    });
    _retry = Timer(d, () {
      _countdown?.cancel();
      _connect();
    });
  }

  void _closeWs() {
    final ws = _ws;
    _ws = null;
    ws?.close(WebSocketStatus.goingAway);
  }

  void _closeSse() {
    _wsProbe?.cancel();
    final sub = _sseSub;
    _sseSub = null;
    sub?.cancel();
    final client = _sseClient;
    _sseClient = null;
    client?.close();
  }

  void _setTransport(MirrorTransport t) {
    if (_transport == t) return;
    _transport = t;
    onTransportChanged?.call(t);
    notifyListeners();
  }

  void _set(MirrorState s) {
    state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _running = false;
    _retry?.cancel();
    _countdown?.cancel();
    _closeWs();
    _closeSse();
    super.dispose();
  }
}
