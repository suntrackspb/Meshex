import 'package:flutter/material.dart';

/// Website wordmark: Manrope ExtraBold with the three Meshex brand colors.
class MeshexWordmark extends StatelessWidget {
  const MeshexWordmark({super.key, this.fontSize = 64});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text.rich(
        const TextSpan(
          children: [
            TextSpan(
              text: 'mes',
              style: TextStyle(color: Color(0xFF227DF3)),
            ),
            TextSpan(
              text: 'h',
              style: TextStyle(color: Color(0xFF8848DB)),
            ),
            TextSpan(
              text: 'ex',
              style: TextStyle(color: Color(0xFFCF3E83)),
            ),
          ],
        ),
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.075 * fontSize,
          height: 1,
        ),
        semanticsLabel: 'Meshex',
        textDirection: TextDirection.ltr,
        maxLines: 1,
      ),
    );
  }
}
