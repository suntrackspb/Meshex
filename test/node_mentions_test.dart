import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/data/mentions.dart';
import 'package:meshex/data/database.dart';
import 'package:meshex/data/notify/message_alerts.dart';
import 'message_alerts_test.dart' as fixtures;

void main() {
  const node = Node(
    num: 0xaabb1234,
    userId: '!aabb1234',
    longName: 'Дальняя Нода',
    shortName: 'DN',
    hwModel: 0,
    role: 0,
    isUnmessagable: false,
    hasXeddsaSigned: false,
    viaMqtt: false,
    isFavorite: false,
    isIgnored: false,
    mirrorCorrected: false,
    onRadio: true,
    onMirror: false,
  );

  test('search by each identifier inserts configured name without @', () {
    for (final query in ['', 'дальняя', 'нода', 'dn', 'aabb1234', '!aabb']) {
      final found = NodeMentions.candidates([node], query);
      expect(found, [node]);
      expect(NodeMentions.insertion(found.single, 'longName'), 'Дальняя Нода');
      expect(NodeMentions.insertion(found.single, 'shortName'), 'DN');
      expect(NodeMentions.insertion(found.single, 'nodeId'), '!aabb1234');
    }
    expect(NodeMentions.candidates([node], 'missing'), isEmpty);
    final unnamed = node.copyWith(longName: '', shortName: '');
    expect(NodeMentions.insertion(unnamed, 'longName'), '!aabb1234');
    expect(NodeMentions.insertion(unnamed, 'shortName'), '!aabb1234');
  });

  test('all identifiers with and without @, case, punctuation and Unicode', () {
    for (final name in [
      'Дальняя Нода',
      'ЯZ',
      '!aabb1234',
      'aabb1234',
      '!custom',
    ]) {
      for (final prefix in ['', '@']) {
        final text = 'Привет, $prefix${name.toUpperCase()}!';
        expect(
          NodeMentions.mentions(
            text,
            0xaabb1234,
            longName: 'Дальняя Нода',
            shortName: 'ЯZ',
            userId: '!custom',
          ),
          isTrue,
          reason: text,
        );
        expect(
          MessageAlerts.classify(
            fixtures.msg(body: text),
            const AlertContext(
              me: 0xaabb1234,
              myLongName: 'Дальняя Нода',
              myShortName: 'ЯZ',
              myUserId: '!custom',
            ),
          ),
          AlertKind.mention,
          reason: text,
        );
      }
    }
  });

  test('no partial word matches or empty names', () {
    for (final text in ['superNODE', 'NODE123', 'NODE_', 'яNODE', 'NODEя']) {
      expect(NodeMentions.matches(text, ['node']), isFalse);
    }
    expect(NodeMentions.matches('hello', ['', '  ']), isFalse);
    expect(NodeMentions.matches('@A+B,', ['A+B']), isTrue);
  });

  test(
    'query follows cursor, accepts multi-word names and excludes emails',
    () {
      expect(NodeMentions.query('@', 1)?.query, '');
      expect(NodeMentions.query('Привет @Дальняя Но', 18)?.query, 'дальняя но');
      expect(NodeMentions.query('mail@example.org', 16), isNull);
      expect(NodeMentions.query('@node\ntext', 10), isNull);
      expect(NodeMentions.query('@one @two', 9)?.query, 'two');
      expect(NodeMentions.query('@one suffix', 4)?.query, 'one');
      expect(NodeMentions.query('@one', -1), isNull);
    },
  );
}
