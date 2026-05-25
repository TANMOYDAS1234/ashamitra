import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/emergency_button.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  Future<void> _call(String number) async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      Get.snackbar('Error', 'Cannot open dialer', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _openMaps(String query) async {
    final uri = Uri.parse('geo:0,0?q=${Uri.encodeComponent(query)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      Get.snackbar('Error', 'Cannot open maps', snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ── Capture and share the patient's GPS so the ambulance can find them ────
  Future<void> _sharePatientLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      Get.snackbar('লোকেশন বন্ধ', 'ফোনের GPS / লোকেশন চালু করুন',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      Get.snackbar('অনুমতি দরকার', 'অ্যাপকে লোকেশন অনুমতি দিন',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    Get.dialog(
      const Center(child: CircularProgressIndicator(color: Colors.white)),
      barrierDismissible: false,
    );
    try {
      final pos = await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 20));
      if (Get.isDialogOpen ?? false) Get.back();
      Get.dialog(_locationDialog(pos.latitude, pos.longitude));
    } catch (_) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('ব্যর্থ', 'অবস্থান পাওয়া যায়নি — আবার চেষ্টা করুন',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Widget _locationDialog(double lat, double lng) {
    final coords = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    final shareLink = 'https://maps.google.com/?q=$lat,$lng';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
      title: Text('রোগীর অবস্থান', style: AppTextStyles.h2),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'এই অবস্থান অ্যাম্বুলেন্স বা সুপারভাইজারকে পাঠান:',
            style: AppTextStyles.bodySm,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: AppRadius.mdR,
            ),
            child: Text(coords, style: AppTextStyles.h3),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shareLink));
            Get.back();
            Get.snackbar('কপি হয়েছে', 'লোকেশন লিঙ্ক কপি হয়েছে',
                snackPosition: SnackPosition.BOTTOM);
          },
          child: const Text('লিঙ্ক কপি করুন'),
        ),
        TextButton(
          onPressed: () {
            Get.back();
            _openMaps('$lat,$lng');
          },
          child: const Text('ম্যাপে দেখুন'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.emergency),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () => Get.back(),
                            customBorder: const CircleBorder(),
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(Icons.arrow_back_ios_new_rounded,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'emergency_title'.tr,
                          style: AppTextStyles.h2.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Icon(Icons.emergency_rounded, size: 56, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      'emergency_subtitle'.tr,
                      style: AppTextStyles.bodyLg.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'emergency_conditions'.tr,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySm.copyWith(color: Colors.white.withValues(alpha: 0.70)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: Container(
                  color: AppColors.background,
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Column(
                        children: [
                          EmergencyButton(
                            icon: Icons.emergency_rounded,
                            label: 'call_ambulance'.tr,
                            subtitle: 'call_ambulance_desc'.tr,
                            onTap: () => _call('102'),
                          ),
                          const SizedBox(height: 12),
                          EmergencyButton(
                            icon: Icons.share_location_rounded,
                            label: 'share_location'.tr,
                            subtitle: 'share_location_desc'.tr,
                            color: AppColors.primary,
                            onTap: _sharePatientLocation,
                          ),
                          const SizedBox(height: 12),
                          EmergencyButton(
                            icon: Icons.person_outline_rounded,
                            label: 'call_anm'.tr,
                            subtitle: 'call_anm_desc'.tr,
                            color: AppColors.purple,
                            onTap: () => _call('18001801104'),
                          ),
                          const SizedBox(height: 12),
                          EmergencyButton(
                            icon: Icons.local_hospital_rounded,
                            label: 'call_health'.tr,
                            subtitle: 'call_health_desc'.tr,
                            color: AppColors.sky,
                            onTap: () => _call('104'),
                          ),
                          const SizedBox(height: 12),
                          EmergencyButton(
                            icon: Icons.navigation_rounded,
                            label: 'navigate_chc'.tr,
                            subtitle: 'navigate_chc_desc'.tr,
                            color: AppColors.safeGreen,
                            onTap: () => _openMaps('Community Health Centre near me'),
                          ),
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () => Get.offAllNamed(AppRoutes.home),
                            child: Text(
                              'back_to_home'.tr,
                              style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
