import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/components/app_header.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../core/utils/validators.dart';
import '../../controller/patient_controller.dart';
import '../../data/models/patient_model.dart';

class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});

  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  late final PatientController _ctrl;
  final _formKey = GlobalKey<FormState>();
  String _caseType = 'Pregnancy';
  String _gender = 'Female';
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _villageCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  /// If non-null, this screen is in EDIT mode for an existing patient.
  /// Pre-fills the form fields and the Save button calls updatePatient
  /// instead of addPatient. Triage-derived fields (outcome, reason,
  /// nextStep, qaHistory, risk, lastVisit) are preserved unchanged.
  PatientModel? _editing;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<PatientController>()
        ? Get.find<PatientController>()
        : Get.put(PatientController(), permanent: true);

    // Edit-mode detection: pass the existing PatientModel as Get.arguments.
    final args = Get.arguments;
    if (args is PatientModel) {
      _editing = args;
      _nameCtrl.text    = args.name;
      _ageCtrl.text     = args.age;
      _villageCtrl.text = args.village == 'Unknown' || args.village == '—' ? '' : args.village;
      _mobileCtrl.text  = args.mobile;
      _caseType = args.type;
      _gender   = args.gender.isNotEmpty ? args.gender : 'Female';
    } else if (args is Map<String, dynamic>) {
      // 1b fix: when the worker reaches Add Patient from a case tile on the
      // dashboard, the case ID is passed in as 'caseType'. Pre-select that
      // chip so they don't have to manually pick the case again — they
      // already told us which case they're filing a patient for.
      final preselected = args['caseType']?.toString();
      if (preselected != null && preselected.isNotEmpty &&
          ['Pregnancy', 'Newborn', 'Child', 'Other'].contains(preselected)) {
        _caseType = preselected;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _villageCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  bool get _isEditing => _editing != null;

  void _showSnack(String title, String body, Color color) {
    Get.snackbar(
      title, body,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: color,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isEditing) {
      // EDIT mode: only update demographic fields. Triage data is preserved
      // by copyWith semantics — those fields aren't passed so the existing
      // values carry over.
      final updated = _editing!.copyWith(
        name:    _nameCtrl.text.trim(),
        type:    _caseType,
        village: _villageCtrl.text.trim().isEmpty ? 'Unknown' : _villageCtrl.text.trim(),
        mobile:  _mobileCtrl.text.trim(),
        age:     _ageCtrl.text.trim(),
        gender:  _gender,
      );
      final result = await _ctrl.updatePatient(updated);
      if (!mounted) return;
      if (result == 'duplicate') {
        _showSnack(
          'Cannot Save',
          'Another patient already has this name and mobile number.',
          AppColors.warningYellow,
        );
        return;
      }
      Get.back();
      _showSnack('Patient Updated', '${updated.name} updated successfully.', AppColors.safeGreen);
      return;
    }

    // ADD mode
    _ctrl.addPatient(
      name: _nameCtrl.text.trim(),
      type: _caseType,
      village: _villageCtrl.text.trim().isEmpty ? 'Unknown' : _villageCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
      gender: _gender,
    );
    Get.back();
    _showSnack('Patient Added', '${_nameCtrl.text.trim()} has been added successfully.', AppColors.safeGreen);
  }

  void _saveAndCheckup() {
    if (!_formKey.currentState!.validate()) return;
    final patient = _ctrl.addPatient(
      name: _nameCtrl.text.trim(),
      type: _caseType,
      village: _villageCtrl.text.trim().isEmpty ? 'Unknown' : _villageCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
      gender: _gender,
    );
    Get.toNamed(AppRoutes.selectCase, arguments: {
      'patientId': patient.id,
      'patientName': patient.name,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(title: _isEditing ? 'Edit Patient' : 'Add Patient'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        AppInput(
                          hint: 'Full name',
                          label: 'Patient Name',
                          controller: _nameCtrl,
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 20),
                          validator: (v) => v == null || v.isEmpty ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: AppInput(
                                hint: 'Age',
                                label: 'Age',
                                controller: _ageCtrl,
                                keyboardType: TextInputType.number,
                                prefixIcon: const Icon(Icons.cake_outlined, color: AppColors.primary, size: 20),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Gender', style: AppTextStyles.label),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: _gender,
                                    onChanged: (v) => setState(() => _gender = v!),
                                    style: AppTextStyles.body,
                                    decoration: const InputDecoration(),
                                    items: ['Female', 'Male', 'Other']
                                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        AppInput(
                          hint: 'Village / Area name',
                          label: 'Village',
                          controller: _villageCtrl,
                          prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(height: 16),
                        AppInput(
                          hint: '10-digit mobile number',
                          label: 'Mobile Number',
                          controller: _mobileCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primary, size: 20),
                          validator: Validators.phone,
                        ),
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Case Type', style: AppTextStyles.label),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: ['Pregnancy', 'Newborn', 'Child', 'Other'].map((c) {
                                final sel = c == _caseType;
                                return Material(
                                  color: sel ? AppColors.primary : AppColors.surface,
                                  borderRadius: AppRadius.pillR,
                                  child: InkWell(
                                    onTap: () => setState(() => _caseType = c),
                                    borderRadius: AppRadius.pillR,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: sel ? AppColors.primary : AppColors.surface,
                                        borderRadius: AppRadius.pillR,
                                        boxShadow: sel
                                            ? AppShadows.tinted(AppColors.primary, strength: 2)
                                            : AppShadows.low,
                                      ),
                                      child: Text(
                                        c,
                                        style: AppTextStyles.label.copyWith(
                                          color: sel ? AppColors.onPrimary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Column(
                          children: [
                            AppButton(
                              label: _isEditing ? 'Save Changes' : 'Save Patient',
                              onPressed: _save,
                              outlined: !_isEditing, // edit mode: primary; add mode: secondary (paired with checkup)
                              width: double.infinity,
                            ),
                            // "Save & Start Checkup" only makes sense for new patients —
                            // editing doesn't need a follow-up checkup step.
                            if (!_isEditing) ...[
                              const SizedBox(height: 10),
                              AppButton(
                                label: 'Save & Start Checkup',
                                onPressed: _saveAndCheckup,
                                icon: Icons.mic_rounded,
                                width: double.infinity,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 24),
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
}
