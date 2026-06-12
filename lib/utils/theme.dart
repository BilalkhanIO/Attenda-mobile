import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Aurora Liquid Glass 2026 Color Tokens ────────────
class AppColors {
  // ── Primary palette ──────────────────────────────────
  static const primary   = Color(0xFF00C896);   // emerald
  static const secondary = Color(0xFF00E5FF);   // cyan
  static const accent    = Color(0xFFFF6FD8);

  // ── Legacy aliases (used across all screens) ──────────
  static const primary600 = primary;
  static const primary500 = Color(0xFF00B488);   // emerald mid-shade
  static const primary100 = Color(0xFFCCF5EC);   // light emerald
  static const primary900 = Color(0xFF006B50);   // deep emerald

  // ── Semantic colors ───────────────────────────────────
  static const success500 = Color(0xFF22C55E);
  static const success700 = Color(0xFF15803D);
  static const success100 = Color(0xFFDCFCE7);
  static const warning500 = Color(0xFFF59E0B);
  static const warning800 = Color(0xFF92400E);
  static const warning100 = Color(0xFFFEF3C7);
  static const danger500  = Color(0xFFEF4444);
  static const danger800  = Color(0xFF991B1B);
  static const danger100  = Color(0xFFFEE2E2);

  // ── Neutral ───────────────────────────────────────────
  static const gray50  = Color(0xFFF8FAFC);
  static const gray100 = Color(0xFFF1F5F9);
  static const gray200 = Color(0xFFE2E8F0);
  static const gray400 = Color(0xFF94A3B8);
  static const gray500 = Color(0xFF64748B);
  static const white   = Color(0xFFFFFFFF);

  // ── Legacy accent aliases ─────────────────────────────
  static const purple500 = primary;           // indigo is the new purple
  static const purple700 = Color(0xFF4338CA);
  static const purple100 = primary100;
  static const teal100   = secondary;         // cyan is the new teal
  static const teal700   = Color(0xFF0EA5E9);

  // ── Dark backgrounds ──────────────────────────────────
  static const bgDark  = Color(0xFF04141A);   // very dark teal-black
  static const bgDark2 = Color(0xFF081D24);   // deep teal-dark
  static const bgDark3 = Color(0xFF0E2A34);   // mid teal-dark

  // ── Legacy mesh aliases ───────────────────────────────
  static const meshBot = bgDark;
  static const meshMid = bgDark2;
  static const meshTop = bgDark3;
  static const dark950 = bgDark;
  static const dark800 = bgDark2;
  static const dark700 = bgDark3;

  // ── Glass surface tokens ──────────────────────────────
  static const glass05     = Color(0x0DFFFFFF);
  static const glass10     = Color(0x1AFFFFFF);
  static const glass12     = Color(0x1FFFFFFF);
  static const glass15     = Color(0x26FFFFFF);
  static const glass20     = Color(0x33FFFFFF);
  static const glassBorder = Color(0x2EFFFFFF);
  static const glassHigh   = Color(0x5AFFFFFF);

  // ── On-glass text tokens ──────────────────────────────
  static const onGlass      = white;
  static const onGlassSub   = Color(0xCCFFFFFF);
  static const onGlassMuted = Color(0x99FFFFFF);
  static const onGlassDim   = Color(0x55FFFFFF);

  // ── Text ──────────────────────────────────────────────
  static const textPrimary   = white;
  static const textSecondary = Color(0xFFB8C0D4);
}

// ─── Gradient Palette ────────────────────────────────
class AppGradients {
  // Background
  static const mesh = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.bgDark3, AppColors.bgDark2, AppColors.bgDark],
    stops: [0.0, 0.5, 1.0],
  );

  // Primary action button: Aurora
  static const primaryBtn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.secondary],
  );

  // Glass card surface
  static const glassCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
  );

  // Premium gradient set
  static const aurora = LinearGradient(
    colors: [AppColors.primary, AppColors.secondary],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const sunset = LinearGradient(
    colors: [AppColors.accent, Color(0xFFFF9671)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const emerald = LinearGradient(
    colors: [Color(0xFF00C896), Color(0xFF00E5FF)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
  static const cyber = LinearGradient(
    colors: [Color(0xFF7B61FF), Color(0xFFFF3CAC)],
    begin: Alignment.topLeft, end: Alignment.bottomRight,
  );
}

/// Parses a server-provided "#RRGGBB" hex string. Malformed values fall back
/// instead of throwing a FormatException mid-build.
Color parseHexColor(String? hex, {Color fallback = AppColors.primary600}) {
  if (hex == null) return fallback;
  final cleaned = hex.replaceFirst('#', '');
  if (cleaned.length != 6) return fallback;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? fallback : Color(0xFF000000 | value);
}

// ─── Status Colors ────────────────────────────────────
class StatusColors {
  static Color bg(String status) {
    switch (status) {
      case 'in':         return AppColors.success100;
      case 'late':       return AppColors.warning100;
      case 'absent':     return AppColors.danger100;
      case 'remote':     return AppColors.primary100;
      case 'leave':      return AppColors.primary100;
      case 'half_leave': return const Color(0xFFE0F2FE);
      default:           return AppColors.gray100;
    }
  }

  static Color fg(String status) {
    switch (status) {
      case 'in':         return AppColors.success700;
      case 'late':       return AppColors.warning800;
      case 'absent':     return AppColors.danger800;
      case 'remote':     return AppColors.primary900;
      case 'leave':      return AppColors.primary900;
      case 'half_leave': return const Color(0xFF0369A1);
      default:           return AppColors.gray500;
    }
  }

  static String label(String status) {
    switch (status) {
      case 'in':         return 'Checked In';
      case 'out':        return 'Checked Out';
      case 'late':       return 'Late';
      case 'absent':     return 'Absent';
      case 'remote':     return 'Remote';
      case 'leave':      return 'On Leave';
      case 'half_leave': return 'Half-Day';
      default:           return status;
    }
  }

  static IconData icon(String status) {
    switch (status) {
      case 'in':         return Icons.check_circle;
      case 'out':        return Icons.logout;
      case 'late':       return Icons.warning_rounded;
      case 'absent':     return Icons.cancel;
      case 'remote':     return Icons.home_rounded;
      case 'leave':      return Icons.beach_access;
      case 'half_leave': return Icons.calendar_today;
      default:           return Icons.help_outline;
    }
  }
}

// ─── App Theme ────────────────────────────────────────
class AppTheme {
  static TextTheme _buildTextTheme(ThemeData base) => GoogleFonts.plusJakartaSansTextTheme(
    base.textTheme,
  ).copyWith(
    displayLarge:   const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
    headlineLarge:  const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    headlineMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge:     const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium:    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    bodyLarge:      const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
    bodyMedium:     const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    bodySmall:      const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelLarge:     const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
  );

  // Light theme kept for compatibility (dialogs, pickers, etc.)
  static ThemeData get light => build();

  // Primary dark glass theme
  static ThemeData get glass => build();

  static ThemeData build({
    Color primary = AppColors.primary,
    Color secondary = AppColors.secondary,
    VisualDensity visualDensity = VisualDensity.standard,
  }) {
    final base = ThemeData.dark();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: visualDensity,
      scaffoldBackgroundColor: AppColors.bgDark,
      colorScheme: ColorScheme(
        brightness:    Brightness.dark,
        primary:       primary,
        onPrimary:     Colors.white,
        secondary:     secondary,
        onSecondary:   Colors.white,
        tertiary:      AppColors.accent,
        onTertiary:    Colors.white,
        error:         AppColors.danger500,
        onError:       Colors.white,
        surface:       AppColors.bgDark3,
        onSurface:     Colors.white,
      ),
      textTheme: _buildTextTheme(base),
      appBarTheme: AppBarTheme(
        backgroundColor:  Colors.transparent,
        foregroundColor:  Colors.white,
        elevation:        0,
        shadowColor:      Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: AppColors.glass12,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger500),
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 14),
        labelStyle: GoogleFonts.plusJakartaSans(
          color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600, fontSize: 14,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor:            Colors.white,
        unselectedLabelColor:  Colors.white.withValues(alpha: 0.45),
        indicatorColor:        primary,
        dividerColor:          Colors.white.withValues(alpha: 0.1),
        labelStyle:            GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:  GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgDark3,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.1), thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgDark3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        contentTextStyle: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textSecondary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.bgDark2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : Colors.white54),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.white24),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
      ),
    );
  }
}
