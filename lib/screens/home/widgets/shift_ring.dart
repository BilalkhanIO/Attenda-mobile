import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

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
      ..color = AppColors.gray200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (pct > 0) {
      final sweepAngle = 2 * 3.14159265 * pct;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final arcPaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -3.14159265 / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.pct != pct;
}
