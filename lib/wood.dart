import 'dart:math';

import 'package:flutter/material.dart';

/// Wood tones. Stains are pastel so green/yellow still read as green/yellow.
abstract final class Wood {
  static const birch = Color(0xFFEBCFA3);
  static const oak = Color(0xFFD6A96E);
  static const walnut = Color(0xFF8A5A36);
  static const green = Color(0xFF86C49A);
  static const yellow = Color(0xFFF0C95E);
  static const grey = Color(0xFF9C928A);
  static const ink = Color(0xFF4A2F1B);
}

/// A rounded plank with gradient, wavy grain and a bevel. [seed] varies the grain per box.
class WoodBox extends StatelessWidget {
  final Color color;
  final Widget? child;
  final double radius;
  final int seed;
  final bool raised;

  const WoodBox({super.key, required this.color, this.child, this.radius = 8, this.seed = 0, this.raised = true});

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.35)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: raised
            ? [
                BoxShadow(color: dark, offset: const Offset(0, 3)),
                const BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 4)),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _WoodPainter(color, radius, seed, raised),
        child: Center(child: child),
      ),
    );
  }
}

class _WoodPainter extends CustomPainter {
  final Color color;
  final double radius;
  final int seed;
  final bool raised;
  _WoodPainter(this.color, this.radius, this.seed, this.raised);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final light = Color.lerp(color, Colors.white, 0.22)!;
    final dark = Color.lerp(color, Colors.black, 0.12)!;
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: raised ? [light, color, dark] : [dark, color, light],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipRRect(rr);
    final rng = Random(seed);
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..color = Color.lerp(color, Colors.brown.shade900, 0.3)!.withValues(alpha: 0.28);
    final lines = 4 + (size.height / 10).round();
    for (var i = 0; i < lines; i++) {
      final y0 = size.height * (i + rng.nextDouble()) / lines;
      final amp = 0.5 + rng.nextDouble() * 1.5;
      final freq = 0.5 + rng.nextDouble() * 1.2;
      final phase = rng.nextDouble() * pi * 2;
      grain.strokeWidth = 0.6 + rng.nextDouble() * 0.8;
      final path = Path()..moveTo(0, y0);
      for (double x = 0; x <= size.width; x += 3) {
        path.lineTo(x, y0 + amp * sin(phase + freq * 2 * pi * x / size.width));
      }
      canvas.drawPath(path, grain);
    }
    // a knot on some planks
    if (rng.nextDouble() < 0.25 && size.width > 30) {
      final c = Offset(size.width * (0.2 + rng.nextDouble() * 0.6), size.height * (0.3 + rng.nextDouble() * 0.4));
      for (var r = 1.5; r < 5; r += 1.5) {
        canvas.drawOval(Rect.fromCenter(center: c, width: r * 3, height: r * 1.6), grain);
      }
    }
    canvas.restore();

    // bevel: highlight on top edge, dark rim around
    canvas.drawRRect(
      rr.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: raised ? 0.55 : 0.1),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color.lerp(color, Colors.black, 0.4)!.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_WoodPainter old) => old.color != color || old.seed != seed || old.raised != raised || old.radius != radius;
}
