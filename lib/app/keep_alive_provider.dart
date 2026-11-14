import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/background/keep_alive.dart';
import '../mqtt/mqtt_proxy.dart';
import 'mqtt_providers.dart';
import 'providers.dart';
import 'locale_provider.dart';
import '../l10n/l10n.dart';
import '../core/radio/journal.dart';
import '../core/radio/radio_session.dart';

/// Текст уведомления службы: состояние радио и (если работает) MQTT-прокси.
final _keepAliveStatusProvider = Provider<KeepAliveStatus?>((ref) {
  final state = ref.watch(radioProvider.select((r) => r.state));
  // Do not stop the restarted service while the persisted endpoint is loading.
  final restoring =
      ref.watch(restoreRadioOnStartupProvider) &&
      ref.watch(startupConnectProvider).isLoading;
  final target = ref.watch(radioProvider.select((r) => r.target?.title));
  final mqtt = ref.watch(
    mqttProxyProvider.select(
      (p) => p.state == MqttProxyState.inactive ? null : p.statusText,
    ),
  );
  final strings = ref.watch(appStringsProvider);
  return keepAliveStatus(
    restoring && state == RadioState.idle ? RadioState.waitingReconnect : state,
    target,
    mqtt: mqtt,
    translate: (text) => localizeBuiltInText(strings, text),
  );
});

/// Служба удержания связи (Android). Держится живой из корня приложения.
final keepAliveProvider = Provider<KeepAlive>((ref) {
  final journal = ref.read(journalProvider);
  final k = KeepAlive.platform(
    onError: (e) => journal.add(JournalKind.error, 'Фоновая служба: $e'),
  );
  ref.listen(
    _keepAliveStatusProvider,
    (_, s) => k.update(s),
    fireImmediately: true,
  );
  ref.onDispose(() => k.update(null));
  return k;
});
