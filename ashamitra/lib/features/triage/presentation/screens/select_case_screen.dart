import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/case_detection_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../shared/components/app_header.dart';
import '../../../home/presentation/widgets/patient_context_sheet.dart';
import '../../data/models/triage_case_model.dart';

class SelectCaseScreen extends StatefulWidget {
  const SelectCaseScreen({super.key});

  @override
  State<SelectCaseScreen> createState() => _SelectCaseScreenState();
}

class _SelectCaseScreenState extends State<SelectCaseScreen> {
  final _detectionService = CaseDetectionService();
  final _stt = SpeechToText();
  final _tts = TtsService();
  List<TriageCaseModel> _cases = [];
  bool _loading = true;
  bool _listening = false;
  String _transcript = '';

  // Forwarded unchanged to the triage flow when triage is started from a
  // patient, so the resulting report links back to that patient.
  String? _patientId;
  String? _patientName;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      _patientId = args['patientId']?.toString();
      _patientName = args['patientName']?.toString();
    }
    _loadCases();
    _initSttTts();
  }

  Future<void> _initSttTts() async {
    await _stt.initialize();
    await _tts.init();
    await Future.delayed(const Duration(milliseconds: 600));
    // Use the SAME tone as voice_triage_screen's opening prompt (empathy)
    // so the worker doesn't hear two different speaking rates between
    // adjacent screens — that 8% rate difference makes Kore sound like
    // two different female voices to a non-technical ear, even though
    // it's the exact same voice model.
    if (mounted) _tts.speak('speak_situation_prompt'.tr,
        tone: TtsTone.empathy);
  }

  Future<void> _loadCases() async {
    final cases = await _detectionService.loadCases();
    if (mounted) setState(() { _cases = cases; _loading = false; });
  }

  // Single-tap toggle
  Future<void> _toggleMic() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      if (_transcript.isNotEmpty) _detectCase(_transcript);
    } else {
      await _tts.stop();
      setState(() { _listening = true; _transcript = ''; });
      await _stt.listen(
        localeId: 'bn_IN',
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 60),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() => _transcript = result.recognizedWords);
          // Auto-stop on final result
          if (result.finalResult && _transcript.isNotEmpty) {
            _stt.stop();
            setState(() => _listening = false);
            _detectCase(_transcript);
          }
        },
      );
    }
  }

  Future<void> _detectCase(String transcript) async {
    Get.dialog(
      const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      barrierDismissible: false,
    );
    final result = await _detectionService.detect(transcript);
    Get.back();

    // Gap 2 fix: zero confidence means nothing was recognised —
    // go straight to manual selection instead of showing a wrong case.
    if (result.confidence == 0.0) {
      Get.snackbar(
        'not_understood'.tr,
        'not_understood_msg'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.warningYellow,
        colorText: AppColors.onBackground,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    final detectedCase = _cases.firstWhere((c) => c.id == result.caseId,
        orElse: () => _cases.first);
    Get.toNamed(AppRoutes.caseConfirm, arguments: {
      'case': detectedCase,
      'confidence': result.confidence,
      'method': result.method,
      'situation': transcript,
      if (_patientId != null) 'patientId': _patientId,
      if (_patientName != null) 'patientName': _patientName,
    });
  }

  /// Visual metadata for each case id — shared between the tile grid in
  /// build() and the PatientContextSheet handoff in _selectCase.
  static const _caseVisuals = <String, (IconData, Color)>{
    'pregnancy':   (Icons.pregnant_woman_rounded,        AppColors.primary),
    'postpartum':  (Icons.health_and_safety_rounded,     AppColors.purple),
    'newborn':     (Icons.child_care_rounded,            AppColors.sky),
    'infant':      (Icons.baby_changing_station_rounded, AppColors.safeGreen),
    'child':       (Icons.child_friendly_rounded,        AppColors.warningYellow),
    'immunization':(Icons.vaccines_rounded,              AppColors.primary),
    'emergency':   (Icons.emergency_rounded,             AppColors.emergencyRed),
  };

  void _selectCase(TriageCaseModel caseModel) {
    // If the caller already attached a patient (started from patient
    // profile, add-patient form, etc.) skip the picker and go straight
    // to triage. If not — e.g. the worker arrived here from the assistant
    // tab's "save as case" flow — show the patient context sheet first
    // so the resulting report gets attributed properly rather than being
    // anonymous and needing "Attach Patient" later.
    if (_patientId != null && _patientId!.isNotEmpty) {
      Get.toNamed(AppRoutes.voiceTriage, arguments: {
        'caseId': caseModel.id,
        'caseTitle': caseModel.title,
        'patientId': _patientId,
        if (_patientName != null) 'patientName': _patientName,
      });
      return;
    }
    final (icon, color) = _caseVisuals[caseModel.id]
        ?? (Icons.help_outline, AppColors.primary);
    PatientContextSheet.show(
      context,
      caseId: caseModel.id,
      caseTitle: caseModel.title,
      caseIcon: icon,
      caseColor: color,
    );
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final caseIcons = _caseVisuals;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                title: 'select_case'.tr,
                subtitle: 'select_case_subtitle'.tr,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _MicCard(
                  listening: _listening,
                  transcript: _transcript,
                  onTap: _toggleMic,
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'or_pick_manually'.tr,
                  style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: _cases.length,
                  itemBuilder: (_, i) {
                    final caseModel = _cases[i];
                    final (icon, color) = caseIcons[caseModel.id] ?? (Icons.help_outline, AppColors.primary);
                    return Material(
                      color: AppColors.surface,
                      borderRadius: AppRadius.xlR,
                      child: InkWell(
                        onTap: () => _selectCase(caseModel),
                        borderRadius: AppRadius.xlR,
                        splashColor: color.withValues(alpha: 0.08),
                        child: Ink(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.xlR,
                            boxShadow: AppShadows.tinted(color),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: AppRadius.mdR,
                                ),
                                child: Icon(icon, color: color, size: 24),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                caseModel.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelLg,
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
      ),
    );
  }
}

class _MicCard extends StatelessWidget {
  final bool listening;
  final String transcript;
  final VoidCallback onTap;
  const _MicCard({
    required this.listening,
    required this.transcript,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = listening ? AppColors.safeGreen : AppColors.primary;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: listening
                  ? [AppColors.safeGreen, const Color(0xFF16A34A)]
                  : [AppColors.primary, AppColors.purple],
            ),
            borderRadius: AppRadius.lgR,
            boxShadow: AppShadows.tinted(accent, strength: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white, size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listening ? 'listening_tap_to_stop'.tr : 'speak_situation'.tr,
                      style: AppTextStyles.labelLg.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      transcript.isNotEmpty
                          ? transcript
                          : listening
                              ? 'speak_now_dots'.tr
                              : 'tap_mic_then_speak'.tr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
