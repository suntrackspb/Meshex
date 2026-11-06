import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/stickers.dart';
import 'package:meshex/features/chat/sticker_picker.dart';
import 'package:meshex/l10n/l10n.dart';

void main() {
  testWidgets(
    'picker switches packs and returns the tapped immutable sticker ID',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StickerRef? picked;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await pickSticker(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Бисквит · 49'), findsOneWidget);
      expect(find.text('Мемы · 10'), findsOneWidget);
      await tester.tap(find.text('Мемы · 10'));
      await tester.pump();
      // Animated images keep scheduling frames, so don't pumpAndSettle here.
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(StickerImage).first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(picked?.wire, 'sticker:eto:s1:MemeS1ick3r:001');
    },
  );

  testWidgets('unknown pack shows a readable placeholder, not a broken image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StickerMessageBody(ref: StickerRef('future_pack', '001')),
        ),
      ),
    );
    expect(find.text('future_pack / 001'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion uses a still preview', (tester) async {
    final asset = StickerCatalog.packs.last.stickers.first;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: StickerImage(sticker: asset)),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, endsWith('/001.png'));
  });

  test('all ten converted memes contain multiple animation frames', () async {
    for (final asset in StickerCatalog.packs.last.stickers) {
      final bytes = await rootBundle.load(asset.path);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      expect(codec.frameCount, greaterThan(1), reason: asset.path);
      codec.dispose();
    }
  });
}
