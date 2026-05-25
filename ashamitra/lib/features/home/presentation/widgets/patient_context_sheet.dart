import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../patients/controller/patient_controller.dart';
import '../../../patients/data/models/patient_model.dart';

/// Bottom sheet shown when an ASHA taps a case card on Home.
///
/// Pushes the worker toward the **patient-first** workflow:
///   1. Pick an existing patient → triage links to that patient
///   2. Add a new patient → form opens with the case pre-selected
///   3. Continue without a patient → anonymous triage (still works,
///      but the resulting report is labelled "অনামী").
///
/// `caseId` and `caseTitle` are forwarded so the next screen knows which
/// clinical module to load.
class PatientContextSheet extends StatelessWidget {
  final String caseId;
  final String caseTitle;
  final IconData caseIcon;
  final Color caseColor;

  const PatientContextSheet({
    super.key,
    required this.caseId,
    required this.caseTitle,
    required this.caseIcon,
    required this.caseColor,
  });

  static Future<void> show(
    BuildContext context, {
    required String caseId,
    required String caseTitle,
    required IconData caseIcon,
    required Color caseColor,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PatientContextSheet(
        caseId: caseId,
        caseTitle: caseTitle,
        caseIcon: caseIcon,
        caseColor: caseColor,
      ),
    );
  }

  void _navigateToTriage({String? patientId, String? patientName}) {
    Get.back(); // close sheet
    Get.toNamed(AppRoutes.voiceTriage, arguments: {
      'caseId': caseId,
      'caseTitle': caseTitle,
      if (patientId   != null) 'patientId':   patientId,
      if (patientName != null) 'patientName': patientName,
    });
  }

  void _pickExistingPatient(BuildContext context) {
    final ctrl = Get.find<PatientController>();
    Get.back(); // close this sheet first
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExistingPatientPicker(
        patients: ctrl.patients,
        onPick: (p) {
          Get.back();
          Get.toNamed(AppRoutes.voiceTriage, arguments: {
            'caseId':      caseId,
            'caseTitle':   caseTitle,
            'patientId':   p.id,
            'patientName': p.name,
          });
        },
      ),
    );
  }

  void _addNewPatient() {
    Get.back();
    Get.toNamed(AppRoutes.addPatient);
    // After adding, the user can launch checkup via "Save & Start Checkup",
    // which already passes patientId/Name forward.
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Case summary ──────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: caseColor.withValues(alpha: 0.12),
                    borderRadius: AppRadius.mdR,
                  ),
                  child: Icon(caseIcon, color: caseColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(caseTitle, style: AppTextStyles.h3),
                      Text('কার জন্য এই চেকআপ?', style: AppTextStyles.bodySm),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Option 1: existing patient ─────────────────────────────
            _ContextOption(
              icon: Icons.people_alt_rounded,
              title: 'চলমান রোগী নির্বাচন করুন',
              subtitle: 'আগে থেকে যুক্ত রোগীদের তালিকা থেকে বেছে নিন',
              color: AppColors.primary,
              onTap: () => _pickExistingPatient(context),
            ),
            const SizedBox(height: 10),

            // ── Option 2: add new patient ──────────────────────────────
            _ContextOption(
              icon: Icons.person_add_alt_1_rounded,
              title: 'নতুন রোগী যোগ করুন',
              subtitle: 'এখনই নাম, গ্রাম, মোবাইল দিন — পরে চেকআপ শুরু হবে',
              color: AppColors.accent,
              onTap: _addNewPatient,
              recommended: true,
            ),
            const SizedBox(height: 10),

            // ── Option 3: anonymous ────────────────────────────────────
            _ContextOption(
              icon: Icons.flash_on_rounded,
              title: 'অনামী ট্রায়াজ',
              subtitle: 'দ্রুত পরিস্থিতি যাচাই — পরে রোগী যোগ করা যাবে',
              color: AppColors.textSecondary,
              onTap: () => _navigateToTriage(),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ContextOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool recommended;

  const _ContextOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgR,
            boxShadow: AppShadows.tinted(color),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdR,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: AppTextStyles.labelLg)),
                        if (recommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: AppRadius.pillR,
                            ),
                            child: const Text(
                              'প্রস্তাবিত',
                              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.bodySm),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable picker for existing patients. Shows when the worker chose
/// "চলমান রোগী নির্বাচন করুন" in the context sheet.
class _ExistingPatientPicker extends StatefulWidget {
  final List<PatientModel> patients;
  final void Function(PatientModel) onPick;
  const _ExistingPatientPicker({required this.patients, required this.onPick});

  @override
  State<_ExistingPatientPicker> createState() => _ExistingPatientPickerState();
}

class _ExistingPatientPickerState extends State<_ExistingPatientPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? widget.patients
        : widget.patients.where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.village.toLowerCase().contains(q) ||
            p.mobile.contains(q),
          ).toList();

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('চলমান রোগী নির্বাচন করুন', style: AppTextStyles.h2),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'নাম, গ্রাম বা মোবাইল দিয়ে খুঁজুন',
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          widget.patients.isEmpty
                              ? 'এখনো কোনো রোগী যোগ করা হয়নি'
                              : 'কোনো ফলাফল পাওয়া যায়নি',
                          style: AppTextStyles.bodySm,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        return Material(
                          color: AppColors.primarySoft,
                          borderRadius: AppRadius.lgR,
                          child: InkWell(
                            onTap: () => widget.onPick(p),
                            borderRadius: AppRadius.lgR,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                    child: Text(
                                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                      style: AppTextStyles.labelLg.copyWith(color: AppColors.primary),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: AppTextStyles.labelLg),
                                        Text(
                                          '${p.type} · ${p.village.isEmpty ? "—" : p.village}',
                                          style: AppTextStyles.bodySm,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      size: 14, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
