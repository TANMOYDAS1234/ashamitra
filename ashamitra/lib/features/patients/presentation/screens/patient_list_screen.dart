import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/pdf_helper.dart';
import '../../../../shared/components/app_header.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/patient_card.dart';
import '../../../../shared/widgets/risk_badge.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/components/bottom_nav.dart';
import '../../controller/patient_controller.dart';
import '../../data/models/patient_model.dart';

class PatientListScreen extends StatefulWidget {
  const PatientListScreen({super.key});

  @override
  State<PatientListScreen> createState() => _PatientListScreenState();
}

class _PatientListScreenState extends State<PatientListScreen> {
  late final PatientController _ctrl;
  int _filterIndex = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<PatientController>()
        ? Get.find<PatientController>()
        : Get.put(PatientController(), permanent: true);
  }

  static const _filters = ['All', 'Pregnancy', 'Newborn', 'Child', 'High Risk'];

  List<PatientModel> get _filtered => _ctrl.patients.where((p) {
        final name = p.name;
        final type = p.type;
        final village = p.village;
        final risk = p.riskFromOutcome;

        final matchSearch =
            name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                village.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchFilter = _filterIndex == 0 ||
            (_filterIndex == 4
                ? risk == RiskLevel.high || risk == RiskLevel.emergency
                : _typeMatchesFilter(type, _filters[_filterIndex]));
        return matchSearch && matchFilter;
      }).toList();

  // Matches a patient's type string against a filter chip. `type` is English
  // for manually added patients but Bengali for triage-created ones
  // (PatientController._caseLabel), so both spellings must be checked.
  static bool _typeMatchesFilter(String type, String filter) {
    final t = type.toLowerCase();
    return switch (filter) {
      'Pregnancy' => t.contains('pregnan') || type.contains('গর্ভ'),
      'Newborn'   => t.contains('newborn') || type.contains('নবজাতক'),
      'Child'     => t.contains('child') ||
          t.contains('infant') ||
          type.contains('শিশু'),
      _           => true,
    };
  }

  Future<void> _downloadPdf() async {
    final list = _filtered;
    final theme = await PdfHelper.bengaliTheme();
    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text('ASHA Mitra — Patient List',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text('Total patients: ${list.length}',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Divider(height: 24),
          pw.Table.fromTextArray(
            headers: ['Name', 'Type', 'Village', 'Last Visit', 'Risk'],
            data: list.map((p) => [
              p.name,
              p.type,
              p.village,
              p.lastVisit,
              p.riskFromOutcome.name.toUpperCase(),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo100),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    // saveAndOpen now takes pre-computed bytes — call doc.save() to serialize.
    final bytes = await doc.save();
    await PdfHelper.saveAndOpen(bytes, 'asha_mitra_patients_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: 'Patients',
                actions: [
                  HeaderActionPill(
                    icon: Icons.download_rounded,
                    label: 'PDF',
                    onTap: _downloadPdf,
                  ),
                  HeaderActionCircle(
                    icon: Icons.person_add_rounded,
                    onTap: () => Get.toNamed(AppRoutes.addPatient),
                    tooltip: 'Add patient',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: 'Search patient or village...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 22),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _filters.length,
                  itemBuilder: (_, i) {
                    final sel = i == _filterIndex;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Material(
                        color: sel ? AppColors.primary : AppColors.surface,
                        borderRadius: AppRadius.pillR,
                        child: InkWell(
                          onTap: () => setState(() => _filterIndex = i),
                          borderRadius: AppRadius.pillR,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : AppColors.surface,
                              borderRadius: AppRadius.pillR,
                              boxShadow: sel ? AppShadows.tinted(AppColors.primary, strength: 2) : AppShadows.low,
                            ),
                            child: Text(
                              _filters[i],
                              style: AppTextStyles.label.copyWith(
                                color: sel ? AppColors.onPrimary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Obx(() {
                  if (_ctrl.isLoading.value && _ctrl.patients.isEmpty) {
                    return SkeletonList(
                      count: 5,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      builder: (_) => const SkeletonPatientCard(),
                    );
                  }
                  final list = _filtered;
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'patient_empty'.tr,
                      subtitle: 'patient_list_subtitle_empty'.tr,
                      action: FilledButton.icon(
                        onPressed: () => Get.toNamed(AppRoutes.addPatient),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text('add_patient'.tr),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _ctrl.syncFromServer,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        return Dismissible(
                          key: ValueKey(p.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppColors.emergencyRed,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete_rounded, color: Colors.white, size: 24),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('delete_patient'.tr),
                                content: Text('"${p.name}" তালিকা থেকে মুছে ফেলবেন?'),
                                actions: [
                                  TextButton(onPressed: () => Get.back(result: false), child: Text('cancel'.tr)),
                                  TextButton(
                                    onPressed: () => Get.back(result: true),
                                    child: Text('delete_patient_short'.tr, style: const TextStyle(color: AppColors.emergencyRed)),
                                  ),
                                ],
                              ),
                            ) ?? false;
                          },
                          onDismissed: (_) => _ctrl.deletePatient(p.id),
                          child: PatientCard(
                            name: p.name,
                            caseType: p.type,
                            village: p.village,
                            lastVisit: p.lastVisit,
                            riskLevel: p.riskFromOutcome,
                            heroTag: p.id,
                            onTap: () => Get.toNamed(AppRoutes.patientProfile, arguments: p.toJson()),
                            onCallTap: p.mobile.isNotEmpty
                                ? () => launchUrl(Uri.parse('tel:${p.mobile}'))
                                : null,
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 1),
    );
  }
}
