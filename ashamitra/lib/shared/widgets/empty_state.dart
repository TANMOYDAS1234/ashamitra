import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A consistent, illustrated empty-state. Two concentric tinted circles
/// behind a centred icon, then title + subtitle, then an optional CTA.
/// Fades and lifts in on first render.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 16),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Layered icon — outer halo + inner disc + icon
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Icon(icon, size: 44, color: c),
                    // Decorative dots arranged like sparkle marks
                    Positioned(
                      top: 8,
                      right: 22,
                      child: _Dot(color: c, size: 6, opacity: 0.50),
                    ),
                    Positioned(
                      bottom: 18,
                      left: 18,
                      child: _Dot(color: c, size: 4, opacity: 0.35),
                    ),
                    Positioned(
                      top: 30,
                      left: 10,
                      child: _Dot(color: c, size: 5, opacity: 0.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: AppTextStyles.h3),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _Dot({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      );
}
