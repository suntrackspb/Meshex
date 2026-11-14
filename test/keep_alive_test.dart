import 'package:meshex/core/background/keep_alive.dart';
import 'package:meshex/core/radio/radio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_foreground_task/methods');
  var running = false;
  var failStart = false;
  final calls = <MethodCall>[];
  setUp(() {
    running = false;
    failStart = false;
    calls.clear();
    FlutterForegroundTask.skipServiceResponseCheck = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isRunningService':
              return running;
            case 'checkNotificationPermission':
              return NotificationPermission.granted.index;
            case 'startService':
              if (failStart) throw PlatformException(code: 'start-denied');
              running = true;
            case 'stopService':
              running = false;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    FlutterForegroundTask.skipServiceResponseCheck = false;
  });

  testWidgets('failed start is reported and retried without a status change', (
    tester,
  ) async {
    final errors = <Object>[];
    final keepAlive = AndroidKeepAlive(onError: errors.add);
    failStart = true;
    await keepAlive.update((title: 'Meshex', text: 'Подключено'));
    expect(errors, hasLength(1));
    failStart = false;
    await tester.pump(const Duration(seconds: 5));
    expect(calls.where((c) => c.method == 'startService'), hasLength(2));
    expect(running, isTrue);
    await keepAlive.update(null);
    expect(running, isFalse);
  });

  testWidgets('disconnect cancels a pending restart', (tester) async {
    final keepAlive = AndroidKeepAlive();
    failStart = true;
    await keepAlive.update((title: 'Meshex', text: 'Подключено'));
    await keepAlive.update(null);
    await tester.pump(const Duration(minutes: 1));
    expect(calls.where((c) => c.method == 'startService'), hasLength(1));
  });

  test('running service receives the updated task removal policy', () async {
    running = true;
    final keepAlive = AndroidKeepAlive();
    await keepAlive.update((title: 'Meshex', text: 'Подключено'));
    final update = calls.singleWhere((c) => c.method == 'updateService');
    expect(update.arguments['stopWithTask'], isFalse);
    expect(update.arguments['allowAutoRestart'], isTrue);
    expect(calls.where((c) => c.method == 'startService'), isEmpty);
    await keepAlive.update(null);
    expect(running, isFalse);
  });

  test('no service when idle', () {
    expect(keepAliveStatus(RadioState.idle, 'T-Beam'), isNull);
  });

  test('status text follows radio state', () {
    expect(keepAliveStatus(RadioState.ready, 'T-Beam'), (
      title: 'Meshex: T-Beam',
      text: 'Подключено',
    ));
    expect(keepAliveStatus(RadioState.configuring, null)?.text, 'Подключение');
    expect(keepAliveStatus(RadioState.waitingReconnect, '')?.title, 'Meshex');
    expect(
      keepAliveStatus(RadioState.ready, 'X', mqtt: 'Подключено')?.text,
      'Подключено · MQTT: Подключено',
    );
  });
}
