import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../shared/widgets/referral_map/referral_map_widget.dart';
import '../../../../core/services/rule_executor.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/triage_result_card.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../patients/controller/patient_controller.dart';
import '../../../../core/services/decision_trace_service.dart';
import '../../../../core/services/mdsr_hook_service.dart';

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

  /// Set after the worker uses the inline "Add Patient" picker on this
  /// screen (urgent / anonymous triage only). Drives the post-attach UI
  /// (button replaced by a small confirmation pill) so the worker sees
  /// the action took effect without leaving the screen.
  String? _attachedPatientName;

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

    // If pipeline blocked (validation failed), use conversational risk level as fallback
    final conversationalRisk = _answers['_riskLevel'] ?? 'low';
    final fallbackBand = switch (conversationalRisk) {
      'emergency' => 'RED',
      'high'      => 'RED',
      'medium'    => 'YELLOW',
      _           => 'GREEN',
    };
    final engineBand = _engineResult.pipelineBlocked ? 'GREEN' : _engineResult.band;
    // Take the worse of engine band vs conversational risk — never downgrade
    const bandOrder = ['GREEN', 'YELLOW', 'RED'];
    final effectiveBand = bandOrder.indexOf(engineBand) >= bandOrder.indexOf(fallbackBand)
        ? engineBand
        : fallbackBand;
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
      TriageOutcome.safe      => _greenCounselling(_caseType),
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

  // ── GREEN counselling scripts — one per case type ──────────────────────────
  static String _greenCounselling(String caseType) => switch (caseType) {
    'pregnancy' =>
      'এখন ভালো আছেন। পরবর্তী ANC চেকআপ সময়মতো করুন। আয়রন ও ক্যালসিয়াম ট্যাবলেট নিয়মিত খান। '
      'বাচ্চার নড়াচড়া কমলে বা মাথা ব্যথা হলে সঙ্গে সঙ্গে জানান।',
    'postpartum' =>
      'মা এখন ভালো আছেন। প্রতিদিন পরিষ্কার থাকুন, সেলাইয়ের জায়গা শুকনো রাখুন। '
      'বুকের দুধ খাওয়ান। জ্বর বা অতিরিক্ত রক্তপাত হলে সঙ্গে সঙ্গে PHC-তে যান।',
    'newborn' =>
      'শিশু এখন ভালো আছে। প্রতি ২ ঘণ্টায় বুকের দুধ দিন। নাভি শুকনো ও পরিষ্কার রাখুন। '
      'জ্বর, শ্বাসকষ্ট বা দুধ না খেলে সঙ্গে সঙ্গে SNCU-তে নিয়ে যান।',
    'child' =>
      'শিশু এখন ভালো আছে। পুষ্টিকর খাবার দিন, পানি পান করান। '
      'টিকার সময়সূচি মেনে চলুন। জ্বর ৫ দিনের বেশি হলে PHC-তে নিয়ে যান।',
    'immunization' =>
      'টিকার সময়সূচি ঠিক আছে। পরবর্তী টিকার তারিখ মনে রাখুন। '
      'টিকার পর জ্বর হলে প্যারাসিটামল দিন। কোনো সমস্যা হলে ANM-কে জানান।',
    'emergency' =>
      'এখন স্থিতিশীল আছেন। বিশ্রাম নিন। '
      'যেকোনো নতুন উপসর্গ দেখা দিলে সঙ্গে সঙ্গে ১০৮ কল করুন।',
    _ =>
      '২ দিন পর রুটিন ফলো-আপ করুন। কোনো নতুন সমস্যা হলে জানান।',
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
    // The backend upload (and retry-on-failure) is handled inside
    // PatientController.saveReport — no separate API call here, otherwise
    // every report would be POSTed twice and duplicated on the server.
  }

  void _saveFollowUp() {
    final ctrl = Get.find<PatientController>();
    final outcomeStr = _outcome.name == 'safe'
        ? 'safe'
        : _outcome.name == 'emergency'
            ? 'emergency'
            : 'attention';
    final qaHistory = _qaPairs
        .map((qa) => {'question': qa.question, 'answer': qa.answer})
        .toList();
    final situation = _answers['_situation'] ?? '';
    final patientId = _args['_patientId']?.toString() ?? '';

    // If this triage was started from an existing patient, attach the result
    // to that patient (updates latest-triage snapshot on the Patient doc).
    // For anonymous triage we **do not** create a ghost patient — the
    // Report saved in _autoSaveReport above is the canonical record.
    // Worker can later view it in the Reports tab or add a real patient
    // and link the situation.
    final linked = patientId.isNotEmpty &&
        ctrl.applyFollowUp(
          patientId: patientId,
          outcome: outcomeStr,
          reason: _reasonText,
          nextStep: _nextStepText,
          situation: situation,
          qaHistory: qaHistory,
        );

    Get.snackbar(
      'সংরক্ষিত হয়েছে',
      linked
          ? 'রোগীর তথ্য হালনাগাদ করা হয়েছে।'
          : 'রিপোর্ট সংরক্ষিত হয়েছে। Reports ট্যাবে দেখুন।',
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
                const SizedBox(height: 16),
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => Get.offAllNamed(AppRoutes.home),
                        customBorder: const CircleBorder(),
                        child: Ink(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            boxShadow: AppShadows.low,
                          ),
                          child: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'triage_result'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Band card ────────────────────────────────────────────────
                TriageResultCard(
                  outcome: _outcome,
                  reason: _reasonText,
                  nextStep: _nextStepText,
                ),
                const SizedBox(height: 16),

                // ── Action card (all bands) ──────────────────────────────────
                _ActionCard(engineResult: _engineResult, outcome: _outcome),

                // ── Attach Patient CTA (anonymous / urgent triage) ──────────
                // Shown when no patient was picked at start. The subtitle on
                // home's "অনামী ট্রায়াজ" option promises this — now the
                // worker can act on it right here, instead of hunting for
                // the Attach button buried in the Reports tab.
                if (_attachedPatientName == null &&
                    (_args['_patientName'] == null ||
                     _args['_patientName'].toString().trim().isEmpty)) ...[
                  const SizedBox(height: 16),
                  _AttachPatientCard(
                    onTap: () => _openAttachPatientPicker(context),
                  ),
                ] else if (_attachedPatientName != null) ...[
                  const SizedBox(height: 16),
                  _AttachedPatientPill(name: _attachedPatientName!),
                ],

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

  /// Maps the triage caseId to the add-patient form's case-type chip
  /// label. Matches the same logic in PatientContextSheet so the worker
  /// gets a consistent default whichever entry point they used.
  String _caseTypeForForm() {
    switch (_caseType) {
      case 'pregnancy':
      case 'postpartum':
        return 'Pregnancy';
      case 'newborn':
        return 'Newborn';
      case 'infant':
      case 'child':
        return 'Child';
      default:
        return 'Other';
    }
  }

  /// Pushes the Add Patient form with the case-type pre-filled, then
  /// detects whether a new patient was created (patients list grew by 1)
  /// and attaches it to the just-saved report. Same id-swap delay
  /// handling as the picker — if the upload hasn't returned the real
  /// Mongo _id yet, the local attach still works and the patient info
  /// rides up with the eventual upload payload.
  Future<void> _addNewPatientAndAttach(BuildContext context) async {
    final ctrl = Get.find<PatientController>();
    final beforeCount = ctrl.patients.length;
    await Get.toNamed(AppRoutes.addPatient, arguments: {
      'caseType': _caseTypeForForm(),
    });
    if (!mounted) return;
    if (ctrl.patients.length <= beforeCount) {
      // User cancelled the add-patient form — nothing to attach.
      return;
    }
    // New patient was added: it's the most recent in the list.
    // PatientController.addPatient inserts at index 0.
    final newPatient = ctrl.patients.first;
    final report = ctrl.reports.isNotEmpty ? ctrl.reports[0] : null;
    final reportId = report?['id']?.toString() ?? '';
    if (reportId.isEmpty) return;
    final ok = await ctrl.attachPatientToReport(
      reportId:    reportId,
      patientId:   newPatient.id,
      patientName: newPatient.name,
      patientType: newPatient.type,
    );
    if (mounted) {
      setState(() => _attachedPatientName = newPatient.name);
    }
    Get.snackbar(
      ok ? 'patient_attached'.tr : 'patient_attached_local'.tr,
      ok
          ? '${newPatient.name} এই রিপোর্টের সাথে যুক্ত করা হয়েছে।'
          : '${newPatient.name} স্থানীয়ভাবে যুক্ত — সার্ভারে পরে সিঙ্ক হবে।',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: ok ? AppColors.safeGreen : AppColors.warningYellow,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }

  /// Opens a searchable bottom sheet of the worker's existing patients
  /// and attaches the picked one to the most recent report (the one
  /// _autoSaveReport just created). Mirrors the Reports-tab attach flow
  /// so behaviour stays consistent.
  Future<void> _openAttachPatientPicker(BuildContext context) async {
    final ctrl = Get.find<PatientController>();
    final patients = ctrl.patients.toList();
    if (patients.isEmpty) {
      Get.snackbar(
        'no_patients_yet'.tr,
        'no_patients_add_first'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.warningYellow,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 4),
      );
      return;
    }
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sbCtx, setSheetState) {
          final q = query.toLowerCase().trim();
          final filtered = q.isEmpty
              ? patients
              : patients.where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.village.toLowerCase().contains(q) ||
                  p.mobile.contains(q),
                ).toList();
          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sbCtx).size.height * 0.75,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
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
                    child: Text('select_patient'.tr,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  // ── Quick "register a new patient" entry ───────────────
                  // The urgent flow originally only let the worker pick from
                  // existing patients. Now they can also create one on the
                  // spot with the case-type pre-filled. After the form pops
                  // we detect the new patient (by patients-count growth) and
                  // attach it to the just-saved report automatically.
                  Material(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    borderRadius: AppRadius.lgR,
                    child: InkWell(
                      borderRadius: AppRadius.lgR,
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        await _addNewPatientAndAttach(context);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.person_add_alt_1_rounded,
                                color: AppColors.accent, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'add_new_patient'.tr,
                                    style: AppTextStyles.label.copyWith(
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'add_new_patient_subtitle'.tr,
                                    style: AppTextStyles.caption,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: AppColors.accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setSheetState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'search_patients_hint'.tr,
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Text('no_matches_found'.tr),
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
                                  borderRadius: AppRadius.lgR,
                                  onTap: () async {
                                    Navigator.of(sheetCtx).pop();
                                    // The just-saved report sits at
                                    // reports[0] (most recent first).
                                    // Wait briefly for upload to swap the
                                    // placeholder id with the server _id,
                                    // so the PATCH targets the real doc.
                                    final report = ctrl.reports.isNotEmpty
                                        ? ctrl.reports[0]
                                        : null;
                                    final reportId =
                                        report?['id']?.toString() ?? '';
                                    if (reportId.isEmpty) return;
                                    final ok = await ctrl.attachPatientToReport(
                                      reportId:    reportId,
                                      patientId:   p.id,
                                      patientName: p.name,
                                      patientType: p.type,
                                    );
                                    if (mounted) {
                                      setState(() => _attachedPatientName = p.name);
                                    }
                                    Get.snackbar(
                                      ok ? 'patient_attached'.tr : 'patient_attached_local'.tr,
                                      ok
                                          ? '${p.name} এই রিপোর্টের সাথে যুক্ত করা হয়েছে।'
                                          : '${p.name} স্থানীয়ভাবে যুক্ত — সার্ভারে পরে সিঙ্ক হবে।',
                                      snackPosition: SnackPosition.BOTTOM,
                                      backgroundColor: ok
                                          ? AppColors.safeGreen
                                          : AppColors.warningYellow,
                                      colorText: Colors.white,
                                      margin: const EdgeInsets.all(16),
                                      borderRadius: 12,
                                      duration: const Duration(seconds: 3),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_rounded,
                                            color: AppColors.primary, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.name,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '${p.type} · ${p.village}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
        },
      ),
    );
  }
}

class _AttachPatientCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AttachPatientCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        borderRadius: AppRadius.lgR,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgR,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_alt_1_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'add_patient_now'.tr,
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.primary, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'add_patient_now_subtitle'.tr,
                      style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachedPatientPill extends StatelessWidget {
  final String name;
  const _AttachedPatientPill({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.safeGreen.withValues(alpha: 0.10),
        borderRadius: AppRadius.lgR,
        border: Border.all(
          color: AppColors.safeGreen.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.safeGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name এই রিপোর্টের সাথে যুক্ত',
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.safeGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
        borderRadius: AppRadius.lgR,
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: border, size: 18),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: AppTextStyles.overline.copyWith(color: border),
              ),
              if (engineResult.referral.isNotEmpty && engineResult.referral != 'None') ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: border.withValues(alpha: 0.12),
                    borderRadius: AppRadius.pillR,
                  ),
                  child: Text(
                    engineResult.referral,
                    style: AppTextStyles.caption.copyWith(color: border, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          if (actionText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(actionText, style: AppTextStyles.body.copyWith(color: textColor)),
          ],
          // Nearest referral map (referral cases)
          if (outcome != TriageOutcome.safe && engineResult.referral.isNotEmpty && engineResult.referral != 'None') ...[
            const SizedBox(height: 12),
            ReferralMapWidget(facilityType: engineResult.referral),
          ],
          // Sign-off pending badge
          if (engineResult.signOffPending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: AppRadius.smR,
                border: Border.all(color: const Color(0xFFD97706)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'এই নিয়মটি চূড়ান্ত অনুমোদনের অপেক্ষায় আছে।',
                      style: AppTextStyles.caption.copyWith(color: const Color(0xFF92400E)),
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
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.low,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('উত্তর সারসংক্ষেপ', style: AppTextStyles.overline.copyWith(color: AppColors.primary)),
          const SizedBox(height: 12),
          ...qaPairs.map((qa) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qa.question, style: AppTextStyles.bodySm),
                    const SizedBox(height: 4),
                    Text(qa.answer, style: AppTextStyles.labelLg),
                    const Divider(height: 18, color: Color(0xFFE0E7FF)),
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
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.low,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: AppRadius.lgR,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: AppRadius.lgR,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ডিসিশন ট্রেস (অডিট)',
                        style: AppTextStyles.label.copyWith(color: AppColors.primary),
                      ),
                    ),
                    Text('${widget.trace.length} নিয়ম', style: AppTextStyles.caption),
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
