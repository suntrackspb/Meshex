import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../radio/radio_session.dart';

/// Текст постоянного уведомления; null — служба не нужна.
typedef KeepAliveStatus = ({String title, String text});

/// Пока есть соединение с нодой (или идёт переподключение), держим процесс
/// живым: на Android без foreground service система рвёт BLE в фоне.
/// Подписи — Meshtastic-Android ru.
KeepAliveStatus? keepAliveStatus(
  RadioState state,
  String? target, {
  String? mqtt,
  String Function(String)? translate,
}) {
  final text = switch (state) {
    RadioState.idle => null,
    RadioState.ready => 'Подключено',
    RadioState.waitingReconnect => 'Отключено',
    _ => 'Подключение',
  };
  if (text == null) return null;
  final name = target == null || target.isEmpty ? '' : ': $target';
  return (
    title: 'Meshex$name',
    text: mqtt == null
        ? (translate?.call(text) ?? text)
        : '${translate?.call(text) ?? text} · MQTT: ${translate?.call(mqtt) ?? mqtt}',
  );
}

/// Служба удержания связи. На всех платформах, кроме Android, ничего не делает
/// (iOS держит BLE фоновым режимом bluetooth-central).
abstract interface class KeepAlive {
  Future<void> update(KeepAliveStatus? status);

  factory KeepAlive.platform({void Function(Object)? onError}) =>
      Platform.isAndroid
      ? AndroidKeepAlive(onError: onError)
      : const _NoKeepAlive();
}

class _NoKeepAlive implements KeepAlive {
  const _NoKeepAlive();
  @override
  Future<void> update(KeepAliveStatus? status) async {}
}

@pragma('vm:entry-point')
void _keepAliveCallback() => FlutterForegroundTask.setTaskHandler(_Idle());

/// Служебный изолят не открывает вторую БД и соединение. MeshApplication
/// удерживает основной движок после закрытия Activity и восстанавливает его
/// через onTaskStart при пересоздании службы системой.
class _Idle extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class AndroidKeepAlive implements KeepAlive {
  AndroidKeepAlive({this.onError});

  final void Function(Object)? onError;
  bool _init = false;
  bool _asked = false;
  KeepAliveStatus? _desired;
  Timer? _retry;
  int _failures = 0;
  final _options = ForegroundTaskOptions(
    eventAction: ForegroundTaskEventAction.nothing(),
    allowWakeLock: true,
    allowWifiLock: true,
    stopWithTask: false,
    allowAutoRestart: true,
  );

  /// Вызовы приходят на каждое изменение состояния — выполняем по очереди.
  Future<void> _chain = Future.value();

  @override
  Future<void> update(KeepAliveStatus? status) {
    _desired = status;
    _retry?.cancel();
    return _chain = _chain.then((_) async {
      try {
        await _apply(status);
        _failures = 0;
      } catch (e) {
        onError?.call(e);
        // Retry failed starts even when the radio status hasn't changed.
        // A newer status supersedes this request, including an explicit stop.
        if (_desired != status) return;
        final seconds = (5 * (1 << _failures.clamp(0, 4))).clamp(5, 60);
        _failures++;
        _retry = Timer(Duration(seconds: seconds), () => update(_desired));
      }
    });
  }

  Future<void> _apply(KeepAliveStatus? s) async {
    final running = await FlutterForegroundTask.isRunningService;
    if (s == null) {
      if (running) _check(await FlutterForegroundTask.stopService());
      return;
    }
    if (!_init) {
      _init = true;
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'connection',
          channelName: 'Служебные уведомления',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
        ),
        foregroundTaskOptions: _options,
      );
    }
    if (running) {
      _check(
        await FlutterForegroundTask.updateService(
          foregroundTaskOptions: _options,
          notificationTitle: s.title,
          notificationText: s.text,
        ),
      );
      return;
    }
    // Android 13+: без разрешения служба работает, но уведомление скрыто.
    if (!_asked) {
      _asked = true;
      final p = await FlutterForegroundTask.checkNotificationPermission();
      if (p == NotificationPermission.denied) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }
    _check(
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
        notificationTitle: s.title,
        notificationText: s.text,
        callback: _keepAliveCallback,
      ),
    );
  }

  void _check(ServiceRequestResult result) {
    if (result is ServiceRequestFailure) throw result.error;
  }
}
