import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/auth_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/app_button.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _ctrl = Get.find<AuthController>();
  late final String _phone;
  String? _pilotOtp;
  final List<TextEditingController> _boxes =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      _phone    = args['phone']?.toString()    ?? '';
      _pilotOtp = args['pilotOtp']?.toString();
    } else {
      _phone    = args?.toString() ?? '';
      _pilotOtp = null;
    }
    if (_pilotOtp != null && _pilotOtp!.length == 6) {
      for (int i = 0; i < 6; i++) {
        _boxes[i].text = _pilotOtp![i];
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _otp => _boxes.map((c) => c.text).join();

  void _onBoxChanged(int index, String val) {
    if (val.isNotEmpty && index < 5) _nodes[index + 1].requestFocus();
    if (val.isEmpty && index > 0) _nodes[index - 1].requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Get.back(),
                      customBorder: const CircleBorder(),
                      child: Ink(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.low,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18, color: AppColors.onBackground),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.sms_rounded, size: 34, color: AppColors.primary),
                ),
                const SizedBox(height: 18),
                Text('otp_title'.tr, style: AppTextStyles.h1),
                const SizedBox(height: 6),
                Text(
                  'otp_subtitle'.trParams({'phone': _phone}),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                // ── Pilot mode OTP banner ────────────────────────────────
                if (_pilotOtp != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: AppRadius.lgR,
                      border: Border.all(color: const Color(0xFFD97706)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_rounded, color: Color(0xFFD97706), size: 20),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PILOT MODE — OTP',
                              style: AppTextStyles.overline.copyWith(color: const Color(0xFF92400E)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _pilotOtp!,
                              style: AppTextStyles.display.copyWith(
                                fontSize: 28,
                                color: const Color(0xFF92400E),
                                letterSpacing: 8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.xlR,
                    boxShadow: AppShadows.mid,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: List.generate(
                          6,
                          (i) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                              child: _OtpBox(
                                controller: _boxes[i],
                                focusNode: _nodes[i],
                                onChanged: (val) => _onBoxChanged(i, val),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Obx(() => AppButton(
                            label: 'verify_otp'.tr,
                            onPressed: _otp.length == 6
                                ? () => _ctrl.verifyOtp(_phone, _otp)
                                : null,
                            isLoading: _ctrl.isLoading.value,
                            width: double.infinity,
                          )),
                      const SizedBox(height: 8),
                      Obx(() {
                        if (_ctrl.errorMsg.value.isEmpty) return const SizedBox.shrink();
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEB),
                            borderRadius: AppRadius.mdR,
                            border: Border.all(color: AppColors.emergencyRed.withValues(alpha: 0.40)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 16, color: AppColors.emergencyRed),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _ctrl.errorMsg.value,
                                  style: AppTextStyles.bodySm.copyWith(color: AppColors.emergencyRed),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      Obx(() => TextButton(
                            onPressed: _ctrl.isLoading.value
                                ? null
                                : () async {
                                    _ctrl.errorMsg.value = '';
                                    await _ctrl.login(_phone);
                                    if (_ctrl.errorMsg.value.isEmpty) {
                                      Get.snackbar(
                                        'OTP পাঠানো হয়েছে',
                                        '$_phone নম্বরে নতুন OTP পাঠানো হয়েছে।',
                                        snackPosition: SnackPosition.BOTTOM,
                                        backgroundColor: AppColors.safeGreen,
                                        colorText: Colors.white,
                                        margin: const EdgeInsets.all(16),
                                        borderRadius: 12,
                                        duration: const Duration(seconds: 3),
                                      );
                                    }
                                  },
                            child: Text('resend_otp'.tr),
                          )),
                    ],
                  ),
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

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLength: 1,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        style: AppTextStyles.h2,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: const Color(0xFFF5F7FF),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mdR,
            borderSide: const BorderSide(color: Color(0xFFE0E7FF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mdR,
            borderSide: const BorderSide(color: Color(0xFFE0E7FF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.mdR,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
