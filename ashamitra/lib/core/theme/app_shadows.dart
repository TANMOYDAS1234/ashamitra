import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Three-tier elevation system. Use these instead of ad-hoc BoxShadow lists.
///
///   low   — resting cards, default surfaces
///   mid   — interactive cards (tappable lists, dashboard tiles)
///   high  — floating elements (FAB, bottom sheets, popovers)
///
/// `tinted(color)` returns a colored shadow for branded surfaces (e.g. a
/// red emergency card with a faint red glow). Use sparingly — only on
/// surfaces that benefit from spatial color spill.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get low => [
        BoxShadow(
          color: AppColors.onBackground.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get mid => [
        BoxShadow(
          color: AppColors.onBackground.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get high => [
        BoxShadow(
          color: AppColors.onBackground.withValues(alpha: 0.10),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// Branded shadow — used for cards that should glow in their accent color.
  /// Pass `strength` 1 for subtle, 2 for prominent.
  static List<BoxShadow> tinted(Color color, {int strength = 1}) {
    final alpha = strength == 2 ? 0.18 : 0.10;
    return [
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: strength == 2 ? 16 : 10,
        offset: const Offset(0, 4),
      ),
    ];
  }
}
