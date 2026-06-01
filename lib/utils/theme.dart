import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Attenda Color Tokens ─────────────────────────────
class AppColors {
  static const primary600  = Color(0xFFF15153);
  static const primary100  = Color(0xFFFDE8E8);
  static const primary900  = Color(0xFFB91C1E);
  static const dark950     = Color(0xFF321847);
  static const dark800     = Color(0xFF4A2466);
  static const dark700     = Color(0xFF5E2E7A);
  static const gray500     = Color(0xFF64748B);
  static const gray400     = Color(0xFF94A3B8);
  static const gray200     = Color(0xFFE2E8F0);
  static const gray100     = Color(0xFFF1F5F9);
  static const gray50      = Color(0xFFF8FAFC);
  static const success700  = Color(0xFF065F46);
  static const success500  = Color(0xFF10B981);
  static const success100  = Color(0xFFD1FAE5);
  static const warning800  = Color(0xFF92400E);
  static const warning500  = Color(0xFFF59E0B);
  static const warning100  = Color(0xFFFEF3C7);
  static const danger800   = Color(0xFF991B1B);
  static const danger500   = Color(0xFFEF4444);
  static const danger100   = Color(0xFFFEE2E2);
  static const purple700   = Color(0xFF5B21B6);
  static const purple500   = Color(0xFF8B5CF6);
  static const purple100   = Color(0xFFEDE9FE);
  static const teal700     = Color(0xFF0F766E);
  static const teal100     = Color(0xFFCCFBF1);
  static const white       = Color(0xFFFFFFFF);

  // Glass surface tokens
  static const glass05     = Color(0x0DFFFFFF);
  static const glass10     = Color(0x1AFFFFFF);
  static const glass15     = Color(0x26FFFFFF);
  static const glass20     = Color(0x33FFFFFF);
  static const glassBorder = Color(0x40FFFFFF);
  static const glassHigh   = Color(0x5AFFFFFF);

  // Glass text tokens
  static const onGlass     = Colors.white;
  static const onGlassSub  = Color(0xCCFFFFFF); // 80%
  static const onGlassMuted= Color(0x99FFFFFF); // 60%
  static const onGlassDim  = Color(0x55FFFFFF); // 33%

  // Mesh background colors
  static const meshTop     = Color(0xFF2D1952);
  static const meshMid     = Color(0xFF1A0E38);
  static const meshBot     = Color(0xFF0D0724);
}

// ─── Background Gradients ────────────────────────────
class AppGradients {
  static const mesh = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.meshTop, AppColors.meshMid, AppColors.meshBot],
    stops: [0.0, 0.55, 1.0],
  );

  static const primaryBtn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6D), Color(0xFFF15153)],
  );

  static const glassCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2EFFFFFF), Color(0x0DFFFFFF)],
  );
}

// ─── Status colors ────────────────────────────────────
class StatusColors {
  static Color bg(String status) {
    switch (status) {
      case 'in':         return AppColors.success100;
      case 'late':       return AppColors.warning100;
      case 'absent':     return AppColors.danger100;
      case 'remote':     return AppColors.purple100;
      case 'leave':      return AppColors.primary100;
      case 'half_leave': return AppColors.teal100;
      default:           return AppColors.gray100;
    }
  }
  static Color fg(String status) {
    switch (status) {
      case 'in':         return AppColors.success700;
      case 'late':       return AppColors.warning800;
      case 'absent':     return AppColors.danger800;
      case 'remote':     return AppColors.purple700;
      case 'leave':      return AppColors.primary600;
      case 'half_leave': return AppColors.teal700;
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
      case 'half_leave': return 'Half-Day Leave';
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
      case 'leave':      return Icons.calendar_today;
      case 'half_leave': return Icons.calendar_today;
      default:           return Icons.help_outline;
    }
  }
}

// ─── Light Theme (kept for reference) ────────────────
class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.gray50,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary600,
      primary: AppColors.primary600,
      surface: AppColors.white,
      background: AppColors.gray50,
    ),
    textTheme: GoogleFonts.dmSansTextTheme().copyWith(
      displayLarge:   const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.dark950),
      headlineLarge:  const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.dark950),
      headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.dark950),
      titleLarge:     const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.dark950),
      titleMedium:    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.dark950),
      bodyLarge:      const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.dark950),
      bodyMedium:     const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.dark800),
      bodySmall:      const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.gray500),
      labelLarge:     const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.white),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.dark950,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dark950),
    ),
    cardTheme: CardTheme(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gray200),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary600,
        foregroundColor: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gray200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gray200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary600, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger500)),
      hintStyle: const TextStyle(color: AppColors.gray500, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.dark800, fontWeight: FontWeight.w600, fontSize: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.dark800,
      contentTextStyle: GoogleFonts.dmSans(color: AppColors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.gray200, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.primary600,
      unselectedItemColor: AppColors.gray500,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );

  // ─── Glass / Dark Theme ───────────────────────────
  static ThemeData get glass => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.meshBot,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary:    AppColors.primary600,
      onPrimary:  Colors.white,
      secondary:  AppColors.dark700,
      onSecondary:Colors.white,
      error:      AppColors.danger500,
      onError:    Colors.white,
      background: AppColors.meshMid,
      onBackground: Colors.white,
      surface:    Color(0xFF1E1040),
      onSurface:  Colors.white,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge:   const TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: Colors.white),
      headlineLarge:  const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
      headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
      titleLarge:     const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
      titleMedium:    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
      bodyLarge:      const TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: Colors.white),
      bodyMedium:     TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.white.withOpacity(0.8)),
      bodySmall:      TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white.withOpacity(0.6)),
      labelLarge:     const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    cardTheme: CardTheme(
      color: AppColors.glass10,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary600,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withOpacity(0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger500),
      ),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.w600, fontSize: 14),
    ),
    tabBarTheme: TabBarTheme(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withOpacity(0.5),
      indicatorColor: AppColors.primary600,
      dividerColor: Colors.white.withOpacity(0.1),
      labelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF2D1952),
      contentTextStyle: GoogleFonts.dmSans(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withOpacity(0.12), thickness: 1),
    dialogTheme: DialogTheme(
      backgroundColor: const Color(0xFF2A1650),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      contentTextStyle: GoogleFonts.dmSans(fontSize: 14, color: Colors.white70),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1040),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.selected) ? AppColors.primary600 : Colors.transparent),
      side: BorderSide(color: Colors.white.withOpacity(0.4)),
    ),
  );
}
