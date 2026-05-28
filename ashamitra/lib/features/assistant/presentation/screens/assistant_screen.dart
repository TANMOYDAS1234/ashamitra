// ─────────────────────────────────────────────────────────────────────────────
// AssistantScreen — voice-first Gemini-Live-style AI assistant for ASHA workers
//
// Behaviour:
//   1. Opens with a warm greeting in the app's selected language (Bengali by
//      default; Hindi or English if the worker set it).
//   2. Voice orb auto-starts listening after the greeting plays.
//   3. Worker speaks freely — clinical questions, general knowledge, casual
//      chat. Whatever.
//   4. Assistant detects the language of the worker's reply and continues in
//      THAT language for the rest of the session — even if it differs from
//      the app setting. Code-switching is tolerated.
//   5. When the conversation contains clinical content (2+ symptoms, a clear
//      patient situation, or a danger sign), the assistant suggests:
//      "Should I save this as a report?" Inline action chips appear.
//   6. If yes → patient picker → save report. If no → conversation continues.
//   7. Tap orb to interrupt the assistant; tap again to resume.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../app/routes.dart';
import '../../../../core/services/language_controller.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/widgets/voice_orb.dart';
import '../../services/assistant_chat_service.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  // ── Services ───────────────────────────────────────────────────────────
  final _chat = AssistantChatService();
  final _stt = SpeechToText();
  final _tts = TtsService();

  // ── State ──────────────────────────────────────────────────────────────
  final List<AssistantTurn> _history = [];
  AssistantLang _activeLang = AssistantLang.bn;
  OrbState _orbState = OrbState.idle;

  String _liveTranscript = '';
  String _statusLine = '';
  bool _sttReady = false;
  bool _isListening = false;
  bool _isThinking = false;
  bool _showSaveChip = false;
  // True while the screen wants to stay listening between turns and even
  // through silent pauses. Flipped off only on dispose so background
  // STT events can't accidentally restart the mic after teardown.
  bool _autoListen = true;

  // Escalates the status line from "thinking" to "waking server" after
  // 5s of waiting so the worker knows the cold-start is happening rather
  // than the app being frozen. Cancelled when the reply lands.
  Timer? _coldStartHintTimer;

  // Round-robin index for the ack-filler phrases — same pattern as triage.
  // Plays a 1-second cached "got it" the moment STT finalizes so the worker
  // never hears silence while the LLM/TTS round-trip is in flight. Every
  // phrase is bundled in the APK and cached on disk, so playback is
  // instant (no network).
  int _ackFillerIndex = 0;
  static const _ackFillers = <String>[
    'বুঝেছি।',
    'একটু অপেক্ষা করুন।',
    'ধন্যবাদ।',
  ];

  @override
  void initState() {
    super.initState();
    _activeLang = AssistantLangX.fromIndex(
      Get.find<LanguageController>().selectedIndex.value,
    );
    _statusLine = _bootStatus(_activeLang);
    _initAll();
  }

  Future<void> _initAll() async {
    await _tts.init();
    _wireTtsCallbacks();
    _sttReady = await _stt.initialize(
      onError: (_) => _resetToIdle(),
      onStatus: (status) {
        if (!mounted) return;
        if ((status == SpeechToText.doneStatus ||
                status == SpeechToText.notListeningStatus) &&
            _isListening) {
          _onListenComplete();
        }
      },
    );
    if (!mounted) return;
    // Voice-first: greet immediately, then auto-listen when TTS done.
    await _speakGreeting();
  }

  void _wireTtsCallbacks() {
    _tts.onStart = () {
      if (mounted) setState(() => _orbState = OrbState.processing);
    };
    _tts.onComplete = () {
      if (!mounted) return;
      setState(() => _orbState = OrbState.idle);
      // Auto-listen after every TTS chunk — voice-first behaviour
      if (!_isThinking && !_showSaveChip) _startListening();
    };
    _tts.onError = () {
      if (mounted) _resetToIdle();
    };
  }

  // ── Greeting ───────────────────────────────────────────────────────────
  Future<void> _speakGreeting() async {
    final greeting = _greetingFor(_activeLang);
    setState(() => _statusLine = _greetingStatus(_activeLang));
    await _tts.speak(greeting, tone: TtsTone.empathy);
  }

  // ── STT control ────────────────────────────────────────────────────────
  Future<void> _startListening() async {
    if (!_sttReady || _isListening) return;
    setState(() {
      _isListening = true;
      _liveTranscript = '';
      _orbState = OrbState.listening;
      _statusLine = _listeningStatus(_activeLang);
    });
    // listenFor extended 30s → 45s and pauseFor 4s → 6s so ASHA workers
    // get more thinking-time between phrases. They often pause mid-
    // sentence to recall a number or look up a register; 4 sec was
    // committing too early and cutting them off.
    await _stt.listen(
      localeId: _activeLang.sttLocale,
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 6),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      ),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _liveTranscript = r.recognizedWords);
        if (r.finalResult && _liveTranscript.trim().isNotEmpty) {
          _stt.stop();
        }
      },
    );
  }

  void _onListenComplete() {
    setState(() {
      _isListening = false;
      _orbState = OrbState.idle;
    });
    final input = _liveTranscript.trim();
    if (input.isEmpty) {
      _statusLine = _idleStatus(_activeLang);
      // Silent timeout (4s pauseFor or 30s listenFor with no speech) —
      // re-arm the mic so the screen stays truly always-listening while
      // open. Without this the worker would have to tap the orb after
      // any silent pause. Tiny delay so STT releases cleanly first.
      if (_autoListen && !_isThinking && !_showSaveChip) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && _autoListen && !_isListening && !_isThinking) {
            _startListening();
          }
        });
      }
      return;
    }
    // Bridge the network/LLM wait: play a 1-sec cached ack the moment STT
    // finalizes so the worker never hears silence between speaking and
    // the assistant's full reply. Fire-and-forget; the response audio
    // will replace this as soon as it arrives.
    _playAckFiller();
    _handleUserInput(input);
  }

  /// Plays a short cached "got it" filler from disk (round-robin through
  /// [_ackFillers] so the same phrase doesn't repeat back-to-back). No-op
  /// if the assistant is processing the previous turn — we don't want to
  /// stack ack audio over an in-flight response.
  void _playAckFiller() {
    if (_isThinking) return;
    final phrase = _ackFillers[_ackFillerIndex % _ackFillers.length];
    _ackFillerIndex++;
    // Don't await — the main response will replace this when ready.
    _tts.speak(phrase, tone: TtsTone.normal);
  }

  // ── Main loop: send to Gemini, speak reply ─────────────────────────────
  Future<void> _handleUserInput(String input) async {
    HapticFeedback.lightImpact();
    setState(() {
      _history.add(AssistantTurn(role: 'user', text: input));
      _isThinking = true;
      _orbState = OrbState.processing;
      _statusLine = _thinkingStatus(_activeLang);
      _liveTranscript = '';
    });

    // Arm cold-start hint — after 5s of waiting, switch the status line
    // to "waking the server" so the worker knows the app isn't frozen.
    _coldStartHintTimer?.cancel();
    _coldStartHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isThinking) {
        setState(() => _statusLine = _wakingServerStatus(_activeLang));
      }
    });

    final response = await _chat.ask(
      userInput: input,
      history: _history,
      appLanguage: _activeLang,
    );

    _coldStartHintTimer?.cancel();

    // Switch active language to whatever the worker just spoke
    _activeLang = response.detectedLanguage;

    setState(() {
      _isThinking = false;
      _history.add(AssistantTurn(role: 'assistant', text: response.text));
      _statusLine = '';
      _showSaveChip = response.shouldOfferSave;
    });

    if (response.text.isNotEmpty) {
      try {
        await _tts.stop(); // ensure no overlap with auto-listen restart
      } catch (_) {}
      // Prefer pre-synthesized bytes from /chat-with-voice — one fewer
      // network round-trip, voice arrives with the text instead of a
      // beat behind. Falls back to /tts via _tts.speak otherwise.
      if (response.prefetchedAudio != null &&
          response.prefetchedAudio!.isNotEmpty) {
        await _tts.speakBytes(
          response.prefetchedAudio!,
          text: response.text,
          tone: TtsTone.normal,
        );
      } else {
        await _tts.speak(response.text, tone: TtsTone.normal);
      }
    }
  }

  // ── Orb tap: interrupt / resume ────────────────────────────────────────
  Future<void> _onOrbTap() async {
    if (_isThinking) return; // can't interrupt while waiting on Gemini
    if (_orbState == OrbState.processing) {
      // TTS is speaking — stop it, go listen
      await _tts.stop();
      setState(() => _orbState = OrbState.idle);
      _startListening();
      return;
    }
    if (_isListening) {
      // already listening — stop + process
      await _stt.stop();
      return;
    }
    // Idle → start listening
    _startListening();
  }

  void _resetToIdle() {
    setState(() {
      _isListening = false;
      _isThinking = false;
      _orbState = OrbState.idle;
      _statusLine = _idleStatus(_activeLang);
    });
  }

  // ── Save as report ─────────────────────────────────────────────────────
  void _confirmSave() {
    setState(() => _showSaveChip = false);
    // Hand off to existing patient context sheet flow — assistant content
    // becomes the situation seed.
    final lastUserMessage = _history.lastWhere(
      (t) => t.role == 'user',
      orElse: () => const AssistantTurn(role: 'user', text: ''),
    );
    Get.toNamed(AppRoutes.selectCase, arguments: {
      'situation': lastUserMessage.text,
    });
  }

  void _dismissSave() => setState(() => _showSaveChip = false);

  @override
  void dispose() {
    // Flip auto-listen off first so the delayed restart callback can't
    // re-open the mic on a disposed state.
    _autoListen = false;
    _coldStartHintTimer?.cancel();
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              _AssistantHeader(
                lang: _activeLang,
                onClose: () => Get.back(),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: _ConversationView(history: _history)),
                    if (_showSaveChip)
                      _SaveAsReportChips(
                        lang: _activeLang,
                        onYes: _confirmSave,
                        onNo: _dismissSave,
                      ),
                    if (_liveTranscript.isNotEmpty && _isListening)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: AppRadius.lgR,
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Text(
                            _liveTranscript,
                            style: AppTextStyles.body
                                .copyWith(color: AppColors.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _OrbDock(
                state: _orbState,
                statusLine: _statusLine.isEmpty
                    ? _idleStatus(_activeLang)
                    : _statusLine,
                isThinking: _isThinking,
                onTap: _onOrbTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── i18n strings (no .tr dependency — these need to track _activeLang) ──
  String _bootStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'প্রস্তুতি চলছে...',
        AssistantLang.hi => 'तैयार हो रही हूँ...',
        AssistantLang.en => 'Getting ready...',
      };
  String _greetingFor(AssistantLang l) => switch (l) {
        AssistantLang.bn =>
          'নমস্কার দিদি, আমি আশামিত্র। আপনি কী জানতে চান বা কোনো রোগীর কথা বলতে চান?',
        AssistantLang.hi =>
          'नमस्ते दीदी, मैं आशामित्र हूँ। आप क्या जानना चाहती हैं, या किसी मरीज़ के बारे में बताइए?',
        AssistantLang.en =>
          'Hello, I\'m Asha Mitra. What would you like to know, or tell me about a patient?',
      };
  String _greetingStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'বলছি...',
        AssistantLang.hi => 'बात कर रही हूँ...',
        AssistantLang.en => 'Speaking...',
      };
  String _listeningStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'শুনছি — বলুন',
        AssistantLang.hi => 'सुन रही हूँ — बोलिए',
        AssistantLang.en => 'Listening...',
      };
  String _thinkingStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'ভাবছি...',
        AssistantLang.hi => 'सोच रही हूँ...',
        AssistantLang.en => 'Thinking...',
      };
  String _wakingServerStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'সার্ভার জাগাচ্ছি, একটু অপেক্ষা করুন...',
        AssistantLang.hi => 'सर्वर जगा रहे हैं, थोड़ा रुकें...',
        AssistantLang.en => 'Waking the server, please wait...',
      };
  String _idleStatus(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'অর্বে ট্যাপ করুন কথা বলতে',
        AssistantLang.hi => 'बोलने के लिए ओर्ब पर टैप करें',
        AssistantLang.en => 'Tap the orb to talk',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _AssistantHeader extends StatelessWidget {
  final AssistantLang lang;
  final VoidCallback onClose;
  const _AssistantHeader({required this.lang, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final title = switch (lang) {
      AssistantLang.bn => 'আশামিত্র',
      AssistantLang.hi => 'आशामित्र',
      AssistantLang.en => 'Asha Mitra',
    };
    final subtitle = switch (lang) {
      AssistantLang.bn => 'ভয়েস সহায়ক',
      AssistantLang.hi => 'वॉइस सहायक',
      AssistantLang.en => 'Voice Assistant',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onClose,
              customBorder: const CircleBorder(),
              child: Ink(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.low,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 20, color: AppColors.onBackground),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.h2),
                Text(subtitle, style: AppTextStyles.bodySm),
              ],
            ),
          ),
          // Subtle language pill — shows active conversation language
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: AppRadius.pillR,
              boxShadow: AppShadows.tinted(AppColors.primary),
            ),
            child: Text(
              lang.code.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationView extends StatelessWidget {
  final List<AssistantTurn> history;
  const _ConversationView({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // App's own logo instead of the generic AI sparkle —
              // pilot listeners associated the star with Gemini.
              Opacity(
                opacity: 0.65,
                child: Image.asset(
                  'assets/images/ashalogo.png',
                  width: 56, height: 56,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'যা ইচ্ছা জিজ্ঞেস করুন',
                textAlign: TextAlign.center,
                style: AppTextStyles.h3
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              Text(
                'ক্লিনিক্যাল প্রশ্ন · সাধারণ জ্ঞান · রোগীর কথা',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      itemCount: history.length,
      itemBuilder: (_, i) {
        final turn = history[history.length - 1 - i];
        return _MessageBubble(turn: turn);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AssistantTurn turn;
  const _MessageBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isUser ? 60 : 0,
        right: isUser ? 0 : 60,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AshaMitra logo as the assistant avatar. White circle so the
            // logo's natural colors read cleanly regardless of what's
            // inside the PNG (a tint mask was breaking on logos with
            // non-trivial alpha). Subtle indigo ring keeps it on-brand.
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: AppShadows.tinted(AppColors.primary),
              ),
              padding: const EdgeInsets.all(3),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/ashalogo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppRadius.md),
                  topRight: const Radius.circular(AppRadius.md),
                  bottomLeft: Radius.circular(isUser ? AppRadius.md : 4),
                  bottomRight: Radius.circular(isUser ? 4 : AppRadius.md),
                ),
                boxShadow: AppShadows.low,
              ),
              child: Text(
                turn.text,
                style: AppTextStyles.body.copyWith(
                  color: isUser ? Colors.white : AppColors.onBackground,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveAsReportChips extends StatelessWidget {
  final AssistantLang lang;
  final VoidCallback onYes;
  final VoidCallback onNo;
  const _SaveAsReportChips({
    required this.lang,
    required this.onYes,
    required this.onNo,
  });

  @override
  Widget build(BuildContext context) {
    final prompt = switch (lang) {
      AssistantLang.bn => 'এটি কি রিপোর্ট হিসেবে সংরক্ষণ করব?',
      AssistantLang.hi => 'इसे रिपोर्ट के रूप में सहेजना है?',
      AssistantLang.en => 'Save this as a report?',
    };
    final yes = switch (lang) {
      AssistantLang.bn => 'হ্যাঁ, সংরক্ষণ করুন',
      AssistantLang.hi => 'हाँ, सहेजें',
      AssistantLang.en => 'Yes, save',
    };
    final no = switch (lang) {
      AssistantLang.bn => 'না, শুধু জ্ঞানের জন্য',
      AssistantLang.hi => 'नहीं, सिर्फ़ जानने के लिए',
      AssistantLang.en => 'No, just info',
    };
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.10),
            AppColors.primary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bookmark_add_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(prompt, style: AppTextStyles.labelLg)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onYes,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(yes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(onPressed: onNo, child: Text(no)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrbDock extends StatelessWidget {
  final OrbState state;
  final String statusLine;
  final bool isThinking;
  final VoidCallback onTap;
  const _OrbDock({
    required this.state,
    required this.statusLine,
    required this.isThinking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: VoiceOrb(state: state, size: 130),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              statusLine,
              key: ValueKey(statusLine),
              style: AppTextStyles.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
