import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Bengali-first typography system.
///
/// All styles use **Hind Siliguri** — a font designed specifically for the
/// Bengali script (also covers Devanagari and Latin). Sizes and line-heights
/// are tuned for Bengali rendering (1.4–1.5 height accommodates Bengali's
/// tall matras and descenders).
///
/// Hierarchy:
///   display  → splash/hero text
///   h1 / h2  → page and section titles
///   h3       → card titles, subsection headers
///   bodyLg   → primary body text (default for paragraphs)
///   body     → secondary body, list items
///   bodySm   → supporting text, two-line subtitles
///   labelLg  → button text, prominent labels
///   label    → small labels, chips
///   caption  → meta text, timestamps
///   overline → section dividers, all-caps tags
class AppTextStyles {
  AppTextStyles._();

  // Base font factory. Wraps google_fonts so every style shares one source.
  static TextStyle _hind({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.onBackground,
    double height = 1.4,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.hindSiliguri(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle get display => _hind(size: 32, weight: FontWeight.w700, height: 1.2);
  static TextStyle get h1      => _hind(size: 24, weight: FontWeight.w700, height: 1.25);
  static TextStyle get h2      => _hind(size: 20, weight: FontWeight.w600, height: 1.3);
  static TextStyle get h3      => _hind(size: 17, weight: FontWeight.w600, height: 1.35);

  static TextStyle get bodyLg  => _hind(size: 16, weight: FontWeight.w400, height: 1.5);
  static TextStyle get body    => _hind(size: 15, weight: FontWeight.w400, height: 1.45);
  static TextStyle get bodySm  => _hind(size: 13, weight: FontWeight.w400, height: 1.4, color: AppColors.textSecondary);

  static TextStyle get labelLg => _hind(size: 15, weight: FontWeight.w600, height: 1.3);
  static TextStyle get label   => _hind(size: 13, weight: FontWeight.w600, height: 1.3);

  static TextStyle get caption => _hind(size: 12, weight: FontWeight.w500, height: 1.3, color: AppColors.textSecondary);
  static TextStyle get overline => _hind(size: 11, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.6, color: AppColors.textSecondary);

  // Returns the full Material TextTheme so ThemeData inherits everything.
  static TextTheme get textTheme => TextTheme(
        displayLarge:  display,
        displayMedium: display.copyWith(fontSize: 28),
        displaySmall:  h1,
        headlineLarge: h1,
        headlineMedium: h2,
        headlineSmall: h3,
        titleLarge:    h2,
        titleMedium:   h3,
        titleSmall:    labelLg,
        bodyLarge:     bodyLg,
        bodyMedium:    body,
        bodySmall:     bodySm,
        labelLarge:    labelLg,
        labelMedium:   label,
        labelSmall:    caption,
      );

  // ── Legacy aliases (keep existing call sites compiling during migration) ──
  static TextStyle get button => labelLg.copyWith(color: AppColors.onPrimary);
}
