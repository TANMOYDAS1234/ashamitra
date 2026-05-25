import 'package:flutter/material.dart';

/// Centralised color tokens. Two principles:
///
///   1. **Triage band colors are sacred** — `safeGreen`, `warningYellow`,
///      `emergencyRed` mean "Green / Yellow / Red band" and nothing else.
///      Never reuse them for decorative purposes.
///
///   2. **The primary scale** (primary / primaryDeep / primarySoft) and the
///      **accent scale** (accent / accentDeep / accentSoft) are the
///      app's identity. Use them for everything decorative or interactive.
///
/// The accent is a warm amber that pairs intentionally with the cool indigo
/// primary — a nod to the saffron-and-indigo palette common in Indian
/// civic/health visual identity, without copying the flag literally.
class AppColors {
  AppColors._();

  // ── Primary scale (indigo) ───────────────────────────────────────────────
  static const primary     = Color(0xFF4F46E5); // indigo-600 — buttons, links, active state
  static const primaryDeep = Color(0xFF3730A3); // indigo-800 — emphasis on dark
  static const primarySoft = Color(0xFFEEF2FF); // indigo-50  — quiet fills, focus halos

  // ── Accent scale (warm amber) ────────────────────────────────────────────
  static const accent     = Color(0xFFD97706); // amber-600 — warm highlights, callouts
  static const accentDeep = Color(0xFF92400E); // amber-800 — emphasis
  static const accentSoft = Color(0xFFFEF3C7); // amber-100 — soft fills

  // ── Secondary cool tones (used for case differentiation, not identity) ───
  static const purple = Color(0xFF8B5CF6);
  static const sky    = Color(0xFF06B6D4);

  // ── Triage band colors — DO NOT reuse outside clinical context ───────────
  static const safeGreen      = Color(0xFF22C55E);
  static const warningYellow  = Color(0xFFFACC15);
  static const emergencyRed   = Color(0xFFEF4444);

  // ── Neutrals / surfaces ──────────────────────────────────────────────────
  static const background     = Color(0xFFF7F8FF); // page background (cool tint)
  static const surface        = Color(0xFFFFFFFF); // cards, sheets
  static const surfaceMuted   = Color(0xFFFAFAF9); // nested surfaces (warm off-white)
  static const onPrimary      = Color(0xFFFFFFFF);
  static const onBackground   = Color(0xFF1E1B4B); // deep indigo-near-black, soft on eyes
  static const textSecondary  = Color(0xFF6B7280);
  static const textLight      = Color(0xFF9CA3AF);
  static const cardBorder     = Color(0xFFE0E7FF);

  // ── Legacy aliases (kept so older code keeps compiling) ──────────────────
  static const secondary = safeGreen;
  static const error     = emergencyRed;
  static const warning   = warningYellow;
}
