import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../shared/widgets/voice_orb.dart';
import '../../../../shared/widgets/mic_button.dart';
import '../../../../shared/widgets/glass_card.dart';
import '../../../../core/services/gemini_triage_service.dart';
import '../../../../core/services/rule_executor.dart';
import '../../../../core/services/clup/clup_pipeline.dart';
import '../../../../core/services/clup/situation_extractor.dart';
import '../../../../core/services/clup/clarification_engine.dart';

enum _TriagePhase { situation, questions }

class VoiceTriageScreen extends StatefulWidget {
  const VoiceTriageScreen({super.key});

  @override
  State<VoiceTriageScreen> createState() => _VoiceTriageScreenState();
}

class _VoiceTriageScreenState extends State<VoiceTriageScreen> {
  final _clup = CLUPPipeline();
  final _situationExtractor = SituationExtractor();
  Map<String, bool> _preAnswers = {};
  List<String> _extractedSymptoms = [];
  _TriagePhase _phase = _TriagePhase.situation;
  int _currentIndex = 0;
  OrbState _orbState = OrbState.idle;
  final Map<String, dynamic> _answers = {};
  final List<Map<String, String>> _qaList = [];
  bool _awaitingClarificationAnswer = false;
  ClarificationOutput? _pendingClarification;
  late String _caseType;
  late String _caseTitle;
  List<EngineQuestion> _questions = [];
  String _situation = '';

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  final SpeechToText _sttFallback = SpeechToText();
  bool _sttAvailable = false;
  bool _sttFallbackAvailable = false;
  bool _isListening = false;
  bool _isOffline = false;
  bool _loadingQuestions = false;
  String _transcript = '';
  String _statusText = '';
  bool _answered = false;
  String _detectedLanguage = 'Auto';
  double _confidence = 0.0;
  int _remainingSeconds = 90;

  // ── Keyword maps ─────────────────────────────────────────────
  static const _yesKeywords = [
    'হ্যাঁ', 'হা', 'হ্যা', 'হাঁ', 'জি', 'জি হ্যাঁ', 'অবশ্যই', 'ঠিক', 'সত্যি',
    'হয়', 'হয়েছে', 'আছে', 'আছেন', 'হচ্ছে',
    'হ', 'হো', 'হইছে', 'হইয়াছে', 'হইতেছে', 'আছে তো', 'আছে গো',
    'হইব', 'হবে গো', 'হয় গো', 'আছেই', 'আছে রে',
    'আছে নি', 'হইছে নি', 'হয় নি কি', 'আছে কি না', 'হ্যাঁ গো',
    'হ্যাঁ রে', 'হ্যাঁ বাবা', 'হ্যাঁ মা', 'আছে বলতে পারি',
    'হঁ', 'হঁ গো', 'আছে হে', 'হয় হে', 'হইছে হে', 'আছে তো হে',
    'হয় রে', 'হয় তো', 'আছে রে', 'হইছে রে', 'হ রে', 'হ তো',
    'জি হ্যাঁ', 'জি জি', 'জি বলুন', 'হ্যাঁ জি', 'আছে জি',
    'हाँ', 'हां', 'हा', 'जी', 'जी हाँ', 'बिल्कुल', 'सही', 'ठीक', 'हाँ जी',
    'है', 'हुआ', 'हो रहा है',
    'yes', 'yeah', 'yep', 'correct', 'right', 'sure', 'ok', 'okay', 'yup',
    'haan', 'haa', 'thik', 'thik ache', 'thik hai',
  ];

  static const _noKeywords = [
    'না', 'নাহ', 'নেই', 'নয়', 'নাই', 'না না', 'নো', 'নহে', 'নাহি',
    'হয়নি', 'হয় নি', 'হয়নাই', 'নেই তো',
    'নাই গো', 'নেই গো', 'নাই রে', 'নেই রে', 'হয় নাই', 'হইনি',
    'হইছে না', 'নাই তো', 'নেই তো গো', 'না গো', 'না রে',
    'নাই নি', 'নেই নি', 'না বাবা', 'না মা', 'না গো মা', 'নাহ গো',
    'হয় নাই কি', 'নেই কি না',
    'না হে', 'নাই হে', 'নেই হে', 'হয় না হে', 'হইছে না হে',
    'নাই রে', 'হয় না রে', 'না তো', 'নাই তো রে',
    'नहीं', 'नही', 'ना', 'नहीं है', 'नहीं हुआ', 'नहीं हो रहा',
    'no', 'nope', 'not', 'never', 'nah', 'noo',
    'nahi', 'nai', 'nehi', 'na',
  ];

  static const _maybeKeywords = [
    'মাঝে মাঝে', 'কিছুটা', 'একটু', 'হয়তো', 'নিশ্চিত না', 'জানি না',
    'কখনো কখনো', 'মাঝেমধ্যে', 'একটু একটু', 'কম', 'হালকা',
    'মনে হয়', 'মনে হচ্ছে', 'বলতে পারছি না', 'বুঝতে পারছি না',
    'মনে হইতেছে', 'একটু একটু আছে', 'কম কম', 'হালকা হালকা',
    'মনে হয় গো', 'জানি না গো', 'বলতে পারছি না গো',
    'কখনো কখনো গো', 'একটু আছে গো', 'হয়তো গো',
    'মনে হয় রে', 'জানি না রে', 'একটু আছে নি', 'কিছুটা আছে নি',
    'হয়তো বা', 'হয়তো বাবা', 'নিশ্চিত না গো',
    'একটু হে', 'কম হে', 'মনে হয় হে', 'জানি না হে', 'হয়তো হে',
    'একটু রে', 'কম রে', 'জানি না রে', 'হয়তো রে', 'কখনো রে', 'হালকা রে',
    'कभी कभी', 'थोड़ा', 'शायद', 'पता नहीं', 'हल्का', 'कम',
    'लगता है', 'मालूम नहीं',
    'sometimes', 'maybe', 'little', 'slight', 'occasionally', 'not sure',
    'thoda', 'ektu', 'halka', 'kom',
  ];

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final Map<String, dynamic> argsMap = (args is Map<String, dynamic>) ? args : {};
    _caseType = argsMap['caseId'] as String? ?? 'pregnancy';
    _caseTitle = argsMap['caseTitle'] as String? ?? '🤰 গর্ভবতী মায়ের চেকআপ';
    _situation = argsMap['situation'] as String? ?? '';
    _statusText = 'মাইক ট্যাপ করুন কথা বলতে';
    _detectedLanguage = 'বাংলা';
    _initTts();
    _initStt();
    // Voice detection path: situation already spoken at SelectCaseScreen,
    // skip Phase 1 UI and go straight to question generation.
    if (_situation.isNotEmpty) _generateQuestions(_situation);
  }

  // ── Phase 1: generate questions from situation ───────────────
  Future<void> _generateQuestions(String situation) async {
    setState(() { _loadingQuestions = true; _phase = _TriagePhase.questions; });
    try {
      final moduleId = _toModuleId(_caseType);

      // Extract pre-answers from situation
      if (situation.isNotEmpty) {
        final extraction = _situationExtractor.extract(
          situation: situation,
          moduleId: moduleId,
        );
        _preAnswers = extraction.preAnswers;
        _extractedSymptoms = extraction.extractedSymptoms;
        for (final entry in _preAnswers.entries) {
          _answers[entry.key] = entry.value;
          final matchedQ = Get.find<RuleExecutor>().questionIndex()
              .where((q) => q.id == entry.key)
              .firstOrNull;
          if (matchedQ != null) {
            _qaList.add({
              'question': matchedQ.textBn,
              'answer': entry.value ? 'হ্যাঁ' : 'না',
            });
          }
        }
      }

      final engineQuestions = Get.find<RuleExecutor>().questionIndex()
          .where((q) => q.moduleId == moduleId)
          .toList();

      // Always build plain questions first as the safe fallback
      final qMeta = {for (final q in engineQuestions) q.id: q};
      List<Map<String, dynamic>> enriched;

      final online = await _hasInternet();
      _isOffline = !online;

      if (online && situation.isNotEmpty) {
        try {
          enriched = await GeminiTriageService().enrichQuestions(
            caseType: _caseType,
            situation: situation,
            moduleQuestions: engineQuestions
                .map((q) => {'id': q.id, 'text_bn': q.textBn, 'text_en': q.textEn})
                .toList(),
          );
        } catch (_) {
          // Gemini failed — fall back to plain engine questions
          enriched = engineQuestions
              .map((q) => {'id': q.id, 'text_bn': q.textBn, 'options': ['হ্যাঁ', 'না']})
              .toList();
        }
      } else {
        enriched = engineQuestions
            .map((q) => {'id': q.id, 'text_bn': q.textBn, 'options': ['হ্যাঁ', 'না']})
            .toList();
      }

      final questions = enriched
          .map((e) {
            final id = e['id'] as String;
            final meta = qMeta[id];
            if (meta == null) return null; // skip any ID Gemini invented
            return EngineQuestion(
              id: id,
              moduleId: moduleId,
              ruleId: meta.ruleId,
              textBn: (e['text_bn'] as String).isNotEmpty ? e['text_bn'] as String : meta.textBn,
              textEn: meta.textEn,
              options: (() {
                final opts = List<String>.from((e['options'] as List?) ?? []);
                return opts.length >= 2 ? opts : ['হ্যাঁ', 'না'];
              })(),
              actionBn: meta.actionBn,
              actionEn: meta.actionEn,
            );
          })
          .whereType<EngineQuestion>()
          .where((q) => !_preAnswers.containsKey(q.id))
          .toList();

      if (!mounted) return;

      if (questions.isEmpty) {
        setState(() => _loadingQuestions = false);
        _submitAnswers();
        return;
      }

      setState(() {
        _questions = questions;
        _loadingQuestions = false;
        _currentIndex = 0;
      });
      _speakQuestion();
    } catch (e) {
      // Hard fallback: load plain engine questions so the ASHA is never stuck
      if (!mounted) return;
      try {
        final moduleId = _toModuleId(_caseType);
        final fallback = Get.find<RuleExecutor>().questionIndex()
            .where((q) => q.moduleId == moduleId)
            .where((q) => !_preAnswers.containsKey(q.id))
            .toList();
        setState(() {
          _questions = fallback;
          _loadingQuestions = false;
          _currentIndex = 0;
        });
        if (fallback.isNotEmpty) _speakQuestion();
      } catch (_) {
        setState(() => _loadingQuestions = false);
      }
    }
  }

  static String _toModuleId(String caseType) => switch (caseType) {
    'newborn'      => 'newborn',
    'infant'       => 'child',
    'child'        => 'child',
    'pregnancy'    => 'pregnancy',
    'postpartum'   => 'delivery_pnc',
    'immunization' => 'immunisation',
    _              => 'emergency',
  };

  Future<void> _initTts() async {
    // Try Google TTS engine first (best Bengali quality, free)
    await _tts.setEngine('com.google.android.tts');
    await _tts.setLanguage('bn-IN');

    // Tune for natural Bengali speech
    await _tts.setSpeechRate(0.48);  // slightly faster = more natural
    await _tts.setPitch(1.05);       // slightly above neutral = warmer
    await _tts.setVolume(1.0);

    // Queue mode: flush previous before speaking new
    await _tts.awaitSpeakCompletion(true);

    _tts.setStartHandler(() {
      if (mounted) setState(() => _orbState = OrbState.processing);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _orbState = OrbState.idle);
    });
    _tts.setErrorHandler((msg) {
      if (mounted) setState(() => _orbState = OrbState.idle);
    });

    await Future.delayed(const Duration(milliseconds: 600));
    if (_phase == _TriagePhase.situation) {
      await _tts.speak('পরিস্থিতি বলুন');
    } else if (_questions.isNotEmpty) {
      _speakQuestion();
    }
  }

  // Always speak index 0 — list is reordered by Gemini after each answer
  Future<void> _speakQuestion() async {
    if (_questions.isEmpty || !mounted) return;
    await _tts.stop();
    await Future.delayed(const Duration(milliseconds: 200));
    await _tts.speak(_questions[0].textBn);
  }

  void _startCountdown() {
    _remainingSeconds = 90;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isListening) return false;
      setState(() { _remainingSeconds--; });
      return _remainingSeconds > 0 && _isListening;
    });
  }

  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(
      onError: (e) {
        if (!mounted) return;
        setState(() { _isListening = false; _orbState = OrbState.idle; _statusText = 'আবার চেষ্টা করুন'; });
      },
      onStatus: (status) {
        if (!mounted) return;
        if ((status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) &&
            _isListening && !_answered) {
          setState(() { _isListening = false; _orbState = OrbState.idle; _statusText = 'মাইক ট্যাপ করুন কথা বলতে'; });
        }
      },
    );
    _sttFallbackAvailable = await _sttFallback.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    _sttFallback.stop();
    _clup.resetSession();
    super.dispose();
  }

  Future<bool> _hasInternet() async {
    final r = await Connectivity().checkConnectivity();
    return r.any((c) => c != ConnectivityResult.none);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stt.stop();
      await _sttFallback.stop();
      setState(() { _isListening = false; _orbState = OrbState.idle; _statusText = 'মাইক ট্যাপ করুন কথা বলতে'; });
      // In situation phase, stopping mic submits whatever was heard
      if (_phase == _TriagePhase.situation && _transcript.isNotEmpty) {
        _submitSituation(_transcript);
      }
      return;
    }
    if (!_sttAvailable) {
      setState(() { _statusText = 'Speech recognition unavailable'; });
      return;
    }

    // Stop TTS before listening
    await _tts.stop();

    final online = await _hasInternet();
    _isOffline = !online;
    _answered = false;

    setState(() {
      _isListening = true;
      _transcript = '';
      _orbState = OrbState.listening;
      _statusText = _isOffline ? '🔴 অফলাইন — বলুন...' : '🟢 শুনছি — বলুন...';
      _detectedLanguage = 'বাংলা';
      _confidence = 0.0;
    });

    _startCountdown();

    final listenOpts = SpeechListenOptions(
      listenMode: ListenMode.dictation,
      onDevice: _isOffline,
      partialResults: true,
      cancelOnError: false,
    );

    await _stt.listen(
      localeId: 'bn_IN',
      listenFor: const Duration(seconds: 90),
      pauseFor: const Duration(seconds: 90),
      listenOptions: listenOpts,
      onResult: _onSpeechResult,
      onSoundLevelChange: (level) {
        if (mounted && _isListening) {
          final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
          if (normalised > 0.15) setState(() => _orbState = OrbState.listening);
        }
      },
    );

    if (_sttFallbackAvailable && !_isOffline) {
      _sttFallback.listen(
        localeId: 'hi_IN',
        listenFor: const Duration(seconds: 90),
        pauseFor: const Duration(seconds: 90),
        listenOptions: listenOpts,
        onResult: _onSpeechResult,
      );
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted || _answered) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    setState(() {
      _transcript = text;
      _confidence = result.confidence;
    });

    _detectLanguage(text);

    if (!result.finalResult) return;

    // ── Phase 1: situation collected ─────────────────────────
    if (_phase == _TriagePhase.situation) {
      _stt.stop();
      _sttFallback.stop();
      setState(() { _isListening = false; _orbState = OrbState.processing; });
      _submitSituation(text);
      return;
    }

    // ── Phase 2: answer matching ──────────────────────────────
    // Gap B: check clarification-await BEFORE CLUP so the ASHA's clarification
    // answer (which CLUP would classify as clinicalSymptom and route to
    // _tryMatch) is handled as a clarification response instead.
    if (_awaitingClarificationAnswer) {
      _awaitingClarificationAnswer = false;
      _pendingClarification = null;
      final modId = _toModuleId(_caseType);
      final extraction = _situationExtractor.extract(situation: text, moduleId: modId);
      // Gap C: snapshot list before mutation so indices stay stable
      final snapshot = List<EngineQuestion>.from(_questions);
      for (final entry in extraction.preAnswers.entries) {
        if (!_answers.containsKey(entry.key)) {
          _answers[entry.key] = entry.value;
          final snapIdx = snapshot.indexWhere((q) => q.id == entry.key);
          if (snapIdx != -1) {
            _qaList.add({'question': snapshot[snapIdx].textBn, 'answer': entry.value ? 'হ্যাঁ' : 'না'});
            final liveIdx = _questions.indexWhere((q) => q.id == entry.key);
            if (liveIdx != -1) _questions.removeAt(liveIdx);
          }
        }
      }
      setState(() { _statusText = 'মাইক ট্যাপ করুন কথা বলতে'; });
      if (_questions.isEmpty) { _submitAnswers(); return; }
      _speakQuestion();
      return;
    }

    // Run CLUP pipeline
    final moduleId = _toModuleId(_caseType);
    final decision = _clup.process(input: text, moduleId: moduleId);

    if (decision.isEmergency) {
      if (_questions.isEmpty) { _submitAnswers(); return; }
      _answer(_questions[0].id, _questions[0].options[0]);
      return;
    }

    if (decision.shouldClarify) {
      final clup = decision.clarification!;
      setState(() {
        _orbState = OrbState.idle;
        _statusText = clup.questionBn;
        _awaitingClarificationAnswer = true;
        _pendingClarification = clup;
      });
      _tts.speak(clup.questionBn);
      return;
    }

    if (decision.shouldIgnore) {
      setState(() { _orbState = OrbState.idle; });
      _speakQuestion();
      return;
    }

    // Clinical and relevant — proceed with normal answer matching
    final matched = _tryMatch(decision.cleanedText ?? text);
    if (!matched) {
      setState(() { _orbState = OrbState.idle; });
      _showNoMatch(text);
    }
    // Note: if matched, _answer() already handled STT stop + state update.
  }

  Future<void> _submitSituation(String situation) async {
    setState(() { _situation = situation; _loadingQuestions = true; _transcript = ''; });
    await _tts.speak('ধন্যবাদ, প্রশ্ন তৈরি হচ্ছে...');
    await _generateQuestions(situation);
    // Speak what was understood from situation
    if (_extractedSymptoms.isNotEmpty && mounted) {
      final understood = 'বুঝেছি: ${_extractedSymptoms.join(', ')}. এখন বাকি প্রশ্ন করছি।';
      await _tts.speak(understood);
    }
  }

  void _detectLanguage(String text) {
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(text)) {
      setState(() => _detectedLanguage = 'বাংলা');
    } else if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) {
      setState(() => _detectedLanguage = 'हिंदी (fallback)');
    } else if (text.isNotEmpty) {
      setState(() => _detectedLanguage = 'English (fallback)');
    }
  }

  bool _tryMatch(String text) {
    if (_questions.isEmpty) return false;
    final lower = text.toLowerCase().trim();
    final q = _questions[0];

    // Bengali has no ASCII word boundaries — use simple contains() instead of
    // a \s-boundary regex, which fails on Unicode scripts.
    bool containsKeyword(String keyword) {
      final kw = keyword.toLowerCase();
      return lower == kw || lower.contains(kw);
    }

    if (_yesKeywords.any((kw) => containsKeyword(kw))) {
      _answer(q.id, q.options[0]); return true;
    }
    if (_noKeywords.any((kw) => containsKeyword(kw))) {
      _answer(q.id, q.options[1]); return true;
    }
    if (q.options.length > 2 && _maybeKeywords.any((kw) => containsKeyword(kw))) {
      _answer(q.id, q.options[2]); return true;
    }
    for (final opt in q.options) {
      if (containsKeyword(opt)) {
        _answer(q.id, opt); return true;
      }
    }
    return false;
  }

  void _showNoMatch(String text) {
    if (!mounted) return;
    setState(() { _statusText = 'মাইক ট্যাপ করুন কথা বলতে'; });
    // Re-speak the question so worker hears it again
    _speakQuestion();
    Get.snackbar(
      'বোঝা যায়নি',
      'শোনা গেছে: "$text"\nআবার বলুন বা নিচের বোতাম চাপুন।',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: AppColors.warningYellow,
      colorText: AppColors.onBackground,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      duration: const Duration(seconds: 3),
    );
  }

  void _answer(String qId, String answer) {
    final q = _questions.firstWhere((q) => q.id == qId,
        orElse: () => _questions[0]);
    final isYes = answer == q.options[0];
    _answers[qId] = isYes;
    _qaList.add({'question': q.textBn, 'answer': answer});

    _answered = true;
    _stt.stop();
    _sttFallback.stop();
    setState(() {
      _isListening = false;
      _orbState = OrbState.processing;
      _transcript = '';
      _statusText = 'মাইক ট্যাপ করুন কথা বলতে';
    });

    // Remove answered question so remaining list is always fresh
    _questions.removeWhere((q) => q.id == qId);

    Future.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      if (_questions.isEmpty) {
        _submitAnswers();
        return;
      }

      // Offline path: just go to next question in list
      if (_isOffline) {
        setState(() { _currentIndex = 0; _answered = false; _orbState = OrbState.idle; });
        _speakQuestion();
        return;
      }

      // Online path: ask Gemini which question is most urgent next
      try {
        final remaining = _questions
            .map((q) => {'id': q.id, 'text_bn': q.textBn})
            .toList();
        final history = _qaList
            .map((qa) => {'q': qa['question']!, 'a': qa['answer']!})
            .toList();

        final next = await GeminiTriageService().getNextQuestion(
          caseType: _caseType,
          situation: _situation,
          conversationHistory: history,
          remainingQuestions: remaining,
        );

        if (!mounted) return;

        if (next.shouldFinish) {
          _submitAnswers();
          return;
        }

        // Speak immediate action BEFORE next question if danger sign confirmed
        if (next.immediateActionBn != null) {
          setState(() {
            _statusText = next.immediateActionBn!;
            _orbState = OrbState.processing;
          });
          await _tts.speak(next.immediateActionBn!);
          if (!mounted) return;
        }

        // Reorder: move Gemini’s chosen question to front with enriched text
        if (next.questionId != null) {
          final idx = _questions.indexWhere((q) => q.id == next.questionId);
          if (idx != -1) {
            final chosen = _questions.removeAt(idx);
            final enriched = (next.questionTextBn != null &&
                    next.questionTextBn!.isNotEmpty)
                ? EngineQuestion(
                    id: chosen.id,
                    moduleId: chosen.moduleId,
                    ruleId: chosen.ruleId,
                    textBn: next.questionTextBn!,
                    textEn: chosen.textEn,
                    options: next.options.length >= 2
                        ? next.options
                        : chosen.options,
                    actionBn: chosen.actionBn,
                    actionEn: chosen.actionEn,
                  )
                : chosen;
            _questions.insert(0, enriched);
          }
        }

        setState(() { _currentIndex = 0; _answered = false; _orbState = OrbState.idle; });
        _speakQuestion();
      } catch (_) {
        if (!mounted) return;
        setState(() { _currentIndex = 0; _answered = false; _orbState = OrbState.idle; });
        _speakQuestion();
      }
    });
  }

  void _submitAnswers() {
    // Gap 3: _answers already contains booleans — pass directly to engine
    // Wrap metadata separately so engine only sees typed answers
    final args = <String, dynamic>{
      '_caseType': _caseType,
      '_situation': _situation,
      '_qaList': _qaList.map((qa) => '${qa['question']}|||${qa['answer']}').join(';;'),
      ..._answers, // bool values keyed by questionId
    };
    Get.toNamed(AppRoutes.triageResult, arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    // ── Phase 1 UI ────────────────────────────────────────────
    if (_phase == _TriagePhase.situation) {
      return _buildSituationPhase();
    }

    // ── Loading questions ─────────────────────────────────────
    if (_loadingQuestions || _questions.isEmpty) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.background),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  _loadingQuestions ? 'প্রশ্ন তৈরি হচ্ছে...' : 'প্রশ্ন পাওয়া যায়নি',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final q = _questions[0];
    final total = _questions.length + _qaList.length;
    final answered = _qaList.length;
    final screenHeight = MediaQuery.of(context).size.height;
    final orbSize = screenHeight < 700 ? 80.0 : 100.0;

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
                    GestureDetector(
                      onTap: () { _tts.stop(); _stt.stop(); Get.back(); },
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_caseTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          const SizedBox(height: 2),
                          Text('প্রশ্ন ${answered + 1} / $total',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total > 0 ? (answered + 1) / total : 0,
                              backgroundColor: const Color(0xFFE0E7FF),
                              color: AppColors.primary,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Speaker button to replay question
                    GestureDetector(
                      onTap: _speakQuestion,
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.volume_up_rounded, size: 20, color: AppColors.primary),
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

                      // ── Extracted symptoms badge ────────────────────────
                      if (_extractedSymptoms.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.safeGreen.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.safeGreen.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  size: 14, color: AppColors.safeGreen),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'বোঝা গেছে: ${_extractedSymptoms.join(' • ')}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.safeGreen,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Question card (Gap 6: show clarification question when active) ──
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                            _awaitingClarificationAnswer
                                ? (_pendingClarification?.questionBn ?? q.textBn)
                                : q.textBn,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600,
                                color: AppColors.onBackground, height: 1.5)),
                      ),
                      const SizedBox(height: 16),

                      // ── Mic button ───────────────────────────
                      MicButton(
                        isListening: _isListening,
                        onToggleOn: _toggleListening,
                        onToggleOff: _toggleListening,
                      ),
                      const SizedBox(height: 6),
                      Text(_statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: _isListening ? AppColors.safeGreen : AppColors.textSecondary,
                            fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
                          )),

                      // ── Countdown timer ──────────────────────
                      if (_isListening) ...[
                        const SizedBox(height: 4),
                        Text('⏱️ ${_remainingSeconds}s',
                            style: TextStyle(
                              fontSize: 11,
                              color: _remainingSeconds < 15 ? AppColors.emergencyRed : AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            )),
                      ],

                      // ── Online/Offline + Language badge ──────
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _isOffline
                                  ? AppColors.warningYellow.withValues(alpha: 0.15)
                                  : AppColors.safeGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _isOffline ? '🔴 Offline' : '🟢 Online',
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: _isOffline ? AppColors.warningYellow : AppColors.safeGreen,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '🌐 $_detectedLanguage',
                              style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // ── Live transcript with confidence ──────
                      if (_transcript.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('"$_transcript"',
                                  style: const TextStyle(fontSize: 14, color: AppColors.onBackground, fontWeight: FontWeight.w500)),
                              if (_confidence > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text('Confidence: ', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                    Text('${(_confidence * 100).toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _confidence > 0.7 ? AppColors.safeGreen : AppColors.warningYellow,
                                        )),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Answer buttons ───────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Wrap(
                  spacing: 8, runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: q.options.map((opt) {
                    final isYes = opt == 'হ্যাঁ';
                    final isNo = opt == 'না';
                    return SizedBox(
                      width: (MediaQuery.of(context).size.width - 56) / q.options.length,
                      child: ElevatedButton(
                        onPressed: () => _answer(q.id, opt),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isYes ? AppColors.emergencyRed : isNo ? AppColors.safeGreen : Colors.white,
                          foregroundColor: (isYes || isNo) ? Colors.white : AppColors.textSecondary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: (isYes || isNo) ? Colors.transparent : const Color(0xFFE0E7FF)),
                          ),
                        ),
                        child: Text(opt,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
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

  // ── Phase 1 situation screen ──────────────────────────────────
  Widget _buildSituationPhase() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () { _tts.stop(); _stt.stop(); Get.back(); },
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_caseTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                          const Text('ধাপ ১ — পরিস্থিতি বলুন',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                VoiceOrb(size: 100, state: _orbState),
                const SizedBox(height: 24),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'পরিস্থিতি বলুন',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.onBackground),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'রোগীর অবস্থা সম্পর্কে বিস্তারিত বলুন',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      if (_transcript.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('"$_transcript"',
                              style: const TextStyle(fontSize: 14, color: AppColors.onBackground)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                MicButton(
                  isListening: _isListening,
                  onToggleOn: _toggleListening,
                  onToggleOff: _toggleListening,
                ),
                const SizedBox(height: 8),
                Text(
                  _isListening ? '🔴 শুনছি — থামাতে আবার চাপুন' : 'মাইক চাপুন, তারপর পরিস্থিতি বলুন',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isListening ? AppColors.safeGreen : AppColors.textSecondary,
                    fontWeight: _isListening ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const Spacer(),
                // Skip button — use fallback questions without situation
                TextButton(
                  onPressed: () => _generateQuestions(''),
                  child: const Text('এড়িয়ে যান →',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
