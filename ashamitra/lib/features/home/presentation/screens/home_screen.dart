import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/case_detection_service.dart';
import '../../../../shared/components/bottom_nav.dart';
import '../widgets/greeting_header.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/patient_context_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _svc = CaseDetectionService();

  @override
  void initState() {
    super.initState();
    _svc.loadCases(); // pre-warm cache
  }

  /// Emergency goes straight through — urgency overrides patient context.
  /// Every other case opens the [PatientContextSheet] which nudges the
  /// worker to pick / add a patient first (or proceed anonymously).
  Future<void> _openCase(
    String caseId,
    String title, {
    required IconData icon,
    required Color color,
  }) async {
    if (caseId == 'emergency') {
      Get.toNamed(AppRoutes.emergency);
      return;
    }
    // Resolve canonical title from the clinical engine in case the
    // dashboard's Bengali label diverges from the case definition.
    final cases = await _svc.loadCases();
    final caseModel = cases.firstWhere(
      (c) => c.id == caseId,
      orElse: () => cases.first,
    );
    if (!mounted) return;
    await PatientContextSheet.show(
      context,
      caseId: caseModel.id,
      caseTitle: caseModel.title,
      caseIcon: icon,
      caseColor: color,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Emoji removed from titles — the Material icon already conveys the case.
    final cards = [
      (Icons.pregnant_woman_rounded,         'গর্ভবতী চেকআপ',          'গর্ভাবস্থার যত্ন',   AppColors.primary,         'pregnancy'),
      (Icons.child_care_rounded,             'প্রসব-পরবর্তী',           'ডেলিভারির পর যত্ন',  AppColors.purple,          'postpartum'),
      (Icons.baby_changing_station_rounded,  'নবজাতক (০–২৮ দিন)',      'নবজাতকের যত্ন',     AppColors.sky,             'newborn'),
      (Icons.child_friendly_rounded,         'শিশু (১–১২ মাস)',         'শিশুর স্বাস্থ্য',    const Color(0xFF10B981),   'infant'),
      (Icons.face_rounded,                   'শিশু (১–৫ বছর)',          'শিশু স্বাস্থ্য যাচাই',const Color(0xFFF59E0B),  'child'),
      (Icons.vaccines_rounded,               'টিকা / ইমিউনাইজেশন',    'টিকা মিস যাচাই',     const Color(0xFF6366F1),   'immunization'),
      (Icons.emergency_rounded,              'জরুরি অবস্থা',           'জরুরি সাহায্য',     AppColors.emergencyRed,    'emergency'),
    ];

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 600 ? 3 : 2;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              const GreetingHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 22,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.accent],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('todays_tasks'.tr, style: AppTextStyles.h3),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 1.05,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (_, i) {
                          final (icon, title, desc, color, caseId) = cards[i];
                          return DashboardCard(
                            icon: icon,
                            title: title,
                            description: desc,
                            color: color,
                            index: i,
                            onTap: () => _openCase(caseId, title, icon: icon, color: color),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 0),
    );
  }
}
