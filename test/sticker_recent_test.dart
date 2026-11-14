import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/app/sticker_providers.dart';
import 'package:meshex/data/database.dart';

void main() {
  test('recent stickers persist, deduplicate and keep the latest 20', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (var i = 0; i < 25; i++) {
      await recordRecentSticker(db, (packSha256: 'pack', stickerId: '$i'));
    }
    await recordRecentSticker(db, (packSha256: 'pack', stickerId: '10'));
    final recent = parseRecentStickers(
      await db.getSetting(recentStickersSettingKey),
    );
    expect(recent.length, 20);
    expect(recent.first.stickerId, '10');
    expect(recent[1].stickerId, '24');
    expect(recent.last.stickerId, '5');
    expect(recent.toSet().length, 20);
  });
  test('invalid history is treated as empty', () {
    expect(parseRecentStickers('invalid'), isEmpty);
    expect(parseRecentStickers(null), isEmpty);
  });
}
