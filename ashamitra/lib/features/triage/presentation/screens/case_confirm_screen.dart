import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/case_detection_service.dart';
import '../../data/models/triage_case_model.dart';

class CaseConfirmScreen extends StatefulWidget {
  const CaseConfirmScreen({super.key});

  @override
  State<CaseConfirmScreen> createState() => _CaseConfirmScreenState();
}

class _CaseConfirmScreenState extends State<CaseConfirmScreen> {
  final _service = CaseDetectionService();

  late List<TriageCaseModel> _allCases;
  TriageCaseModel? _detected;
  double _confidence = 0;
  String _method = '';
  bool _loading = true;
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>;
    _detected = args['case'] as TriageCaseModel;
    _confidence = (args['confidence'] as num).toDouble();
    _method = args['method'] as String;
    _loading = false;
    _loadAllCases();
    if (_confidence >= 0.95) _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllCases() async {
    _allCases = await _service.loadCases();
    if (mounted) setState(() {});
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 1) {
        t.cancel();
        _proceed(_detected!);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  void _proceed(TriageCaseModel c) {
    _timer?.cancel();
    final args = Get.arguments as Map<String, dynamic>;
    Get.toNamed(AppRoutes.voiceTriage, arguments: {
      'caseId': c.id,
      'caseTitle': c.title,
      'situation': args['situation'] as String? ?? '',
      if (args['patientId'] != null) 'patientId': args['patientId'],
      if (args['patientName'] != null) 'patientName': args['patientName'],
    });
  }

  Color get _confidenceColor {
    if (_confidence >= 0.85) return AppColors.safeGreen;
    if (_confidence >= 0.60) return AppColors.warningYellow;
    return AppColors.emergencyRed;
  }

  String get _confidenceLabel {
    if (_confidence >= 0.85) return 'high_confidence'.tr;
    if (_confidence >= 0.60) return 'medium_confidence'.tr;
    return 'low_confidence'.tr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: _loading ? _buildLoading() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildLoading() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('analyzing_situation'.tr, style: AppTextStyles.body),
          ],
        ),
      );

  Widget _buildContent() {
    final c = _detected!;
    final isAutoProceeding = _confidence >= 0.95 && _timer != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Text('case_recognized'.tr, style: AppTextStyles.h1),
          const SizedBox(height: 6),
          Text('ASHA-র বক্তব্য বিশ্লেষণ করা হয়েছে', style: AppTextStyles.bodySm),

          const SizedBox(height: 32),

          // ── Detected case card ───────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.xlR,
              boxShadow: AppShadows.tinted(_confidenceColor, strength: 2),
            ),
            child: Column(
              children: [
                Text(
                  c.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: 18),

                // Confidence bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: LinearProgressIndicator(
                          value: _confidence,
                          backgroundColor: AppColors.primarySoft,
                          color: _confidenceColor,
                          minHeight: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(_confidence * 100).toStringAsFixed(0)}%',
                      style: AppTextStyles.labelLg.copyWith(color: _confidenceColor),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _badge(_confidenceLabel, _confidenceColor),
                    _badge(
                      _method == 'ai' ? 'ai_detected'.tr : 'rule_based'.tr,
                      AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          if (isAutoProceeding) ...[
            Text(
              '$_countdown সেকেন্ডে স্বয়ংক্রিয়ভাবে শুরু হবে...',
              style: AppTextStyles.label.copyWith(color: AppColors.safeGreen),
            ),
            const SizedBox(height: 12),
          ],

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _proceed(c),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                'yes_correct_start'.tr,
                style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Change case button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _timer?.cancel();
                _showCasePicker();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
              ),
              child: Text('change'.tr, style: AppTextStyles.labelLg.copyWith(color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.pillR,
        ),
        child: Text(label, style: AppTextStyles.label.copyWith(color: color)),
      );

  void _showCasePicker() {
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('pick_correct_case'.tr, style: AppTextStyles.h3),
            const SizedBox(height: 16),
            ..._allCases.map((c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    c.title,
                    style: c.id == _detected?.id
                        ? AppTextStyles.labelLg.copyWith(color: AppColors.primary)
                        : AppTextStyles.body,
                  ),
                  trailing: c.id == _detected?.id
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    Get.back();
                    _proceed(c);
                  },
                )),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}
