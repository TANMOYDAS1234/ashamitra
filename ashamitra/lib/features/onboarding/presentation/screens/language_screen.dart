import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/services/language_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/app_button.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  static const _languages = [
    ('বাংলা', 'Bengali'),
    ('हिन्दी', 'Hindi'),
    ('English', 'English'),
  ];

  static const _langColors = [
    Color(0xFF4F46E5), // indigo — Bengali
    Color(0xFFE85D04), // saffron — Hindi
    Color(0xFF0891B2), // teal — English
  ];

  static const _langAbbr = ['বা', 'हि', 'En'];

  @override
  Widget build(BuildContext context) {
    final lang = Get.find<LanguageController>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                Text('select_language_subtitle'.tr, style: AppTextStyles.bodySm),
                const SizedBox(height: 8),
                Text(
                  'select_language'.tr,
                  style: AppTextStyles.display.copyWith(fontSize: 30),
                ),
                const SizedBox(height: 40),
                Obx(() => Column(
                      children: List.generate(_languages.length, (i) {
                        final (name, subName) = _languages[i];
                        final isSelected = i == lang.selectedIndex.value;
                        final accent = _langColors[i];
                        final abbr = _langAbbr[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Material(
                            color: isSelected ? accent : AppColors.surface,
                            borderRadius: AppRadius.xlR,
                            child: InkWell(
                              onTap: () => lang.setLanguage(i),
                              borderRadius: AppRadius.xlR,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                decoration: BoxDecoration(
                                  color: isSelected ? accent : AppColors.surface,
                                  borderRadius: AppRadius.xlR,
                                  boxShadow: isSelected
                                      ? AppShadows.tinted(accent, strength: 2)
                                      : AppShadows.low,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.20)
                                            : accent.withValues(alpha: 0.10),
                                        borderRadius: AppRadius.mdR,
                                      ),
                                      child: Center(
                                        child: Text(
                                          abbr,
                                          style: AppTextStyles.h3.copyWith(
                                            color: isSelected ? Colors.white : accent,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: AppTextStyles.h2.copyWith(
                                            color: isSelected ? Colors.white : AppColors.onBackground,
                                          ),
                                        ),
                                        Text(
                                          subName,
                                          style: AppTextStyles.bodySm.copyWith(
                                            color: isSelected
                                                ? Colors.white.withValues(alpha: 0.80)
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    if (isSelected)
                                      const Icon(Icons.check_circle_rounded,
                                          color: Colors.white, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    )),
                const Spacer(),
                AppButton(
                  label: 'continue'.tr,
                  onPressed: () => Get.offNamed(AppRoutes.welcome),
                  icon: Icons.arrow_forward_rounded,
                  width: double.infinity,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
