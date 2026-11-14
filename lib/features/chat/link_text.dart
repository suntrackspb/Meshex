import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/links.dart';

/// Текст сообщения с кликабельными ссылками (открываются во внешнем браузере).
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key});

  final String text;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _taps = <TapGestureRecognizer>[];
  late List<TextPart> _parts;

  @override
  void initState() {
    super.initState();
    _updateLinks();
  }

  @override
  void didUpdateWidget(covariant LinkText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _updateLinks();
  }

  void _updateLinks() {
    _clear();
    _parts = splitLinks(widget.text);
    for (final part in _parts) {
      final uri = part.link;
      if (uri == null) continue;
      _taps.add(
        TapGestureRecognizer()
          ..onTap = () => launchUrl(uri, mode: LaunchMode.externalApplication),
      );
    }
  }

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final text = _buildText(context);
    return desktop ? SelectionArea(child: text) : text;
  }

  Widget _buildText(BuildContext context) {
    // Keep recognizers alive across feed/theme rebuilds: disposing one while
    // the finger is down cancels the pending tap.
    if (_taps.isEmpty) return Text(widget.text);
    var linkIndex = 0;
    final color = Theme.of(context).colorScheme.primary;
    return Text.rich(
      TextSpan(
        children: [
          for (final p in _parts)
            if (p.link != null)
              TextSpan(
                text: p.text,
                style: TextStyle(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
                recognizer: _taps[linkIndex++],
              )
            else
              TextSpan(text: p.text),
        ],
      ),
    );
  }
}
