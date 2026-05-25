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

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<PatientController>()
        ? Get.find<PatientController>()
        : Get.put(PatientController(), permanent: true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _villageCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    _ctrl.addPatient(
      name: _nameCtrl.text.trim(),
      type: _caseType,
      village: _villageCtrl.text.trim().isEmpty ? 'Unknown' : _villageCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
      gender: _gender,
    );
    Get.back();
    Get.snackbar(
      'Patient Added',
      '${_nameCtrl.text.trim()} has been added successfully.',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.safeGreen,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
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
              const AppHeader(title: 'Add Patient'),
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
                              label: 'Save Patient',
                              onPressed: _save,
                              outlined: true,
                              width: double.infinity,
                            ),
                            const SizedBox(height: 10),
                            AppButton(
                              label: 'Save & Start Checkup',
                              onPressed: _saveAndCheckup,
                              icon: Icons.mic_rounded,
                              width: double.infinity,
                            ),
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
