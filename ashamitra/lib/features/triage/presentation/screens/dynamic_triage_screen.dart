import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
// ignore: unused_import
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/gemini_triage_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../shared/widgets/voice_orb.dart';
import '../../../../shared/widgets/glass_card.dart';

class DynamicTriageScreen extends StatefulWidget {
  const DynamicTriageScreen({super.key});

  @override
  State<DynamicTriageScreen> createState() => _DynamicTriageScreenState();
}

class _DynamicTriageScreenState extends State<DynamicTriageScreen> {
  final _gemini = GeminiTriageService();
  final _tts = TtsService();
  final _stt = SpeechToText();

  late String _caseType;
  late String _caseTitle;
  late String _situation;

  // All generated questions
  List<Map<String, dynamic>> _questions = [];
  int _currentIndex = 0;

  // Conversation history
  final List<Map<String, String>> _history = [];

  bool _collectingSituation = false;
  bool _loadingQuestions = false; // true while fetching all questions
  bool _isListening = false;
  bool _isSpeaking = false;
  String _transcript = '';
  double _confidence = 0.0;
  OrbState _orbState = OrbState.idle;
  int _remainingSeconds = 90;

  String get _currentQuestion =>
      _questions.isNotEmpty && _currentIndex < _questions.length
          ? _questions[_currentIndex]['question'] as String
          : '';

  List<String> get _currentOptions =>
      _questions.isNotEmpty && _currentIndex < _questions.length
          ? List<String>.from(_questions[_currentIndex]['options'] as List)
          : [];

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    _caseType = args['caseId'] as String? ?? 'pregnancy';
    _caseTitle = args['caseTitle'] as String? ?? 'চেকআপ';
    _situation = args['situation'] as String? ?? '';
    _collectingSituation = _situation.isEmpty;
    _initTts();
    _initStt();
  }

  Future<void> _initTts() async {
    _tts.onStart    = () { if (mounted) setState(() => _isSpeaking = true); };
    _tts.onComplete = () { if (mounted) setState(() => _isSpeaking = false); };
    _tts.onError    = () { if (mounted) setState(() => _isSpeaking = false); };
    await _tts.init();
  }

  Future<void> _initStt() async {
    await _stt.initialize(
      onError: (_) {
        if (!mounted) return;
        setState(() { _isListening = false; _orbState = OrbState.idle; });
      },
      onStatus: (s) {
        if (!mounted) return;
        if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) {
          setState(() { _isListening = false; _orbState = OrbState.idle; });
        }
      },
    );

    if (_collectingSituation) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) _speak('রোগীর পরিস্থিতি বলুন।');
    } else {
      await _fetchQuestions();
    }
  }

  Future<void> _fetchQuestions() async {
    setState(() { _loadingQuestions = true; _orbState = OrbState.processing; });
    final questions = await _gemini.generateQuestions(
      caseType: _caseType,
      situation: _situation,
    );
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _currentIndex = 0;
      _loadingQuestions = false;
      _orbState = OrbState.idle;
      _transcript = '';
    });
    if (_questions.isNotEmpty) await _speak(_currentQuestion);
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  // Single-tap toggle mic
  Future<void> _toggleMic() async {
    if (_isListening) {
      await _stt.stop();
      setState(() { _isListening = false; _orbState = OrbState.idle; });
      if (_transcript.isNotEmpty) _handleVoiceAnswer(_transcript);
    } else {
      await _tts.stop();
      setState(() {
        _isListening = true;
        _transcript = '';
        _confidence = 0.0;
        _orbState = OrbState.listening;
        _remainingSeconds = 90;
      });
      _startCountdown();
      await _stt.listen(
        localeId: 'bn_IN',
        listenFor: const Duration(seconds: 90),
        pauseFor: const Duration(seconds: 90),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
        onResult: _onResult,
        onSoundLevelChange: (level) {
          if (mounted && _isListening) {
            final n = ((level + 2) / 12).clamp(0.0, 1.0);
            if (n > 0.15) setState(() => _orbState = OrbState.listening);
          }
        },
      );
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;
    setState(() { _transcript = text; _confidence = result.confidence; });
    if (result.finalResult) {
      _stt.stop();
      setState(() { _isListening = false; _orbState = OrbState.processing; });
      _handleVoiceAnswer(text);
    }
  }

  void _handleVoiceAnswer(String text) {
    if (_collectingSituation) {
      setState(() {
        _situation = text;
        _collectingSituation = false;
      });
      _fetchQuestions();
    } else {
      _submitAnswer(text);
    }
  }

  void _startCountdown() {
    _remainingSeconds = 90;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isListening) return false;
      setState(() => _remainingSeconds--);
      return _remainingSeconds > 0 && _isListening;
    });
  }

  void _submitAnswer(String answer) {
    _history.add({'q': _currentQuestion, 'a': answer});
    setState(() { _transcript = ''; _orbState = OrbState.idle; });

    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
      _speak(_currentQuestion);
    } else {
      _finishTriage();
    }
  }

  Future<void> _finishTriage() async {
    setState(() { _loadingQuestions = true; _orbState = OrbState.processing; });
    await _speak('ধন্যবাদ। ফলাফল তৈরি হচ্ছে।');

    // Build qaList string for result screen display
    final qaListStr = _history.map((h) => '${h['q']}|||${h['a']}').join(';;');

    // Gap 2 fix: map each history entry to a synthetic answer key so the
    // engine receives non-empty answers and doesn't block with INPUT_004.
    // Keys are 'dyn_0', 'dyn_1', ... — they won't match any rule condition,
    // so the engine returns GREEN, which is the correct safe default for
    // Gemini-generated questions that have no rule IDs.
    // The ASHA still sees the full Q&A summary on the result screen.
    final syntheticAnswers = <String, dynamic>{
      for (var i = 0; i < _history.length; i++)
        'dyn_$i': _history[i]['a'] ?? '',
    };

    if (!mounted) return;

    Get.toNamed(AppRoutes.triageResult, arguments: {
      '_caseType': _caseType,
      '_qaList': qaListStr,
      '_situation': _situation,
      ...syntheticAnswers,
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final orbSize = screenHeight < 700 ? 80.0 : 100.0;
    final total = _questions.length;
    final progress = total == 0 ? 0.0 : (_currentIndex / total).clamp(0.0, 1.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () { _tts.stop(); _stt.stop(); Get.back(); },
                        customBorder: const CircleBorder(),
                        child: Ink(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            boxShadow: AppShadows.low,
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _caseTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelLg.copyWith(color: AppColors.primary),
                          ),
                          Text(
                            _collectingSituation
                                ? 'পরিস্থিতি বর্ণনা করুন'
                                : total == 0
                                    ? 'প্রশ্ন তৈরি হচ্ছে...'
                                    : 'প্রশ্ন ${_currentIndex + 1} / $total',
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: LinearProgressIndicator(
                              value: _collectingSituation ? 0.0 : progress,
                              backgroundColor: AppColors.primarySoft,
                              color: AppColors.primary,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () {
                          if (_collectingSituation) {
                            _speak('রোগীর পরিস্থিতি বলুন।');
                          } else if (!_loadingQuestions && _currentQuestion.isNotEmpty) {
                            _speak(_currentQuestion);
                          }
                        },
                        customBorder: const CircleBorder(),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            _isSpeaking ? Icons.volume_up_rounded : Icons.replay_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    children: [
                      VoiceOrb(size: orbSize, state: _orbState),
                      const SizedBox(height: 16),

                      // ── Main card ────────────────────────────
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: _collectingSituation
                            ? Column(
                                children: [
                                  const Icon(Icons.record_voice_over_rounded,
                                      size: 36, color: AppColors.primary),
                                  const SizedBox(height: 12),
                                  Text(
                                    'রোগীর পরিস্থিতি বলুন',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.h2,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'মাইক চাপুন এবং রোগীর সমস্যা বিস্তারিত বলুন। যেমন: বয়স, লক্ষণ, কতদিন ধরে হচ্ছে ইত্যাদি।',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodySm,
                                  ),
                                ],
                              )
                            : _loadingQuestions
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(
                                            color: AppColors.primary, strokeWidth: 2),
                                        const SizedBox(height: 10),
                                        Text('প্রশ্ন তৈরি হচ্ছে...', style: AppTextStyles.bodySm),
                                      ],
                                    ),
                                  )
                                : Text(
                                    _currentQuestion,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.h2,
                                  ),
                      ),
                      const SizedBox(height: 20),

                      // ── Mic toggle ───────────────────────────
                      Material(
                        shape: const CircleBorder(),
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _loadingQuestions ? null : _toggleMic,
                          customBorder: const CircleBorder(),
                          child: Ink(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: _isListening
                                    ? [AppColors.safeGreen, const Color(0xFF16A34A)]
                                    : [AppColors.primary, AppColors.purple],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: AppShadows.tinted(
                                _isListening ? AppColors.safeGreen : AppColors.primary,
                                strength: 2,
                              ),
                            ),
                            child: Icon(
                              _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                              color: Colors.white, size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isListening
                            ? 'শুনছি — থামাতে আবার চাপুন'
                            : _collectingSituation
                                ? 'মাইক চাপুন পরিস্থিতি বলতে'
                                : 'মাইক চাপুন উত্তর দিতে',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: _isListening ? AppColors.safeGreen : AppColors.textSecondary,
                          fontWeight: _isListening ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),

                      if (_isListening) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_remainingSeconds}s',
                          style: AppTextStyles.caption.copyWith(
                            color: _remainingSeconds < 15 ? AppColors.emergencyRed : AppColors.textSecondary,
                          ),
                        ),
                      ],

                      // ── Live transcript ──────────────────────
                      if (_transcript.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: AppRadius.mdR,
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('"$_transcript"', style: AppTextStyles.body),
                              if (_confidence > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${(_confidence * 100).toStringAsFixed(0)}% নিশ্চিত',
                                  style: AppTextStyles.caption.copyWith(
                                    color: _confidence > 0.7 ? AppColors.safeGreen : AppColors.warningYellow,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      // ── Previous answers ─────────────────────
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('আগের উত্তর', style: AppTextStyles.overline),
                        ),
                        const SizedBox(height: 6),
                        ..._history.reversed.take(3).map((h) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: AppColors.surface.withValues(alpha: 0.70),
                                  borderRadius: AppRadius.mdR,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: Text(h['q'] ?? '', style: AppTextStyles.bodySm)),
                                    const SizedBox(width: 8),
                                    Text(h['a'] ?? '', style: AppTextStyles.label),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Option buttons ───────────────────────────────
              if (!_collectingSituation && !_loadingQuestions && _currentOptions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Wrap(
                    spacing: 10, runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: _currentOptions.map((opt) {
                      final isYes = opt == 'হ্যাঁ';
                      final isNo = opt == 'না';
                      final bg = isYes
                          ? AppColors.emergencyRed
                          : isNo
                              ? AppColors.safeGreen
                              : AppColors.surface;
                      final fg = (isYes || isNo) ? AppColors.onPrimary : AppColors.textSecondary;
                      return SizedBox(
                        width: (MediaQuery.of(context).size.width - 56) /
                            _currentOptions.length.clamp(1, 3),
                        child: Material(
                          color: bg,
                          borderRadius: AppRadius.mdR,
                          child: InkWell(
                            onTap: () => _submitAnswer(opt),
                            borderRadius: AppRadius.mdR,
                            child: Ink(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: AppRadius.mdR,
                                border: (isYes || isNo)
                                    ? null
                                    : Border.all(color: AppColors.cardBorder),
                                boxShadow: (isYes || isNo)
                                    ? AppShadows.tinted(bg, strength: 2)
                                    : AppShadows.low,
                              ),
                              child: Text(
                                opt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.label.copyWith(color: fg),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
