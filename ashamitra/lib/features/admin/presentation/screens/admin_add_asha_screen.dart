import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/components/app_header.dart';
import '../../../admin/controller/admin_controller.dart';

class AdminAddAshaScreen extends StatefulWidget {
  const AdminAddAshaScreen({super.key});

  @override
  State<AdminAddAshaScreen> createState() => _AdminAddAshaScreenState();
}

class _AdminAddAshaScreenState extends State<AdminAddAshaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _block = TextEditingController();
  final _district = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _block.dispose();
    _district.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final ctrl = Get.find<AdminController>();

    final ok = await ctrl.addAshaWorker(
      phone: _phone.text.trim(),
      name: _name.text.trim(),
      block: _block.text.trim(),
      district: _district.text.trim(),
    );

    setState(() => _saving = false);

    if (ok) {
      Get.back();
      Get.snackbar(
        'admin_success'.tr,
        'admin_add_success'.tr,
        backgroundColor: AppColors.safeGreen,
        colorText: AppColors.onPrimary,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        icon: const Icon(Icons.check_circle_outline_rounded, color: AppColors.onPrimary),
      );
    } else {
      Get.snackbar(
        'admin_add_error'.tr,
        ctrl.errorMsg.value,
        backgroundColor: AppColors.emergencyRed,
        colorText: AppColors.onPrimary,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        icon: const Icon(Icons.error_outline_rounded, color: AppColors.onPrimary),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(title: 'admin_add_asha'.tr),

              // ── Form Area ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Container Card grouping form elements elegantly
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.xxlR,
                            boxShadow: AppShadows.mid,
                          ),
                          child: Column(
                            children: [
                              _field(
                                ctrl: _name,
                                label: 'admin_full_name'.tr,
                                icon: Icons.person_outline_rounded,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'admin_name_required'.tr;
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              _field(
                                ctrl: _phone,
                                label: 'admin_phone'.tr,
                                icon: Icons.phone_android_rounded,
                                keyboardType: TextInputType.phone,
                                validator: (v) {
                                  if (v == null || v.trim().length < 10) return 'admin_phone_required'.tr;
                                  return null;
                                },
                              ),
                              const SizedBox(height: 18),
                              _field(ctrl: _block, label: 'admin_block'.tr, icon: Icons.location_on_outlined),
                              const SizedBox(height: 18),
                              _field(ctrl: _district, label: 'admin_district'.tr, icon: Icons.map_outlined),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── Submit Button ──────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                              elevation: 0,
                              shadowColor: AppColors.primary.withValues(alpha: 0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.lgR,
                              ),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: AppColors.onPrimary,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    'admin_save'.tr,
                                    style: AppTextStyles.labelLg.copyWith(
                                      color: AppColors.onPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Modularized Form Field Method ─────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        floatingLabelStyle: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        prefixIcon: Icon(
          icon,
          color: AppColors.primary.withValues(alpha: 0.8),
          size: 22,
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC), // Ultra-light grey for form depth
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.emergencyRed, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.lgR,
          borderSide: const BorderSide(color: AppColors.emergencyRed, width: 1.8),
        ),
        errorStyle: AppTextStyles.caption.copyWith(
          color: AppColors.emergencyRed,
        ),
      ),
    );
  }
}
