import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../app/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text_styles.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  const BottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppShadows.high,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'home'.tr,
                selected: currentIndex == 0,
                onTap: () => Get.offAllNamed(AppRoutes.home),
              ),
              _NavItem(
                icon: Icons.people_alt_rounded,
                label: 'patients'.tr,
                selected: currentIndex == 1,
                onTap: () => Get.offAllNamed(AppRoutes.patientList),
              ),
              _VoiceNavItem(onTap: () => Get.toNamed(AppRoutes.assistant)),
              _NavItem(
                icon: Icons.bar_chart_rounded,
                label: 'reports'.tr,
                selected: currentIndex == 3,
                onTap: () => Get.offAllNamed(AppRoutes.reports),
              ),
              _NavItem(
                icon: Icons.person_rounded,
                label: 'profile'.tr,
                selected: currentIndex == 4,
                onTap: () => Get.offAllNamed(AppRoutes.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : const Color(0xFF9CA3AF);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdR,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated pill behind active icon — soft indigo→accent gradient on active.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.14),
                              AppColors.accent.withValues(alpha: 0.10),
                            ],
                          )
                        : null,
                    borderRadius: AppRadius.pillR,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceNavItem extends StatelessWidget {
  final VoidCallback onTap;
  const _VoiceNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Material(
          shape: const CircleBorder(),
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.purple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: AppShadows.tinted(AppColors.primary, strength: 2),
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
