import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The wordmark: the app icon's arched A, then "NIGEN" in Bebas Neue, with
/// the A sized to the capitals. Shared by [AnigenLogo] and the intro.
class Wordmark {
  final Color color;
  final TextPainter text;

  /// Bebas Neue's capitals are 0.7 of its size
  final double capHeight;
  final double gap;

  /// A dark halo, so it reads over bright artwork.
  final bool shadow;

  Wordmark({
    required double fontSize,
    required double letterSpacing,
    required this.color,
    this.shadow = false,
  }) : capHeight = fontSize * 0.7,
       gap = fontSize * 0.06 + letterSpacing,
       text = TextPainter(
         text: TextSpan(
           text: 'NIGEN',
           style: TextStyle(
             fontFamily: 'BebasNeue',
             fontSize: fontSize,
             letterSpacing: letterSpacing,
             height: 1,
             color: color,
             shadows: shadow ? _shadows : null,
           ),
         ),
         textDirection: TextDirection.ltr,
       )..layout();

  static const _shadows = [
    Shadow(color: Colors.black, blurRadius: 2),
    Shadow(color: Colors.black87, blurRadius: 10),
  ];

  // The A in assets/icon/anigen.svg, stroke included, is 37 x 40.5 units
  double get unit => capHeight / 40.5;
  double get aWidth => 37 * unit;

  Size get size => Size(aWidth + gap + text.width, text.height);

  /// Just the A, lying on its side as on the icon.
  Size get markSize => Size(40.5 * unit, aWidth);
}

class WordmarkPainter extends CustomPainter {
  final Wordmark wordmark;
  final double opacity;

  /// 0 lying on its side as on the icon, 1 upright.
  final double turn;

  /// 0 hidden behind the A, 1 in place.
  final double slide;

  /// Only the A, as on the icon, filling [Wordmark.markSize].
  final bool markOnly;

  WordmarkPainter({
    required this.wordmark,
    this.opacity = 1,
    this.turn = 1,
    this.slide = 1,
    this.markOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = wordmark;
    if (markOnly) {
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(-math.pi / 2);
      _paintA(canvas);
      canvas.restore();
      return;
    }
    // The A starts in the middle and moves left as the letters come out,
    // so the whole word ends up centred
    final shift = (size.width - w.aWidth) / 2 * (1 - slide);
    final aRight = shift + w.aWidth;

    // The A: the icon's path, centred on its middle
    canvas.save();
    canvas.translate(shift + w.aWidth / 2, size.height / 2);
    canvas.rotate(-math.pi / 2 * (1 - turn));
    // Starts near the size of the splash screen's icon, settles as it turns
    canvas.scale(1.45 - 0.45 * turn);
    _paintA(canvas);
    canvas.restore();

    // NIGEN, slid out from behind the A's right edge
    if (slide <= 0) return;
    final baseline = w.text.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    // Capitals centred on the A
    final top = (size.height - w.capHeight) / 2 - (baseline - w.capHeight);
    final x = aRight + w.gap - (w.text.width + w.gap) * (1 - slide);
    if (slide >= 1) {
      w.text.paint(canvas, Offset(x, top));
      return;
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(aRight, -size.height, 1e6, size.height * 2));
    canvas.saveLayer(
      null,
      Paint()
        ..color = Colors.black.withValues(alpha: (slide * 2.5).clamp(0, 1)),
    );
    w.text.paint(canvas, Offset(x, top));
    canvas.restore();
    canvas.restore();
  }

  /// The icon's A, centred on the origin.
  void _paintA(Canvas canvas) {
    final u = wordmark.unit;
    final a = Path()
      ..moveTo(-14 * u, 20.25 * u)
      ..lineTo(-14 * u, -1.75 * u)
      ..arcTo(
        Rect.fromCircle(center: Offset(0, -1.75 * u), radius: 14 * u),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(14 * u, 20.25 * u)
      ..moveTo(-14 * u, 7.25 * u)
      ..lineTo(14 * u, 7.25 * u);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * u;
    if (wordmark.shadow) {
      for (final s in Wordmark._shadows) {
        canvas.drawPath(
          a,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9 * u
            ..color = s.color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.blurSigma),
        );
      }
    }
    canvas.drawPath(
      a,
      stroke
        ..color = wordmark.color.withValues(alpha: wordmark.color.a * opacity),
    );
  }

  @override
  bool shouldRepaint(WordmarkPainter old) =>
      old.wordmark != wordmark ||
      old.opacity != opacity ||
      old.turn != turn ||
      old.slide != slide ||
      old.markOnly != markOnly;
}
