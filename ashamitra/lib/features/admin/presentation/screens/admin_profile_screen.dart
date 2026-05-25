import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/language_controller.dart';
import '../../../../shared/components/app_header.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/controller/auth_controller.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _auth = Get.find<AuthController>();
  final _lang = Get.find<LanguageController>();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _block;
  late final TextEditingController _district;

  bool _saving = false;
  String? _successMsg;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final u = _auth.user.value;
    _name     = TextEditingController(text: u?.name     ?? '');
    _block    = TextEditingController(text: u?.block    ?? '');
    _district = TextEditingController(text: u?.district ?? '');
  }

  @override
  void dispose() {
    _name.dispose(); _block.dispose();
    _district.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _successMsg = null; _errorMsg = null; });
    try {
      await _auth.updateProfile(
        name:     _name.text.trim(),
        block:    _block.text.trim(),
        district: _district.text.trim(),
      );
      if (!mounted) return;
      setState(() { _successMsg = 'profile_updated_msg'.tr; _saving = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMsg = 'Error: $e'; _saving = false; });
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
              AppHeader(title: 'admin_profile_title'.tr),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    children: [
                      _avatarCard(),
                      const SizedBox(height: 16),
                      _editCard(),
                      const SizedBox(height: 16),
                      _languageCard(),
                      const SizedBox(height: 16),
                      _logoutCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    _auth.updateProfileImage(picked.path);
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    _auth.updateProfileImage(picked.path);
  }

  void _showPhotoOptions() {
    final hasPhoto = _auth.user.value?.profileImagePath != null;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smR,
                ),
                child: const Icon(Icons.photo_library_rounded, color: AppColors.primary, size: 20),
              ),
              title: Text('গ্যালারি থেকে বেছে নিন',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              onTap: () { Get.back(); _pickPhoto(); },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sky.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smR,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: AppColors.sky, size: 20),
              ),
              title: Text('ক্যামেরা দিয়ে তুলুন',
                  style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              onTap: () { Get.back(); _takePhoto(); },
            ),
            if (hasPhoto) ...[
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.emergencyRed.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smR,
                  ),
                  child: const Icon(Icons.delete_rounded, color: AppColors.emergencyRed, size: 20),
                ),
                title: Text('ছবি সরিয়ে দিন',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.emergencyRed,
                    )),
                onTap: () { Get.back(); _auth.updateProfileImage(null); },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _viewPhoto(String path) {
    final u = _auth.user.value;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Hero(
              tag: 'admin_photo',
              child: ClipRRect(
                borderRadius: AppRadius.lgR,
                child: UserAvatar(
                  user: u,
                  size: MediaQuery.of(context).size.width * 0.85,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  textColor: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _avatarCard() => Obx(() {
        final u = _auth.user.value;
        final name = u?.name ?? '';
        final photoPath = u?.profileImagePath;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecor(),
          child: Row(
            children: [
              // ── Photo with tap/long-press ──────────────────────
              GestureDetector(
                onTap: _showPhotoOptions,
                onLongPress: photoPath != null ? () => _viewPhoto(photoPath) : null,
                child: Hero(
                  tag: 'admin_photo',
                  child: Stack(
                    children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: UserAvatar(
                          user: u,
                          size: 72,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          textColor: AppColors.primary,
                        ),
                      ),
                      // Camera badge
                      Positioned(
                        right: 0, bottom: 0,
                        child: Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surface, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 12, color: AppColors.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isNotEmpty ? name : 'Admin User',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3),
                    const SizedBox(height: 4),
                    Text(u?.phone ?? '',
                        style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: AppRadius.smR,
                          ),
                          child: Text('Admin',
                              style: AppTextStyles.overline.copyWith(color: AppColors.primary)),
                        ),
                        if (photoPath != null) ...[
                          const SizedBox(width: 6),
                          Text('ছবি ধরে রাখুন দেখতে',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary.withValues(alpha: 0.7),
                              )),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      });

  Widget _editCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('admin_edit_info'.tr, style: AppTextStyles.label),
              const SizedBox(height: 16),
              _field(_name, 'admin_full_name'.tr, Icons.person_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'admin_name_required'.tr : null),
              const SizedBox(height: 12),
              _field(_block, 'admin_block'.tr, Icons.location_on_rounded),
              const SizedBox(height: 12),
              _field(_district, 'admin_district'.tr, Icons.map_rounded),
              const SizedBox(height: 16),
              if (_successMsg != null) _banner(_successMsg!, AppColors.safeGreen),
              if (_errorMsg != null) _banner(_errorMsg!, AppColors.emergencyRed),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary,
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                      : Text('admin_save'.tr, style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _languageCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecor(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.language_rounded, color: AppColors.sky, size: 18),
              const SizedBox(width: 8),
              Text('admin_language'.tr, style: AppTextStyles.label),
            ]),
            const SizedBox(height: 14),
            Obx(() => Column(
                  children: List.generate(LanguageController.labels.length, (i) {
                    final selected = _lang.selectedIndex.value == i;
                    final badge = i == 0 ? 'বাং' : i == 1 ? 'हिं' : 'En';
                    return Material(
                      color: selected ? AppColors.sky.withValues(alpha: 0.06) : AppColors.background,
                      borderRadius: AppRadius.lgR,
                      child: InkWell(
                        onTap: () => _lang.setLanguage(i),
                        borderRadius: AppRadius.lgR,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected ? AppColors.sky.withValues(alpha: 0.06) : AppColors.background,
                            borderRadius: AppRadius.lgR,
                            border: Border.all(
                              color: selected ? AppColors.sky : const Color(0xFFE2E8F0),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.sky.withValues(alpha: 0.12)
                                      : AppColors.primary.withValues(alpha: 0.06),
                                  borderRadius: AppRadius.smR,
                                ),
                                alignment: Alignment.center,
                                child: Text(badge,
                                    style: AppTextStyles.label.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: selected ? AppColors.sky : AppColors.primary,
                                    )),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(LanguageController.labels[i],
                                    style: AppTextStyles.body.copyWith(
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      color: selected ? AppColors.sky : AppColors.onBackground,
                                    )),
                              ),
                              if (selected)
                                const Icon(Icons.check_circle_rounded, color: AppColors.sky, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                )),
          ],
        ),
      );

  Widget _logoutCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.xlR,
          border: Border.all(color: AppColors.emergencyRed.withValues(alpha: 0.15)),
          boxShadow: AppShadows.low,
        ),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showLogoutConfirmation,
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: Text('admin_logout'.tr),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.emergencyRed,
              side: const BorderSide(color: AppColors.emergencyRed),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
            ),
          ),
        ),
      );

  void _showLogoutConfirmation() {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xxlR),
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.emergencyRed.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded, color: AppColors.emergencyRed, size: 28),
              ),
              const SizedBox(height: 20),
              Text('admin_logout'.tr, style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Text('লগআউট করতে চান?',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Get.back(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdR,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Text('cancel'.tr,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () { Get.back(); _auth.logout(); },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emergencyRed, foregroundColor: AppColors.onPrimary,
                        elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
                      ),
                      child: Text('admin_logout'.tr, style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecor() => BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlR,
        boxShadow: AppShadows.low,
      );

  Widget _field(TextEditingController ctrl, String label, IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    String? Function(String?)? validator,
  }) => TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLength: maxLength,
        validator: validator,
        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTextStyles.bodySm,
          counterText: '',
          prefixIcon: Icon(icon, color: AppColors.primary, size: 18),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: const BorderSide(color: AppColors.emergencyRed)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: AppRadius.mdR, borderSide: const BorderSide(color: AppColors.emergencyRed, width: 1.5)),
        ),
      );

  Widget _banner(String msg, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.mdR,
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(msg, style: AppTextStyles.label.copyWith(color: color)),
      );
}
