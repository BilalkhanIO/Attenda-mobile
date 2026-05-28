import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Attenda Color Tokens ─────────────────────────────
class AppColors {
  static const primary600  = Color(0xFFF15153); // Imperial Red
  static const primary100  = Color(0xFFFDE8E8);
  static const primary900  = Color(0xFFB91C1E);
  static const dark950     = Color(0xFF321847); // Violet
  static const dark800     = Color(0xFF4A2466);
  static const dark700     = Color(0xFF5E2E7A);
  static const gray500     = Color(0xFF64748B);
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
}

// ─── Status colors ────────────────────────────────────
class StatusColors {
  static Color bg(String status) {
    switch (status) {
      case 'in':     return AppColors.success100;
      case 'late':   return AppColors.warning100;
      case 'absent': return AppColors.danger100;
      case 'remote': return AppColors.purple100;
      case 'leave':  return AppColors.primary100;
      default:       return AppColors.gray100;
    }
  }
  static Color fg(String status) {
    switch (status) {
      case 'in':     return AppColors.success700;
      case 'late':   return AppColors.warning800;
      case 'absent': return AppColors.danger800;
      case 'remote': return AppColors.purple700;
      case 'leave':  return AppColors.primary600;
      default:       return AppColors.gray500;
    }
  }
  static String label(String status) {
    switch (status) {
      case 'in':     return 'Checked In';
      case 'out':    return 'Checked Out';
      case 'late':   return 'Late';
      case 'absent': return 'Absent';
      case 'remote': return 'Remote';
      case 'leave':  return 'On Leave';
      default:       return status;
    }
  }
  static IconData icon(String status) {
    switch (status) {
      case 'in':     return Icons.check_circle;
      case 'out':    return Icons.logout;
      case 'late':   return Icons.warning_rounded;
      case 'absent': return Icons.cancel;
      case 'remote': return Icons.home_rounded;
      case 'leave':  return Icons.calendar_today;
      default:       return Icons.help_outline;
    }
  }
}

// ─── Theme ────────────────────────────────────────────
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
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.dark950,
        side: const BorderSide(color: AppColors.gray200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gray200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger500),
      ),
      hintStyle: const TextStyle(color: AppColors.gray500, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.dark800, fontWeight: FontWeight.w600, fontSize: 14),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.primary600,
      unselectedItemColor: AppColors.gray500,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.gray200, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.dark800,
      contentTextStyle: GoogleFonts.dmSans(color: AppColors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
