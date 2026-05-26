import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vapi_tts_service.dart';

/// Warms the on-device TTS cache so rural ASHAs hear natural Bengali (Leda)
/// even when offline. Without this, an offline-first-time encounter falls
/// back to the robotic device TTS — bad for clinical trust.
///
/// Coverage (run once per app install, ~500 phrases):
///   1. Static triage questions + actions from triage_cases.json (~87)
///   2. Hardcoded UI prompts spoken in voice/triage screens (~5)
///   3. Common acknowledgment fillers (Gemini-style responses) (~12)
///   4. Dynamic vital alerts enumerated over plausible value ranges (~400)
///        - Temperature: 38.5-41.0°C in 0.1° steps × 3 module variants
///        - SpO2:        60-93%      in 1% steps × 2 severity tiers
///        - RR:          51-90/min   in 1 steps × 2 module variants
///        - BP:          systolic 130-200 × diastolic 80-120 (common pairs)
///        - MUAC:        8.0-12.4 cm in 0.1 steps × 2 severity tiers
///        - Weight LBW:  0.8-1.4 kg  in 0.1 steps (newborn)
///
/// Cost: ~500 API calls + ~15 MB cache, one-time per device.
/// ~25,000 Bengali chars total → Google bill ≈ $0.75/device at Chirp3 pricing.
/// Pilot of 50 ASHAs ≈ $37.50 one-time. Runs silent in background.
class TtsPrewarmService {
  static const _prefsKey = 'tts_prewarm_version';
  static const _currentVersion = 'charon_v3_2026_05';

  /// Tones that match the actual usage at the call site:
  ///   - question  : triage Q&A
  ///   - empathy   : UI prompts, acknowledgments
  ///   - emergency : vital danger alerts (RED-band warnings)
  ///   - urgent    : vital warnings (YELLOW-band warnings)
  static const _toneQuestion  = 'question';
  static const _toneEmpathy   = 'empathy';
  static const _toneEmergency = 'emergency';
  static const _toneUrgent    = 'urgent';

  static bool _running = false;

  /// Kick off the prewarm in the background. Returns immediately. Safe to call
  /// from main() — does not block app startup.
  static Future<void> startInBackground() async {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  static Future<void> _run() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefsKey) == _currentVersion) return;

      final conn = await Connectivity().checkConnectivity();
      if (!conn.any((c) => c != ConnectivityResult.none)) return;

      final tts = VapiTtsService();

      // Combine all phrase sources with their target tones.
      final batches = <(String tone, List<String> phrases)>[
        (_toneEmpathy,   _hardcodedPrompts()),
        (_toneEmpathy,   _acknowledgments()),
        (_toneQuestion,  await _extractFromJson()),
        (_toneEmergency, _vitalAlertsEmergency()),
        (_toneUrgent,    _vitalAlertsUrgent()),
      ];

      var ok = 0, consecutiveFails = 0;
      for (final batch in batches) {
        final tone = batch.$1;
        for (final phrase in batch.$2) {
          final success = await tts.prefetch(phrase, tone: tone);
          if (success) {
            ok++;
            consecutiveFails = 0;
          } else {
            consecutiveFails++;
            // Backend down or quota hit — give up, retry next launch.
            if (consecutiveFails > 8) return;
          }
        }
      }

      // Only mark complete if we made meaningful progress.
      if (ok > 0 && consecutiveFails < 5) {
        await prefs.setString(_prefsKey, _currentVersion);
      }
    } finally {
      _running = false;
    }
  }

  // ── Source 1: triage_cases.json ────────────────────────────────────────────
  /// Pull every `text:` and `action:` string out of triage_cases.json.
  static Future<List<String>> _extractFromJson() async {
    try {
      final raw = await rootBundle.loadString('assets/data/triage_cases.json');
      final json = jsonDecode(raw);
      final out = <String>{};

      void walk(dynamic node) {
        if (node is Map) {
          for (final entry in node.entries) {
            final k = entry.key.toString();
            final v = entry.value;
            if ((k == 'text' || k == 'action') && v is String && v.trim().isNotEmpty) {
              out.add(v.trim());
            } else {
              walk(v);
            }
          }
        } else if (node is List) {
          for (final item in node) {
            walk(item);
          }
        }
      }

      walk(json);
      return out.toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Source 2: hardcoded UI prompts spoken at runtime ───────────────────────
  static List<String> _hardcodedPrompts() => const [
    'পরিস্থিতি বলুন বা প্রশ্ন করুন',
    'পরিস্থিতি বলুন। মাইক বোতাম চাপুন।',
    'মাইক্রোফোন চালু করুন এবং কথা বলুন।',
    'আমি আশামিত্র। আপনার সহায়তা করতে এসেছি।',
    'বুঝেছি। আরো কিছু জানতে চাই।',
  ];

  // ── Source 3: common short acknowledgments (Gemini-style fillers) ──────────
  /// When the conversational layer is offline, these short responses still
  /// play with Leda's voice instead of falling back to robotic device TTS.
  static List<String> _acknowledgments() => const [
    'বুঝেছি।',
    'ভালো খবর।',
    'ধন্যবাদ।',
    'আপনি ভালো করেছেন জানিয়েছেন।',
    'এটা গুরুত্বপূর্ণ।',
    'চিন্তা করবেন না।',
    'আরেকটু জানতে চাই।',
    'একটু অপেক্ষা করুন।',
    'অনুগ্রহ করে আবার বলুন।',
    'সব ঠিক হয়ে যাবে।',
    'নিরাপদ থাকুন।',
    'আপনার পরিশ্রমের জন্য ধন্যবাদ।',
  ];

  // ── Source 4: vital alerts (RED — emergency tone) ──────────────────────────
  static List<String> _vitalAlertsEmergency() {
    final phrases = <String>[];

    // Newborn fever 37.6-39.0°C (anything > 37.5 is RED for newborn)
    for (double t = 37.6; t <= 39.0; t += 0.1) {
      final temp = double.parse(t.toStringAsFixed(1));
      phrases.add('জ্বর ${temp}°C — নবজাতকের জন্য বিপদচিহ্ন! এখনই SNCU-তে রেফার করুন।');
    }

    // SpO2 < 90 (severe hypoxia)
    for (int s = 60; s < 90; s++) {
      phrases.add('SpO2 $s% — গুরুতর হাইপক্সিয়া! এখনই ১০৮ কল করুন।');
    }

    // Newborn RR > 60
    for (int r = 61; r <= 90; r++) {
      phrases.add('শ্বাসের হার $r/মিনিট — নবজাতকের জন্য বিপদচিহ্ন! SNCU-তে রেফার করুন।');
    }

    // Newborn LBW 0.8-1.4 kg
    for (double w = 0.8; w <= 1.4; w += 0.1) {
      final wt = double.parse(w.toStringAsFixed(1));
      phrases.add('ওজন $wt kg — LBW (কম ওজন)। SNCU-তে রেফার করুন।');
    }

    // MUAC < 11.5 (SAM)
    for (double m = 8.0; m < 11.5; m += 0.1) {
      final muac = double.parse(m.toStringAsFixed(1));
      phrases.add('MUAC $muac cm — SAM (গুরুতর অপুষ্টি)! NRC-তে রেফার করুন।');
    }

    // BP severe — systolic ≥ 140 (pre-eclampsia)
    // Cover common observed pairs only — full enumeration would be 60×40 = too many.
    const sysBpHigh = [140, 145, 150, 155, 160, 165, 170, 175, 180, 190, 200];
    const diaBpHigh = [80, 85, 90, 95, 100, 105, 110, 115, 120];
    for (final s in sysBpHigh) {
      for (final d in diaBpHigh) {
        if (d >= s) continue; // dia must be below sys
        phrases.add('BP $s.0/$d — প্রি-এক্লাম্পসিয়া! বাম কাতে শোয়ান, ১০৮ কল করুন।');
      }
    }

    return phrases;
  }

  // ── Source 5: vital alerts (YELLOW — urgent tone) ──────────────────────────
  static List<String> _vitalAlertsUrgent() {
    final phrases = <String>[];

    // Child/general fever 38.6-41.0°C (> 38.5 = YELLOW)
    for (double t = 38.6; t <= 41.0; t += 0.1) {
      final temp = double.parse(t.toStringAsFixed(1));
      phrases.add('জ্বর ${temp}°C — উচ্চ জ্বর। PHC-তে নিয়ে যান।');
    }

    // Delivery_pnc fever 38.1-40.0°C (> 38.0 = YELLOW for postpartum)
    for (double t = 38.1; t <= 40.0; t += 0.1) {
      final temp = double.parse(t.toStringAsFixed(1));
      phrases.add('জ্বর ${temp}°C — পিউরপেরাল সেপসিসের ঝুঁকি! FRU-তে রেফার করুন।');
    }

    // SpO2 90-93 (mild hypoxia)
    for (int s = 90; s < 94; s++) {
      phrases.add('SpO2 $s% — কম অক্সিজেন। FRU-তে রেফার করুন।');
    }

    // General RR > 50 (fast breathing, child/infant)
    for (int r = 51; r <= 80; r++) {
      phrases.add('শ্বাসের হার $r/মিনিট — দ্রুত শ্বাস। PHC-তে নিয়ে যান।');
    }

    // MUAC 11.5-12.4 (MAM)
    for (double m = 11.5; m < 12.5; m += 0.1) {
      final muac = double.parse(m.toStringAsFixed(1));
      phrases.add('MUAC $muac cm — MAM (মাঝারি অপুষ্টি)। ICDS-তে রেফার করুন।');
    }

    // BP mild — systolic 130-139
    const sysBpMild = [130, 132, 134, 135, 136, 138];
    for (final s in sysBpMild) {
      phrases.add('BP $s.0 — উচ্চ রক্তচাপ। ২৪ ঘণ্টার মধ্যে PHC-তে নিয়ে যান।');
    }

    return phrases;
  }
}
