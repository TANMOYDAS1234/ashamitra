import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/language_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/components/bottom_nav.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/controller/auth_controller.dart';
import '../../../patients/controller/patient_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final auth = Get.find<AuthController>();
    try {
      final img = await _picker.pickImage(source: source, imageQuality: 80);
      if (img != null) auth.updateProfileImage(img.path);
    } catch (_) {}
  }

  Future<void> _callSupervisor() async {
    final uri = Uri.parse('tel:18001801104');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _showFullImage() {
    final auth = Get.find<AuthController>();
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: Hero(
                  tag: 'profile_image',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: UserAvatar(
                      user: auth.user.value,
                      size: MediaQuery.of(context).size.width * 0.85,
                      backgroundColor: Colors.white24,
                      textColor: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 48, right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhotoOptions() {
    final auth = Get.find<AuthController>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              Obx(() => auth.user.value?.profileImagePath != null
                  ? ListTile(
                      leading: const Icon(Icons.delete_outline_rounded,
                          color: AppColors.emergencyRed),
                      title: const Text('Remove Photo',
                          style: TextStyle(color: AppColors.emergencyRed)),
                      onTap: () {
                        auth.updateProfileImage(null);
                        Navigator.of(ctx).pop();
                      },
                    )
                  : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    final lang = Get.find<LanguageController>();
    showDialog(
      context: context,
      builder: (_) => Obx(() => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('change_language'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(LanguageController.labels.length, (i) {
                final selected = lang.selectedIndex.value == i;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  title: Text(
                    LanguageController.labels[i],
                    style: TextStyle(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
                  ),
                  onTap: () {
                    lang.setLanguage(i);
                    Get.back();
                  },
                );
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: Text('cancel'.tr,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          )),
    );
  }

  void _showEditProfile() {
    final auth = Get.find<AuthController>();
    final nameCtrl = TextEditingController(text: auth.user.value?.name ?? '');
    final blockCtrl = TextEditingController(text: auth.user.value?.block ?? '');
    final districtCtrl =
        TextEditingController(text: auth.user.value?.district ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('edit_profile'.tr,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onBackground)),
            const SizedBox(height: 20),
            _Field(
                controller: nameCtrl,
                label: 'full_name'.tr,
                icon: Icons.person_rounded),
            const SizedBox(height: 14),
            _Field(
                controller: blockCtrl,
                label: 'block'.tr,
                icon: Icons.location_on_rounded),
            const SizedBox(height: 14),
            _Field(
                controller: districtCtrl,
                label: 'district'.tr,
                icon: Icons.map_rounded),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  await auth.updateProfile(
                    name: nameCtrl.text.trim(),
                    block: blockCtrl.text.trim(),
                    district: districtCtrl.text.trim(),
                  );
                  Get.back();
                  Get.snackbar(
                    'profile_updated'.tr,
                    'profile_updated_msg'.tr,
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: AppColors.safeGreen,
                    colorText: Colors.white,
                    margin: const EdgeInsets.all(16),
                    borderRadius: 12,
                  );
                },
                child: Text('save_changes'.tr,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('help_guide'.tr,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onBackground)),
            const SizedBox(height: 16),
            ...['🎙️', '👆', '🚨', '📋', '📊']
                .asMap()
                .entries
                .map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value,
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  'help_tip${e.key + 1}'.tr,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                      height: 1.4))),
                        ],
                      ),
                    )),
          ],
        ),
      ),
    );
  }

  void _syncData() async {
    Get.snackbar('syncing'.tr, 'syncing_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.primary,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 1));
    await Get.find<PatientController>().syncFromServer();
    Get.snackbar('sync_complete'.tr, 'sync_complete_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.safeGreen,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12);
  }

  void _toggleNotifications() {
    Get.snackbar('notifications_updated'.tr, 'notifications_updated_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.primary.withOpacity(0.9),
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final lang = Get.find<LanguageController>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                decoration: const BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(30)),
                ),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Obx(() {
                          final u = auth.user.value;
                          return GestureDetector(
                            onLongPress: u?.profileImagePath != null
                                ? () => _showFullImage()
                                : null,
                            child: Hero(
                              tag: 'profile_image',
                              child: UserAvatar(
                                user: u,
                                size: 74,
                                backgroundColor: Colors.white24,
                                textColor: Colors.white,
                              ),
                            ),
                          );
                        }),
                        GestureDetector(
                          onTap: () => _showPhotoOptions(),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.edit_rounded,
                                color: AppColors.primary, size: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Obx(() => Text(
                          auth.user.value?.name ?? 'ASHA Worker',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h2.copyWith(color: Colors.white),
                        )),
                    const SizedBox(height: 6),
                    Obx(() {
                      final id = auth.user.value?.id ?? '';
                      final shortId = id.length > 8 ? id.substring(id.length - 8).toUpperCase() : id.toUpperCase();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          borderRadius: AppRadius.pillR,
                        ),
                        child: Text(
                          'ID: ASHA-$shortId',
                          style: AppTextStyles.caption.copyWith(color: Colors.white),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Obx(() => _Section(title: 'my_details'.tr, items: [
                            _InfoRow(Icons.location_on_rounded, 'block'.tr,
                                auth.user.value?.block ?? 'Basirhat'),
                            _InfoRow(Icons.map_rounded, 'district'.tr,
                                auth.user.value?.district ?? 'North 24 Parganas'),
                            _InfoRow(Icons.translate_rounded, 'language'.tr,
                                lang.currentLabel),
                            _InfoRow(Icons.sync_rounded, 'offline_sync'.tr,
                                'last_synced'.tr),
                          ])),
                      const SizedBox(height: 16),
                      _Section(title: 'settings'.tr, items: [
                        _ActionRow(Icons.edit_rounded, 'edit_profile'.tr,
                            () => _showEditProfile()),
                        _ActionRow(Icons.notifications_rounded,
                            'notifications'.tr, _toggleNotifications),
                        _ActionRow(Icons.language_rounded, 'change_language'.tr,
                            () => _showLanguageDialog()),
                        _ActionRow(Icons.cloud_download_rounded, 'sync_data'.tr,
                            _syncData),
                      ]),
                      const SizedBox(height: 16),
                      _Section(title: 'support'.tr, items: [
                        _ActionRow(Icons.help_outline_rounded, 'help_guide'.tr,
                            () => _showHelpSheet()),
                        _ActionRow(Icons.phone_in_talk_rounded,
                            'contact_supervisor'.tr, _callSupervisor),
                      ]),
                      const SizedBox(height: 16),
                      Material(
                        color: AppColors.emergencyRed.withValues(alpha: 0.08),
                        borderRadius: AppRadius.lgR,
                        child: InkWell(
                          onTap: () => auth.logout(),
                          borderRadius: AppRadius.lgR,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.logout_rounded,
                                    color: AppColors.emergencyRed, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'logout'.tr,
                                  style: AppTextStyles.labelLg.copyWith(color: AppColors.emergencyRed),
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 4),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  const _Field({required this.controller, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(), style: AppTextStyles.overline),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgR,
            boxShadow: AppShadows.low,
          ),
          child: Column(children: items),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Text(label, style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          const Spacer(),
          Text(value, style: AppTextStyles.labelLg),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionRow(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgR,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(label, style: AppTextStyles.body),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
