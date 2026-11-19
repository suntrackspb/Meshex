import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/appearance.dart';

bool get supportsAppDisplayScale =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

/// Gives the app a logical viewport at the selected zoom, then fits it to the
/// window. Flutter applies the same transform to painting and hit testing.
class AppDisplayScale extends StatelessWidget {
  const AppDisplayScale({
    super.key,
    required this.interfacePercent,
    required this.textPercent,
    required this.child,
  });

  final int interfacePercent;
  final int textPercent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final zoom = interfacePercent / defaultAppearanceScale;
    final text = textPercent / defaultAppearanceScale;
    final size = media.size / zoom;
    final textScaler = text == 1
        ? media.textScaler
        : _AppTextScaler(media.textScaler, text);

    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            devicePixelRatio: media.devicePixelRatio * zoom,
            padding: media.padding / zoom,
            viewPadding: media.viewPadding / zoom,
            viewInsets: media.viewInsets / zoom,
            systemGestureInsets: media.systemGestureInsets / zoom,
            displayFeatures: zoom == 1
                ? media.displayFeatures
                : [
                    for (final feature in media.displayFeatures)
                      DisplayFeature(
                        bounds: Rect.fromLTRB(
                          feature.bounds.left / zoom,
                          feature.bounds.top / zoom,
                          feature.bounds.right / zoom,
                          feature.bounds.bottom / zoom,
                        ),
                        type: feature.type,
                        state: feature.state,
                      ),
                  ],
            textScaler: textScaler,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AppTextScaler extends TextScaler {
  const _AppTextScaler(this.system, this.multiplier);

  final TextScaler system;
  final double multiplier;

  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _AppTextScaler &&
      other.system == system &&
      other.multiplier == multiplier;

  @override
  int get hashCode => Object.hash(system, multiplier);
}
