import 'package:get/get.dart';
import 'vapi_tts_service.dart';

/// TTS tone profiles — each maps to a different emotional register.
/// The backend (server.js) maps these to Google Cloud speaking-rate values
/// when synthesizing Bengali audio through Chirp3-HD-Kore. The Flutter side
/// just passes the tone name through to /api/tts.
enum TtsTone {
  normal,    // routine questions — calm, clear
  empathy,   // acknowledging patient situation — warm, slightly slower
  urgent,    // YELLOW band — alert but not panic
  emergency, // RED band — fast, high pitch, commanding
  positive,  // GREEN band / reassurance — warm, slightly upbeat
  question,  // asking a clinical question — clear, slightly slower
}

/// Thin facade over [VapiTtsService] that exposes tone-aware speak methods.
///
/// One voice everywhere: Google Cloud Chirp3-HD-Kore (mature authoritative
/// female). The previous device-TTS fallback path was removed because it
/// used Android's system Bengali voice — also female, but clearly different
/// from Kore. Pilot testers reported it as "two different voices" and
/// found the inconsistency confusing.
///
/// Sources VapiTtsService tries in order for every speak call:
///   1. On-disk cache (instant after first play)
///   2. APK-bundled asset (instant for ~105 critical phrases shipped with
///      the app — emergency callouts, common questions, ack fillers)
///   3. Backend /api/tts → Google Cloud (~1-2 sec network round-trip)
///
/// If all three fail (offline + uncached + not bundled), the call returns
/// silently — no fallback voice. The on-screen text is always rendered
/// regardless, so workers never miss the question itself, just the audio
/// reinforcement of it in rare offline cases.
class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final VapiTtsService _vapiTts = VapiTtsService();

  Function()? onStart;
  Function()? onComplete;
  Function()? onError;

  /// `true` when the last [speak] attempt produced audio (cache / bundle /
  /// network all worked). `false` when audio could not be played at all
  /// (offline + uncached + not bundled).
  ///
  /// Screens can listen with `Obx(() => Icon(_tts.audioReady.value ? ... ))`
  /// to show a small "audio offline" indicator next to the rendered text so
  /// the worker isn't surprised by silence when they expected to hear Kore.
  final RxBool audioReady = true.obs;

  /// Wires the VapiTtsService callbacks. Safe to call multiple times; only
  /// the first call performs the wiring, subsequent calls re-attach the
  /// handlers (useful when the parent widget rebuilds).
  Future<void> init() async {
    _vapiTts.onStart    = () => onStart?.call();
    _vapiTts.onComplete = () => onComplete?.call();
    _vapiTts.onError    = () => onError?.call();
  }

  /// Speaks [text] in the given [tone]. Returns `true` if audio actually
  /// played (cache hit, bundled asset, or successful network fetch), `false`
  /// if all three sources failed (offline + uncached + not bundled).
  ///
  /// Callers can use the return value to show a small "audio offline" icon
  /// next to the rendered text so the worker isn't surprised by silence.
  Future<bool> speak(String text, {TtsTone tone = TtsTone.normal}) async {
    if (text.trim().isEmpty) return false;
    final played = await _vapiTts.speak(text, tone: tone.name);
    audioReady.value = played;
    return played;
  }

  /// Convenience: speak with tone auto-derived from a clinical risk level.
  Future<bool> speakWithRisk(String text, String riskLevel) =>
      speak(text, tone: _toneFromRisk(riskLevel));

  /// Emergency callout — same Kore voice, just the 'emergency' tone profile
  /// (faster speaking rate). 5-second timeout so a network hang doesn't
  /// keep a worker waiting at the most stressful moment. Returns whether
  /// audio actually played.
  Future<bool> speakEmergency(String text) async {
    if (text.trim().isEmpty) return false;
    final played = await _vapiTts.speak(text, tone: TtsTone.emergency.name)
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    audioReady.value = played;
    return played;
  }

  Future<bool> speakQuestion(String text) => speak(text, tone: TtsTone.question);
  Future<bool> speakPositive(String text) => speak(text, tone: TtsTone.positive);
  Future<bool> speakEmpathy(String text)  => speak(text, tone: TtsTone.empathy);

  static TtsTone _toneFromRisk(String risk) => switch (risk.toLowerCase()) {
        'emergency' => TtsTone.emergency,
        'high'      => TtsTone.emergency,
        'medium'    => TtsTone.urgent,
        'low'       => TtsTone.normal,
        'safe'      => TtsTone.positive,
        _           => TtsTone.normal,
      };

  Future<void> stop() => _vapiTts.stop();
}
