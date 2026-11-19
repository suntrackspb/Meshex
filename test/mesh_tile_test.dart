import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/ui/kit/kit.dart';

void main() {
  testWidgets('secondary click and touch hold invoke the context action', (
    tester,
  ) async {
    var opened = 0;
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MeshTile(
                title: 'With context action',
                onTap: () => opened++,
                onContextAction: () => actions++,
              ),
              MeshTile(title: 'Without context action', onTap: () => opened++),
            ],
          ),
        ),
      ),
    );

    final withAction = find.widgetWithText(ListTile, 'With context action');
    final withoutAction = find.widgetWithText(
      ListTile,
      'Without context action',
    );
    await tester.tap(
      withAction,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    expect(actions, 1);
    expect(opened, 0);

    await tester.longPress(withAction);
    expect(actions, 2);
    expect(opened, 0);

    await tester.tap(withAction, kind: PointerDeviceKind.mouse);
    expect(opened, 1);
    expect(actions, 2);

    await tester.tap(
      withoutAction,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    expect(opened, 1);
    expect(actions, 2);
  });
}
