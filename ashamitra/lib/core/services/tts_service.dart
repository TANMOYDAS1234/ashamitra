import 'package:flutter_tts/flutter_tts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'vapi_tts_service.dart';

/// TTS tone profiles — each maps to a different emotional register
enum TtsTone {
  normal,    // routine questions — calm, clear
  empathy,   // acknowledging patient situation — warm, slightly slower
  urgent,    // YELLOW band — alert but not panic
  emergency, // RED band — fast, high pitch, commanding
  positive,  // GREEN band / reassurance — warm, slightly upbeat
  question,  // asking a clinical question — clear, slightly slower
}

class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  // ── Engines ───────────────────────────────────────────────────────────────
  final FlutterTts _deviceTts = FlutterTts();
  final VapiTtsService _vapiTts = VapiTtsService();

  // Flip to true when ElevenLabs is on a paid plan ($5/mo Starter+). Free tier
  // is blocked from datacenter IPs (Render), so for now we use device TTS only.
  static const bool _useOnlineTts = false;

  bool _initialized = false;
  TtsTone _currentTone = TtsTone.normal;

  Function()? onStart;
  Function()? onComplete;
  Function()? onError;

  // ── Device TTS tone profiles (offline fallback) ───────────────────────────
  static const _profiles = <TtsTone, _ToneProfile>{
    TtsTone.normal:    _ToneProfile(rate: 0.42, pitch: 1.0,  pauseMs: 180),
    TtsTone.empathy:   _ToneProfile(rate: 0.38, pitch: 0.95, pauseMs: 250),
    TtsTone.urgent:    _ToneProfile(rate: 0.48, pitch: 1.1,  pauseMs: 120),
    TtsTone.emergency: _ToneProfile(rate: 0.55, pitch: 1.2,  pauseMs: 80),
    TtsTone.positive:  _ToneProfile(rate: 0.40, pitch: 1.05, pauseMs: 200),
    TtsTone.question:  _ToneProfile(rate: 0.38, pitch: 1.0,  pauseMs: 300),
  };

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) {
      _attachDeviceHandlers();
      return;
    }
    // Device TTS — always initialised as offline fallback
    await _deviceTts.setEngine('com.google.android.tts');
    await _deviceTts.setLanguage('bn-IN');
    await _deviceTts.awaitSpeakCompletion(true);
    await _applyDeviceProfile(TtsTone.normal);
    _attachDeviceHandlers();

    // VAPI TTS — wire callbacks
    _vapiTts.onStart    = () => onStart?.call();
    _vapiTts.onComplete = () => onComplete?.call();
    _vapiTts.onError    = () => onError?.call();

    _initialized = true;
  }

  void _attachDeviceHandlers() {
    _deviceTts.setStartHandler(()  => onStart?.call());
    _deviceTts.setCompletionHandler(() => onComplete?.call());
    _deviceTts.setErrorHandler((_) => onError?.call());
  }

  Future<void> _applyDeviceProfile(TtsTone tone) async {
    final p = _profiles[tone]!;
    await _deviceTts.setSpeechRate(p.rate);
    await _deviceTts.setPitch(p.pitch);
    await _deviceTts.setVolume(1.0);
    _currentTone = tone;
  }

  // ── Online check ──────────────────────────────────────────────────────────
  Future<bool> _isOnline() async {
    final r = await Connectivity().checkConnectivity();
    return r.any((c) => c != ConnectivityResult.none);
  }

  // ── Core speak ────────────────────────────────────────────────────────────
  /// Speaks text using ElevenLabs (human voice) when [_useOnlineTts] is on
  /// and the device is online; otherwise uses on-device flutter_tts.
  Future<void> speak(String text, {TtsTone tone = TtsTone.normal}) async {
    if (text.trim().isEmpty) return;

    if (_useOnlineTts && await _isOnline()) {
      final success = await _vapiTts.speak(text);
      if (success) return;
      // Online TTS failed (quota, cold start, datacenter block) — fall through.
    }

    await _speakDevice(text, tone);
  }

  Future<void> _speakDevice(String text, TtsTone tone) async {
    if (tone != _currentTone) await _applyDeviceProfile(tone);
    final profile = _profiles[tone]!;

    final sentences = text
        .split(RegExp(r'(?<=[।!?\.])\\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (sentences.length <= 1) {
      await _deviceTts.speak(text);
      return;
    }

    for (int i = 0; i < sentences.length; i++) {
      await _deviceTts.speak(sentences[i]);
      if (i < sentences.length - 1) {
        final isQuestion = sentences[i + 1].endsWith('?');
        final delay = isQuestion ? profile.pauseMs + 120 : profile.pauseMs;
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
  }

  // ── Convenience methods ───────────────────────────────────────────────────

  /// Speak with tone auto-detected from risk level string.
  Future<void> speakWithRisk(String text, String riskLevel) =>
      speak(text, tone: _toneFromRisk(riskLevel));

  /// Emergency alert — always urgent, never cached (time-critical).
  Future<void> speakEmergency(String text) async {
    if (_useOnlineTts && await _isOnline()) {
      final success = await _vapiTts.speak(text)
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (success) return;
    }
    await _speakDevice(text, TtsTone.emergency);
  }

  /// Clinical question — slightly slower.
  Future<void> speakQuestion(String text) => speak(text, tone: TtsTone.question);

  /// Reassurance / GREEN result.
  Future<void> speakPositive(String text) => speak(text, tone: TtsTone.positive);

  /// Empathy acknowledgment.
  Future<void> speakEmpathy(String text) => speak(text, tone: TtsTone.empathy);

  static TtsTone _toneFromRisk(String risk) => switch (risk.toLowerCase()) {
    'emergency' => TtsTone.emergency,
    'high'      => TtsTone.emergency,
    'medium'    => TtsTone.urgent,
    'low'       => TtsTone.normal,
    'safe'      => TtsTone.positive,
    _           => TtsTone.normal,
  };

  Future<void> stop() async {
    await _deviceTts.stop();
    await _vapiTts.stop();
  }
}

// ── Internal tone profile model ───────────────────────────────────────────────
class _ToneProfile {
  final double rate;
  final double pitch;
  final int pauseMs;
  const _ToneProfile({
    required this.rate,
    required this.pitch,
    required this.pauseMs,
  });
}
