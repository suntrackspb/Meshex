import 'database.dart';

/// Plain-text mentions stay compatible with clients without mention metadata.
abstract final class NodeMentions {
  static String nodeId(int num) => '!${num.toRadixString(16).padLeft(8, '0')}';

  static bool matches(String text, Iterable<String> names) => names.any((name) {
    final value = name.trim();
    if (value.isEmpty) return false;
    return RegExp(
      '(?<![\\p{L}\\p{N}_])${RegExp.escape(value)}(?![\\p{L}\\p{N}_])',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  });

  static bool mentions(
    String text,
    int num, {
    String longName = '',
    String shortName = '',
    String userId = '',
  }) => matches(text, [
    longName,
    shortName,
    userId,
    nodeId(num),
    nodeId(num).substring(1),
  ]);

  static String insertion(Node node, String format) => switch (format) {
    'nodeId' => nodeId(node.num),
    'shortName' =>
      node.shortName.trim().isEmpty ? nodeId(node.num) : node.shortName.trim(),
    _ => node.longName.trim().isEmpty ? nodeId(node.num) : node.longName.trim(),
  };

  /// Query ends at the cursor; spaces are allowed for multi-word long names.
  static ({int start, int end, String query})? query(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    final prefix = text.substring(0, cursor);
    final match = RegExp(r'(?:^|[\s(\[{])@([^@\n\r]*)$').firstMatch(prefix);
    if (match == null) return null;
    return (
      start: prefix.lastIndexOf('@'),
      end: cursor,
      query: match.group(1)!.toLowerCase(),
    );
  }

  static List<Node> candidates(Iterable<Node> nodes, String query) {
    final result = nodes
        .where(
          (n) => [
            n.longName,
            n.shortName,
            n.userId,
            nodeId(n.num),
          ].any((s) => s.toLowerCase().contains(query)),
        )
        .toList();
    result.sort(
      (a, b) => insertion(
        a,
        'longName',
      ).toLowerCase().compareTo(insertion(b, 'longName').toLowerCase()),
    );
    return result;
  }
}
