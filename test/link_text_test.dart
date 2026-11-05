import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/features/chat/link_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget message(String text) => MaterialApp(
    home: Scaffold(body: Center(child: LinkText(text))),
  );

  testWidgets('link tap survives a feed rebuild while the finger is down', (
    tester,
  ) async {
    const url = 'https://example.com';
    await tester.pumpWidget(message(url));
    final gesture = await tester.startGesture(tester.getCenter(find.text(url)));
    await tester.pumpWidget(message(url));
    await gesture.up();
    await tester.pump();
    expect(launched, [url]);
  });

  testWidgets('updated message opens its new link', (tester) async {
    await tester.pumpWidget(message('https://example.com/old'));
    const url = 'https://example.com/new';
    await tester.pumpWidget(message(url));
    await tester.tap(find.text(url));
    await tester.pump();
    expect(launched, [url]);
    await tester.pumpWidget(message('plain text'));
    await tester.tap(find.text('plain text'));
    await tester.pump();
    expect(launched, [url]);
  });
}
