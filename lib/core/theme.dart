import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان مدار (Coolors "Fiery") + درجات محايدة دافية
class MC {
  static const plum = Color(0xFF5F0F40);
  static const plumDeep = Color(0xFF4A0A31);
  static const crimson = Color(0xFF9A031E);
  static const orange = Color(0xFFFB8B24);
  static const burnt = Color(0xFFE36414);
  static const burntText = Color(0xFFB04A0A);
  static const teal = Color(0xFF0F4C5C);

  static const ink = Color(0xFF22101C);
  static const inkSoft = Color(0xFF3A1D30);
  static const ground = Color(0xFFFAF5EF);
  static const groundDeep = Color(0xFFF2E8DF);
  static const line = Color(0xFFE8DCD2);
  static const track = Color(0xFFEADFD5);
  static const muted = Color(0xFF6E5A66);
  static const mutedDeep = Color(0xFF5B4652);
  static const onDarkMuted = Color(0xFFC9B3BF);

  // شرائح الحالة
  static const orangeTint = Color(0xFFFDEBD9);
  static const tealTint = Color(0xFFE3F0EC);
  static const crimsonTint = Color(0xFFF9E1E4);
  static const plumTint = Color(0xFFEFE8EC);
  static const success = Color(0xFF3FB98F);

  // السوبر أدمن (تيل)
  static const adminRail = Color(0xFF0B2F38);
  static const adminGround = Color(0xFFF4F7F6);
  static const adminLine = Color(0xFFD6E2E0);
  static const adminMuted = Color(0xFF4E6A70);
  static const adminInk = Color(0xFF10242A);
  static const adminOnDark = Color(0xFF9EC3C9);
  static const adminTrack = Color(0xFFDCE7E5);
}

/// خط الأرقام والعناوين
TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color, double? letterSpacing}) =>
    GoogleFonts.readexPro(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing ?? (size >= 28 ? -0.6 : 0),
      height: 1.15,
    );

ThemeData buildTheme({Color ground = MC.ground, Color ink = MC.ink, Color primary = MC.plum}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: MC.burnt,
      error: MC.crimson,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: ground,
  );
  final text = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);
  final radius = BorderRadius.circular(12);
  return base.copyWith(
    textTheme: text,
    dividerColor: MC.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MC.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MC.line)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: MC.crimson, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(44, 46),
        side: const BorderSide(color: MC.onDarkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(44, 44),
        textStyle: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
