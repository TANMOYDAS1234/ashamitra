import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/services/rule_executor.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../shared/widgets/triage_result_card.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../patients/controller/patient_controller.dart';
import '../../../../core/services/decision_trace_service.dart';
import '../../../../core/services/mdsr_hook_service.dart';
import '../../../../features/auth/controller/auth_controller.dart';

class TriageResultScreen extends StatefulWidget {
  const TriageResultScreen({super.key});

  @override
  State<TriageResultScreen> createState() => _TriageResultScreenState();
}

class _TriageResultScreenState extends State<TriageResultScreen> {
  // ── Computed once in initState — never re-run ─────────────────────────────
  late final Map<String, dynamic> _args;
  late final Map<String, String> _answers;
  late final String _caseType;
  late final String _moduleId;
  late final DecisionOutput _engineResult;
  late final TriageOutcome _outcome;
  late final String _reasonText;
  late final String _nextStepText;
  late final List<({String question, String answer})> _qaPairs;
  bool _reportSaved = false;

  @override
  void initState() {
    super.initState();
    final raw = Get.arguments;
    _args = raw is Map<String, dynamic>
        ? raw
        : raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _answers = _args.map((k, v) => MapEntry(k, v.toString()));
    _caseType = _answers['_caseType'] ?? '';
    _moduleId = _toModuleId(_caseType);

    // ── Single deterministic engine run — no LLM in diagnostic path ──────────
    // Gap A fix: args already contain booleans from VoiceTriageScreen.
    // Do NOT toString() them — pass the raw dynamic values directly.
    // Only strip metadata keys (prefixed with '_').
    final rawAnswers = <String, dynamic>{
      for (final e in _args.entries)
        if (!e.key.startsWith('_'))
          e.key: e.value is bool
              ? e.value                          // already bool — pass through
              : e.value == 'হ্যাঁ' ? true          // legacy string path
              : e.value == 'না'  ? false
              : e.value,                         // anything else (String vitals etc.)
    };
    final rawVitals = _args['_vitals'];
    final vitalsMap = rawVitals is Map
        ? Map<String, dynamic>.from(rawVitals)
        : <String, dynamic>{};

    _engineResult = Get.find<RuleExecutor>().execute(
      moduleId: _moduleId,
      answers: rawAnswers,
      vitals: vitalsMap,
    );

    // If pipeline blocked (validation failed), treat as GREEN with warning
    final effectiveBand = _engineResult.pipelineBlocked ? 'GREEN' : _engineResult.band;
    _outcome = switch (effectiveBand) {
      'RED'    => TriageOutcome.emergency,
      'YELLOW' => TriageOutcome.attention,
      _        => TriageOutcome.safe,
    };

    final ruleAction = _engineResult.actionBn.isNotEmpty
        ? _engineResult.actionBn
        : _engineResult.actionEn;
    final label = _caseLabel(_caseType);

    _reasonText = ruleAction.isNotEmpty ? ruleAction : switch (_outcome) {
      TriageOutcome.safe      => '$label কোনো বিপদচিহ্ন পাওয়া যায়নি। রোগী স্থিতিশীল।',
      TriageOutcome.attention => '$label কিছু বিপদচিহ্ন পাওয়া গেছে। চিকিৎসা পর্যালোচনা দরকার।',
      TriageOutcome.emergency => '$label গুরুতর বিপদচিহ্ন শনাক্ত হয়েছে।',
    };
    _nextStepText = switch (_outcome) {
      TriageOutcome.safe      => '২ দিন পর রুটিন ফলো-আপ করুন।',
      TriageOutcome.attention => 'আজই নিকটতম PHC-তে রেফার করুন।',
      TriageOutcome.emergency => 'এখনই অ্যাম্বুলেন্স কল করুন / ANM-কে জানান।',
    };
    _qaPairs = _parseQaPairs(_args);
  }

  static String _toModuleId(String c) => switch (c) {
    'newborn'      => 'newborn',
    'infant'       => 'child',
    'child'        => 'child',
    'pregnancy'    => 'pregnancy',
    'postpartum'   => 'delivery_pnc',
    'immunization' => 'immunisation',
    _              => 'emergency',
  };

  static String _caseLabel(String c) => switch (c) {
    'pregnancy'    => 'গর্ভবতী মায়ের',
    'postpartum'   => 'প্রসব-পরবর্তী',
    'newborn'      => 'নবজাতক শিশুর',
    'infant'       => 'শিশুর (১-১২ মাস)',
    'child'        => 'শিশু স্বাস্থ্যের',
    'immunization' => 'টিকাকরণ',
    'emergency'    => 'জরুরি অবস্থার',
    _              => 'রোগীর',
  };

  static List<({String question, String answer})> _parseQaPairs(
      Map<String, dynamic> args) {
    final result = <({String question, String answer})>[];
    final raw = args['_qaList'];
    if (raw == null) return result;
    for (final item in raw.toString().split(';;')) {
      if (!item.contains('|||')) continue;
      final idx = item.indexOf('|||');
      result.add((
        question: item.substring(0, idx).trim(),
        answer: item.substring(idx + 3).trim(),
      ));
    }
    return result;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_reportSaved) {
      _reportSaved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _autoSaveReport();
      });
    }
  }

  Future<void> _autoSaveReport() async {
    final qaHistory = _qaPairs
        .map((qa) => {'question': qa.question, 'answer': qa.answer})
        .toList();
    final sessionId = DecisionTraceService.newSessionId();
    await Get.find<DecisionTraceService>().write(
      sessionId: sessionId,
      caseId: _caseType,
      moduleId: _moduleId,
      // Gap 1 fix: pass raw dynamic args (booleans), not the stringified _answers
      answers: Map<String, dynamic>.from(_args)
          ..removeWhere((k, _) => k.startsWith('_')),
      result: _engineResult,
      protocolHash: _engineResult.protocolHash,
    );

    await Get.find<MdsrHookService>().evaluateAndEnqueue(
      sessionId: sessionId,
      moduleId: _moduleId,
      result: _engineResult,
      // Pass raw dynamic args (booleans) stripped of metadata keys
      answers: {
        for (final e in _args.entries)
          if (!e.key.startsWith('_'))
            e.key: e.value.toString(), // MdsrHookService expects Map<String,String>
      },
      patientId: _args['_patientId']?.toString(),
      patientName: _args['_patientName']?.toString(),
      ashaId: _args['_ashaId']?.toString(),
    );

    final ctrl = Get.find<PatientController>();
    ctrl.saveReport(
      caseType: _caseType,
      outcome: _outcome.name == 'safe' ? 'safe'
          : _outcome.name == 'emergency' ? 'emergency' : 'attention',
      reason: _reasonText,
      nextStep: _nextStepText,
      situation: _answers['_situation'] ?? '',
      qaHistory: qaHistory,
      patientId: _answers['_patientId'],
      patientName: _answers['_patientName'],
      finalBand: _engineResult.finalBand,
      triggeredRules: _engineResult.triggeredRules,
      riskScore: _engineResult.riskScore,
      riskLevel: _engineResult.riskLevel,
      dangerSigns: _engineResult.dangerSigns,
      suspectedConditions: _engineResult.suspectedConditions,
      facilityType: _engineResult.facilityType,
      recheckAfterHours: _engineResult.recheckAfterHours,
      transportAction: _engineResult.transportAction,
    );

    // Save to backend API (MongoDB via REST — non-blocking)
    try {
      final auth = Get.find<AuthController>();
      final band = _engineResult.finalBand.isNotEmpty
          ? _engineResult.finalBand.toUpperCase()
          : switch (_outcome) {
              TriageOutcome.emergency => 'RED',
              TriageOutcome.attention => 'YELLOW',
              TriageOutcome.safe      => 'GREEN',
            };
      await ApiService.saveReport({
        'sessionId':           sessionId,
        'caseType':            _caseType,
        'caseLabel':           _caseLabel(_caseType),
        'moduleId':            _moduleId,
        'finalBand':           band,
        'outcome':             _outcome.name,
        'reason':              _reasonText,
        'nextStep':            _nextStepText,
        'situation':           _answers['_situation'] ?? '',
        'triggeredRules':      _engineResult.triggeredRules,
        'riskScore':           _engineResult.riskScore.toInt(),
        'riskLevel':           _engineResult.riskLevel,
        'dangerSigns':         _engineResult.dangerSigns,
        'suspectedConditions': _engineResult.suspectedConditions,
        'facilityType':        _engineResult.facilityType,
        'recheckAfterHours':   _engineResult.recheckAfterHours.toInt(),
        'patientId':           _args['_patientId']?.toString() ?? '',
        'patientName':         _args['_patientName']?.toString() ?? '',
        'ashaId':              auth.user.value?.id ?? '',
        'ashaName':            auth.user.value?.name ?? '',
        'ashaPhone':           auth.user.value?.phone ?? '',
        'qaHistory':           qaHistory,
      });
    } catch (e) {
      debugPrint('[Report] API save failed: $e');
      // Non-blocking — local save already succeeded
    }
  }

  void _saveFollowUp() {
    final ctrl = Get.find<PatientController>();
    ctrl.saveTriageResult(
      caseType: _caseType,
      outcome: _outcome.name == 'safe' ? 'safe'
          : _outcome.name == 'emergency' ? 'emergency' : 'attention',
      reason: _reasonText,
      nextStep: _nextStepText,
      situation: _answers['_situation'] ?? '',
      qaHistory: _qaPairs.map((qa) => {'question': qa.question, 'answer': qa.answer}).toList(),
    );
    Get.snackbar(
      'সংরক্ষিত হয়েছে',
      'ট্রায়াজ ফলাফল রোগী তালিকায় যোগ হয়েছে।',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.safeGreen,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 24),
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Get.offAllNamed(AppRoutes.home),
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8)],
                        ),
                        child: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('ট্রায়াজ ফলাফল',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onBackground)),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Band card ────────────────────────────────────────────────
                TriageResultCard(
                  outcome: _outcome,
                  reason: _reasonText,
                  nextStep: _nextStepText,
                ),
                const SizedBox(height: 16),

                // ── Action card (all bands) ──────────────────────────────────
                _ActionCard(engineResult: _engineResult, outcome: _outcome),

                // ── Q&A summary ──────────────────────────────────────────────
                if (_qaPairs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _QaSummary(qaPairs: _qaPairs),
                ],

                // ── Decision trace (collapsible audit) ──────────────────────
                if (_engineResult.trace.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DecisionTrace(
                    trace: _engineResult.trace,
                    firedRuleId: _engineResult.ruleId,
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'ফলো-আপ সংরক্ষণ',
                        onPressed: () {
                          _saveFollowUp();
                          Get.toNamed(AppRoutes.patientList);
                        },
                        outlined: true,
                        icon: Icons.bookmark_add_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: _outcome == TriageOutcome.emergency
                            ? 'জরুরি'
                            : 'রেফার',
                        onPressed: () => Get.toNamed(
                          _outcome == TriageOutcome.emergency
                              ? AppRoutes.emergency
                              : AppRoutes.patientList,
                        ),
                        color: _outcome == TriageOutcome.emergency
                            ? AppColors.emergencyRed
                            : null,
                        icon: _outcome == TriageOutcome.emergency
                            ? Icons.emergency_rounded
                            : Icons.local_hospital_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'হোমে ফিরুন',
                  onPressed: () => Get.offAllNamed(AppRoutes.home),
                  outlined: true,
                  width: double.infinity,
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

// ── Action card — shown for all bands, styled by severity ────────────────────
class _ActionCard extends StatelessWidget {
  final DecisionOutput engineResult;
  final TriageOutcome outcome;

  const _ActionCard({required this.engineResult, required this.outcome});

  @override
  Widget build(BuildContext context) {
    final (bg, border, textColor, icon, label) = switch (outcome) {
      TriageOutcome.emergency => (
        const Color(0xFFFFEBEB),
        AppColors.emergencyRed,
        const Color(0xFF7F1D1D),
        Icons.emergency_rounded,
        'জরুরি পদক্ষেপ',
      ),
      TriageOutcome.attention => (
        const Color(0xFFFFFBEB),
        AppColors.warningYellow,
        const Color(0xFF78350F),
        Icons.warning_amber_rounded,
        'পরবর্তী পদক্ষেপ',
      ),
      TriageOutcome.safe => (
        const Color(0xFFECFDF5),
        AppColors.safeGreen,
        const Color(0xFF064E3B),
        Icons.check_circle_outline_rounded,
        'পরামর্শ',
      ),
    };

    final actionText = engineResult.actionBn.isNotEmpty
        ? engineResult.actionBn
        : engineResult.actionEn;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: border, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: border,
                      letterSpacing: 0.4)),
              if (engineResult.referral.isNotEmpty &&
                  engineResult.referral != 'None') ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: border.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(engineResult.referral,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: border)),
                ),
              ],
            ],
          ),
          if (actionText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(actionText,
                style: TextStyle(fontSize: 14, color: textColor, height: 1.6)),
          ],
          // Sign-off pending badge
          if (engineResult.signOffPending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD97706)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'এই নিয়মটি চূড়ান্ত অনুমোদনের অপেক্ষায় আছে।',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Q&A summary ───────────────────────────────────────────────────────────────
class _QaSummary extends StatelessWidget {
  final List<({String question, String answer})> qaPairs;
  const _QaSummary({required this.qaPairs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('উত্তর সারসংক্ষেপ',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...qaPairs.map((qa) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qa.question,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4)),
                    const SizedBox(height: 3),
                    Text(qa.answer,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onBackground)),
                    const Divider(height: 16, color: Color(0xFFE0E7FF)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Decision trace (collapsible) ──────────────────────────────────────────────
class _DecisionTrace extends StatefulWidget {
  final List<RuleTraceEntry> trace;
  final String firedRuleId;
  const _DecisionTrace({required this.trace, required this.firedRuleId});

  @override
  State<_DecisionTrace> createState() => _DecisionTraceState();
}

class _DecisionTraceState extends State<_DecisionTrace> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        children: [
          // Header / toggle
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('ডিসিশন ট্রেস (অডিট)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                  Text('${widget.trace.length} নিয়ম',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFE0E7FF)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: widget.trace.map((t) {
                  final isFired = t.ruleId == widget.firedRuleId;
                  final bandColor = switch (t.band) {
                    'RED'      => AppColors.emergencyRed,
                    'YELLOW'   => AppColors.warningYellow,
                    'GREEN'    => AppColors.safeGreen,
                    _          => AppColors.textSecondary,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          t.fired
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: t.fired ? bandColor : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(t.ruleId,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isFired
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isFired
                                              ? bandColor
                                              : AppColors.onBackground)),
                                  if (t.fired) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: bandColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(t.band,
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: bandColor)),
                                    ),
                                  ],
                                ],
                              ),
                              Text(t.reason,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
