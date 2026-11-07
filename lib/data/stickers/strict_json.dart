import 'dart:convert';

/// JSON decoder preserving the ability to reject duplicate (including escaped)
/// object keys. Dart's standard decoder silently keeps the last duplicate.
Map<String, dynamic> decodeStickerJson(List<int> bytes, {required int limit}) {
  if (bytes.length > limit) {
    throw const FormatException('Sticker JSON too large');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    throw const FormatException('Sticker JSON must not contain a BOM');
  }
  final parser = _Parser(utf8.decode(bytes));
  final value = parser.value(0);
  parser.space();
  if (parser.offset != parser.text.length || value is! Map<String, dynamic>) {
    throw const FormatException('Expected a single JSON object');
  }
  return value;
}

class _Parser {
  _Parser(this.text);
  final String text;
  int offset = 0;

  Never invalid() => throw const FormatException('Invalid sticker JSON');
  void space() {
    while (offset < text.length &&
        [9, 10, 13, 32].contains(text.codeUnitAt(offset))) {
      offset++;
    }
  }

  bool take(String token) {
    space();
    if (!text.startsWith(token, offset)) return false;
    offset += token.length;
    return true;
  }

  String string() {
    space();
    final start = offset;
    if (offset >= text.length || text[offset++] != '"') invalid();
    while (offset < text.length) {
      final c = text[offset++];
      if (c == '"') return jsonDecode(text.substring(start, offset)) as String;
      if (c == r'\') offset++;
    }
    invalid();
  }

  Object? value(int depth) {
    if (depth > 64) invalid();
    space();
    if (offset >= text.length) invalid();
    if (text[offset] == '"') return string();
    if (take('{')) {
      final result = <String, dynamic>{};
      if (take('}')) return result;
      do {
        final key = string();
        if (result.containsKey(key) || !take(':')) invalid();
        result[key] = value(depth + 1);
        if (take('}')) return result;
      } while (take(','));
      invalid();
    }
    if (take('[')) {
      final result = <Object?>[];
      if (take(']')) return result;
      do {
        result.add(value(depth + 1));
        if (take(']')) return result;
      } while (take(','));
      invalid();
    }
    final start = offset;
    while (offset < text.length && !',]} \t\r\n'.contains(text[offset])) {
      offset++;
    }
    if (start == offset) invalid();
    return jsonDecode(text.substring(start, offset));
  }
}
