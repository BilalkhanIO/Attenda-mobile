import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Minimal Design Tokens ────────────────────────────
// Standard minimal design: solid surfaces, one accent, hairline borders,
// whitespace-first structure. No blur, no translucency, no gradients.
class AppColors {
  // ── Primary accent (single) ──────────────────────────
  static const primary   = Color(0xFF059669);   // emerald 600
  static const secondary = primary;             // single accent: alias
  static const accent    = primary;             // single accent: alias

  // ── Primary shades ────────────────────────────────────
  static const primary600 = primary;
  static const primary500 = Color(0xFF10B981);
  static const primary100 = Color(0xFFD1FAE5);
  static const primary900 = Color(0xFF065F46);

  // ── Semantic colors ───────────────────────────────────
  static const success500 = Color(0xFF16A34A);
  static const success700 = Color(0xFF15803D);
  static const success100 = Color(0xFFDCFCE7);
  static const warning500 = Color(0xFFD97706);
  static const warning800 = Color(0xFF92400E);
  static const warning100 = Color(0xFFFEF3C7);
  static const danger500  = Color(0xFFDC2626);
  static const danger800  = Color(0xFF991B1B);
  static const danger100  = Color(0xFFFEE2E2);
  // Informational (breaks, notices)
  static const info500 = Color(0xFF0284C7);
  static const info700 = Color(0xFF0369A1);
  static const info100 = Color(0xFFE0F2FE);

  // ── Neutral scale ─────────────────────────────────────
  static const gray50  = Color(0xFFF8FAFC);
  static const gray100 = Color(0xFFF1F5F9);
  static const gray200 = Color(0xFFE2E8F0);
  static const gray300 = Color(0xFFCBD5E1);
  static const gray400 = Color(0xFF94A3B8);
  static const gray500 = Color(0xFF64748B);
  static const gray600 = Color(0xFF475569);
  static const gray700 = Color(0xFF334155);
  static const gray900 = Color(0xFF0F172A);
  static const white   = Color(0xFFFFFFFF);

  // ── Canonical surfaces ────────────────────────────────
  static const background = gray50;   // scaffold
  static const surface    = white;    // cards, sheets, dialogs
  static const border     = gray200;  // 1px hairline

  // ── Legacy accent aliases (kept for reference compat) ─
  static const purple500 = primary;      // remote-work accent → primary
  static const purple700 = primary900;
  static const purple100 = primary100;
  static const teal100   = info500;      // break/info accent
  static const teal700   = info700;

  // ── Legacy background aliases (now light surfaces) ────
  static const bgDark  = background;
  static const bgDark2 = surface;
  static const bgDark3 = surface;
  static const meshBot = background;
  static const meshMid = background;
  static const meshTop = background;
  static const dark950 = background;
  static const dark800 = surface;
  static const dark700 = surface;

  // ── Legacy glass aliases (now solid neutrals) ─────────
  static const glass05     = gray50;
  static const glass10     = gray100;
  static const glass12     = gray100;
  static const glass15     = gray100;
  static const glass20     = gray200;
  static const glassBorder = border;
  static const glassHigh   = gray300;

  // ── Legacy on-glass text aliases ──────────────────────
  static const onGlass      = gray900;
  static const onGlassSub   = gray700;
  static const onGlassMuted = gray500;
  static const onGlassDim   = gray400;

  // ── Text ──────────────────────────────────────────────
  static const textPrimary   = gray900;
  static const textSecondary = gray500;
}

// ─── Spacing (4-pt grid) ──────────────────────────────
class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;

  static const double screen  = 16;  // screen padding
  static const double card    = 16;  // card padding
  static const double section = 24;  // gap between sections
}

// ─── Radii (12–16) ────────────────────────────────────
class AppRadius {
  static const double control = 12;  // buttons, inputs, chips-on-cards
  static const double card    = 16;  // cards, dialogs, sheets
}

// ─── Motion (150–200 ms ease-out only) ────────────────
class AppMotion {
  static const Duration duration = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOut;
}

// ─── Type scale: 11/13/15/18/24, weights 500/700 ──────
class AppTextStyles {
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
  static const captionStrong = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
  static const body = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
  static const bodyStrong = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const title = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const headline = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const display = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary);

  /// Timers and counters: tabular figures so digits don't jitter.
  static const timer = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
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
      case 'half_leave': return AppColors.info100;
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
      case 'half_leave': return AppColors.info700;
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

// ─── Legacy gradient palette (now solid fills) ────────
// Decorative gradients are gone; each entry resolves to a flat fill so any
// remaining `Gradient`-typed call sites render solid color.
class AppGradients {
  static const mesh = LinearGradient(
    colors: [AppColors.background, AppColors.background],
  );
  static const primaryBtn = LinearGradient(
    colors: [AppColors.primary, AppColors.primary],
  );
  static const glassCard = LinearGradient(
    colors: [AppColors.surface, AppColors.surface],
  );
  static const aurora = LinearGradient(
    colors: [AppColors.primary, AppColors.primary],
  );
}

// ─── App Theme ────────────────────────────────────────
class AppTheme {
  static TextTheme _buildTextTheme(ThemeData base) => GoogleFonts.dmSansTextTheme(
    base.textTheme,
  ).copyWith(
    displayLarge:   AppTextStyles.display,
    headlineLarge:  AppTextStyles.display,
    headlineMedium: AppTextStyles.headline,
    titleLarge:     AppTextStyles.headline,
    titleMedium:    AppTextStyles.title,
    bodyLarge:      const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
    bodyMedium:     AppTextStyles.body,
    bodySmall:      AppTextStyles.caption,
    labelLarge:     const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
  );

  /// The single light minimal theme.
  static ThemeData get light => build();

  /// Legacy alias — same minimal theme (kept for existing call sites).
  static ThemeData get glass => build();

  static ThemeData build({
    Color primary = AppColors.primary,
    Color secondary = AppColors.primary,
    VisualDensity visualDensity = VisualDensity.standard,
  }) {
    final base = ThemeData.light();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      visualDensity: visualDensity,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme(
        brightness:    Brightness.light,
        primary:       primary,
        onPrimary:     Colors.white,
        secondary:     secondary,
        onSecondary:   Colors.white,
        error:         AppColors.danger500,
        onError:       Colors.white,
        surface:       AppColors.surface,
        onSurface:     AppColors.textPrimary,
        outline:       AppColors.border,
      ),
      textTheme: _buildTextTheme(base),
      appBarTheme: AppBarTheme(
        backgroundColor:  AppColors.background,
        foregroundColor:  AppColors.textPrimary,
        elevation:        0,
        shadowColor:      Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.danger500),
        ),
        hintStyle: const TextStyle(color: AppColors.gray400, fontSize: 13),
        labelStyle: GoogleFonts.dmSans(
          color: AppColors.gray600, fontWeight: FontWeight.w500, fontSize: 13,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor:            primary,
        unselectedLabelColor:  AppColors.gray500,
        indicatorColor:        primary,
        dividerColor:          AppColors.border,
        labelStyle:            GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:  GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.gray900,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        titleTextStyle: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        contentTextStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : Colors.transparent),
        side: const BorderSide(color: AppColors.gray300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.gray400),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : AppColors.gray200),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.gray500,
        textColor: AppColors.textPrimary,
      ),
    );
  }
}
