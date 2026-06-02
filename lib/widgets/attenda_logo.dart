import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/theme.dart';

enum AttendaLogoVariant { dark, light }

/// Attenda brand logo: clock-face icon + "Attenda" wordmark.
///
/// Use [AttendaLogoVariant.dark] for dark/navy backgrounds (white wordmark).
/// Use [AttendaLogoVariant.light] for light/white backgrounds (dark wordmark).
class AttendaLogo extends StatelessWidget {
  final double iconSize;
  final bool showWordmark;
  final AttendaLogoVariant variant;

  const AttendaLogo({
    super.key,
    this.iconSize = 44,
    this.showWordmark = true,
    this.variant = AttendaLogoVariant.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: Size(iconSize, iconSize),
          painter: _AttendaIconPainter(variant: variant),
        ),
        if (showWordmark) ...[
          SizedBox(width: iconSize * 0.28),
          _AttendaWordmark(size: iconSize * 0.64, variant: variant),
        ],
      ],
    );
  }
}

class _AttendaWordmark extends StatelessWidget {
  final double size;
  final AttendaLogoVariant variant;

  const _AttendaWordmark({required this.size, required this.variant});

  @override
  Widget build(BuildContext context) {
    final baseColor = variant == AttendaLogoVariant.dark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF321847);
    final accentColor = AppColors.primary;

    final style = GoogleFonts.dmSans(
      fontWeight: FontWeight.w800,
      fontSize: size,
      letterSpacing: -0.02 * size,
      height: 1,
    );

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'Att', style: style.copyWith(color: baseColor)),
          TextSpan(text: 'en', style: style.copyWith(color: accentColor)),
          TextSpan(text: 'da', style: style.copyWith(color: baseColor)),
        ],
      ),
    );
  }
}

class _AttendaIconPainter extends CustomPainter {
  final AttendaLogoVariant variant;

  const _AttendaIconPainter({required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Scale factor: original viewBox is 44x44
    final scale = s / 44.0;
    canvas.scale(scale, scale);

    final isDark = variant == AttendaLogoVariant.dark;

    // ── Outer ring ──────────────────────────────────────────
    canvas.drawCircle(
      const Offset(22, 22),
      20,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // ── Inner fill ──────────────────────────────────────────
    canvas.drawCircle(
      const Offset(22, 22),
      14,
      Paint()
        ..color = isDark
            ? AppColors.primary.withOpacity(0.15)
            : AppColors.primary.withOpacity(0.1),
    );

    // ── Clock ticks ─────────────────────────────────────────
    const tickColor = AppColors.primary;

    // Top tick (prominent)
    _drawLine(canvas, const Offset(22, 9), const Offset(22, 12), tickColor, 2.0);
    // Bottom tick
    _drawLine(canvas, const Offset(22, 32), const Offset(22, 35), tickColor, 1.2, opacity: 0.4);
    // Left tick
    _drawLine(canvas, const Offset(9, 22), const Offset(12, 22), tickColor, 1.2, opacity: 0.4);
    // Right tick
    _drawLine(canvas, const Offset(32, 22), const Offset(35, 22), tickColor, 1.2, opacity: 0.4);

    // ── Hour hand ────────────────────────────────────────────
    _drawLine(
      canvas,
      const Offset(22, 22),
      const Offset(22, 15),
      AppColors.primary,
      2.2,
    );

    // ── Minute hand ──────────────────────────────────────────
    _drawLine(
      canvas,
      const Offset(22, 22),
      const Offset(27.5, 22),
      isDark ? const Color(0xFFF1F5F9) : const Color(0xFF321847),
      2.2,
    );

    // ── Center dot ───────────────────────────────────────────
    canvas.drawCircle(
      const Offset(22, 22),
      2.2,
      Paint()..color = AppColors.primary,
    );

    // ── Badge background (dark halo) ─────────────────────────
    canvas.drawCircle(
      const Offset(33, 33),
      7,
      Paint()..color = isDark ? AppColors.bgDark2 : const Color(0xFFF8FAFC),
    );

    // ── Green badge fill ─────────────────────────────────────
    canvas.drawCircle(
      const Offset(33, 33),
      6,
      Paint()..color = const Color(0xFF10B981),
    );

    // ── White checkmark ──────────────────────────────────────
    final checkPath = Path()
      ..moveTo(29.5, 33)
      ..lineTo(32, 35.5)
      ..lineTo(36.5, 30.5);

    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Color color,
    double width, {
    double opacity = 1.0,
  }) {
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = color.withOpacity(opacity)
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_AttendaIconPainter old) => old.variant != variant;
}
