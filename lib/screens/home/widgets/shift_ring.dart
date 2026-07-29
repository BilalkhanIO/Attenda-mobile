import 'package:flutter/material.dart';

// ─── Shift Progress Ring ────────────────────────────────

class ShiftRing extends StatelessWidget {
  final double pct;
  final Widget center;
  const ShiftRing({super.key, required this.pct, required this.center});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: const Size(100, 100),
          painter: _RingPainter(pct: pct),
        ),
        center,
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  const _RingPainter({required this.pct});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 9;
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct > 0) {
      final sweepAngle = 2 * 3.14159265 * pct;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: -3.14159265 / 2,
        endAngle: -3.14159265 / 2 + sweepAngle,
        colors: const [Color(0xFF00C896), Color(0xFF00E5FF)],
      );
      final arcPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -3.14159265 / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}
