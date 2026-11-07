import 'package:flutter_test/flutter_test.dart';
import 'package:meshex/mirror/mirror_capabilities.dart';

Map<String, Object?> declaration() => {
  'enabled': true,
  'source_schema_versions': [1],
  'wire_versions': [2],
  'sources': [
    {'url': 'https://s.example/stickers/source.json', 'label': 'Demo'},
  ],
};

void main() {
  test('source service does not require message API and cache roundtrips', () {
    final caps = MirrorCapabilities.parse({'stickers': declaration()});
    expect(caps.stickers!.sources.single.label, 'Demo');
    expect(caps.stickers!.messageApi, isNull);
    expect(
      MirrorCapabilities.parse(caps.toJson()).stickers!.toJson(),
      caps.stickers!.toJson(),
    );
    final ready = MirrorCapabilities.parse({
      'stickers': {
        ...declaration(),
        'message_api': {'version': 1, 'history': true, 'realtime': false},
      },
    });
    expect(ready.stickers!.messageApi!.history, isTrue);
    expect(ready.stickers!.messageApi!.realtime, isFalse);
  });

  test(
    'missing, disabled, incompatible and oversized declarations are ignored',
    () {
      for (final raw in [
        null,
        false,
        {...declaration(), 'enabled': false},
        {
          ...declaration(),
          'source_schema_versions': [2],
        },
        {...declaration(), 'sources': 'bad'},
        {
          ...declaration(),
          'sources': List.filled(17, {'url': 'https://s.example/source.json'}),
        },
      ]) {
        final caps = MirrorCapabilities.parse({
          'stickers': raw,
          'reports': {'base_url': 'https://r.example/'},
        });
        expect(caps.stickers, isNull);
        expect(caps.reports, isNotNull);
      }
    },
  );

  test(
    'deduplicate normalized URLs and isolate malformed sources and message API',
    () {
      final caps = MirrorCapabilities.parse({
        'stickers': {
          ...declaration(),
          'sources': [
            {'url': 'HTTPS://S.EXAMPLE:443/source.json'},
            {'url': 'https://s.example/source.json'},
            {'url': 'https://127.0.0.1/source.json'},
            {'url': 'https://other.example/source.json', 'label': 'bad\nlabel'},
            {'url': 10},
          ],
          'message_api': {'version': 2, 'history': true, 'realtime': true},
        },
      }).stickers!;
      expect(caps.sources.map((s) => s.url), [
        'https://s.example/source.json',
        'https://other.example/source.json',
      ]);
      expect(caps.sources.last.label, isNull);
      expect(caps.messageApi, isNull);
    },
  );
}
