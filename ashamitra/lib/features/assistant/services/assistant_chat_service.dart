// ─────────────────────────────────────────────────────────────────────────────
// AssistantChatService — free-form Gemini-Live-style conversational service
//
// Used by AssistantScreen for general knowledge, clinical doubts, casual
// chat, encouragement. Different from GeminiConversationService (which is
// strictly for the structured triage protocol).
//
// Key behaviours:
//   - Bilingual mode: opening in app's selected language; after user
//     speaks, ASHA Mitra responds in user's spoken language (mix-language
//     code-switching tolerated).
//   - Detects clinical content vs general queries and flags when a
//     "save as report?" prompt should be offered to the worker.
//   - Backed by the same /api/chat backend (Groq primary, Gemini
//     fallback with key rotation, plus AiCache so repeat questions are
//     instant + free).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';

enum AssistantLang { bn, hi, en }

extension AssistantLangX on AssistantLang {
  String get code => switch (this) {
        AssistantLang.bn => 'bn',
        AssistantLang.hi => 'hi',
        AssistantLang.en => 'en',
      };
  String get bengaliLabel => switch (this) {
        AssistantLang.bn => 'বাংলা',
        AssistantLang.hi => 'হিন্দি',
        AssistantLang.en => 'ইংরেজি',
      };
  /// STT locale (speech_to_text plugin)
  String get sttLocale => switch (this) {
        AssistantLang.bn => 'bn_IN',
        AssistantLang.hi => 'hi_IN',
        AssistantLang.en => 'en_IN',
      };
  /// Device TTS locale (flutter_tts plugin)
  String get ttsLocale => switch (this) {
        AssistantLang.bn => 'bn-IN',
        AssistantLang.hi => 'hi-IN',
        AssistantLang.en => 'en-IN',
      };
  static AssistantLang fromIndex(int i) => switch (i) {
        0 => AssistantLang.bn,
        1 => AssistantLang.hi,
        2 => AssistantLang.en,
        _ => AssistantLang.bn,
      };
}

class AssistantTurn {
  final String role; // 'user' or 'assistant'
  final String text;
  const AssistantTurn({required this.role, required this.text});
}

class AssistantResponse {
  /// Sentence-cased reply text the orb will speak + display.
  final String text;

  /// Language the assistant detected in the user's last utterance.
  /// The next TTS pass uses this language so the worker hears their
  /// own language back, even if it differs from the app's setting.
  final AssistantLang detectedLanguage;

  /// True when the user's input describes a real patient situation
  /// (2+ symptoms, refers to a specific patient, mentions referral).
  /// The screen uses this to show the "Save as report?" inline action.
  final bool isClinical;

  /// True when the assistant explicitly recommends offering the save
  /// prompt this turn (covers cases where one clear danger sign alone
  /// warrants saving a record).
  final bool shouldOfferSave;

  const AssistantResponse({
    required this.text,
    required this.detectedLanguage,
    required this.isClinical,
    required this.shouldOfferSave,
  });
}

class AssistantChatService {
  /// [appLanguage] — what the user picked in Settings. Used for the
  /// *first* response and as a fallback if language detection on the
  /// user's input is ambiguous.
  Future<AssistantResponse> ask({
    required String userInput,
    required List<AssistantTurn> history,
    required AssistantLang appLanguage,
  }) async {
    final prompt = _buildPrompt(
      userInput: userInput,
      history: history,
      appLanguage: appLanguage,
    );

    http.Response? res;
    try {
      res = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      return _offlineFallback(userInput, appLanguage);
    }

    if (res.statusCode != 200) {
      return _offlineFallback(userInput, appLanguage);
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (body['text'] as String? ?? '')
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AssistantResponse(
        text: (j['spoken_text'] as String? ?? '').trim(),
        detectedLanguage: _parseLang(j['detected_language']?.toString() ?? appLanguage.code),
        isClinical: (j['is_clinical'] as bool?) ?? false,
        shouldOfferSave: (j['should_offer_save'] as bool?) ?? false,
      );
    } catch (_) {
      // LLM returned plain text, not JSON — still useful. Use raw as the
      // spoken text and assume non-clinical.
      return AssistantResponse(
        text: raw.isEmpty ? _genericReply(appLanguage) : raw,
        detectedLanguage: _heuristicLang(userInput, appLanguage),
        isClinical: false,
        shouldOfferSave: false,
      );
    }
  }

  // ── Prompt construction ──────────────────────────────────────────────────

  String _buildPrompt({
    required String userInput,
    required List<AssistantTurn> history,
    required AssistantLang appLanguage,
  }) {
    final historyText = history.isEmpty
        ? '(কোনো পূর্বের কথোপকথন নেই)'
        : history
            .take(8)
            .map((t) => '${t.role == "user" ? "ASHA" : "Mitra"}: ${t.text}')
            .join('\n');

    return '''
তুমি "Asha Mitra" — গ্রামীণ ভারতের ASHA কর্মীদের জন্য একটি ভয়েস সহায়ক।
তুমি একজন উষ্ণ, বুদ্ধিমান দিদির মতো কথা বলো। তুমি সব কিছুই সাহায্য করতে পারো:
- ক্লিনিক্যাল প্রশ্ন (ORS কীভাবে বানাই, জ্বর কত হলে বিপদ, ANC কতবার)
- সাধারণ জ্ঞান, পুষ্টি, স্বাস্থ্য পরামর্শ
- দৈনন্দিন কথা, উৎসাহ, সাহস
- কোনো রোগীর বিষয়ে আলোচনা

── ভাষার নিয়ম (গুরুত্বপূর্ণ) ──
- অ্যাপের নির্বাচিত ভাষা: ${_langName(appLanguage)}
- ASHA যদি এই ভাষাতেই কথা বলেন → একই ভাষাতে উত্তর দাও
- ASHA যদি অন্য ভাষায় কথা বলেন (বাংলা/হিন্দি/ইংরেজি) → তৎক্ষণাৎ তাদের ভাষায় উত্তর দাও
- কোড-সুইচিং (মিশ্র ভাষা) ঠিক আছে — তাদের মতো করেই উত্তর দাও
- নিজে থেকে ভাষা বদলাবে না — যেটায় ASHA বললেন সেটায় উত্তর

── উত্তরের ধরন ──
- ১-৩ বাক্য, সংক্ষিপ্ত, কথোপকথনের মতো (লেকচার নয়)
- ক্লিনিক্যাল উত্তরে — সঠিক সংখ্যা (থ্রেশহোল্ড / ডোজ) সহ
- সাধারণ কথায় — উষ্ণ ও বন্ধুত্বপূর্ণ
- কখনো "আমি জানি না" বা "এটা আমার কাজ নয়" বলবে না — যা পারো বলো, পারলে কেস-এ ফিরিয়ে আনো

── ক্লিনিক্যাল কন্টেন্ট চিহ্নিতকরণ ──
যদি ASHA একজন রোগীর কথা বলেন (এক বা একাধিক উপসর্গ, রোগীর প্রসঙ্গ,
রেফারের কথা) — তাহলে `is_clinical: true` করো।
যদি ২+ উপসর্গ থাকে বা একটাও স্পষ্ট বিপদচিহ্ন (RED-band) থাকে —
`should_offer_save: true` করো। অ্যাপ তখন "Save as report?" জিজ্ঞেস করবে।

── ভাষা ডিটেক্ট ──
ASHA-র সর্বশেষ বার্তা কোন ভাষায় ছিল তা `detected_language` ফিল্ডে:
- বাংলা = "bn"
- হিন্দি = "hi"
- ইংরেজি = "en"

── পূর্বের কথোপকথন ──
$historyText

ASHA এইমাত্র বললেন: "$userInput"

শুধুমাত্র এই JSON দিয়ে উত্তর দাও (markdown ছাড়া):
{
  "spoken_text": "১-৩ বাক্যের প্রাকৃতিক উত্তর — ASHA-র ভাষায়",
  "detected_language": "bn|hi|en",
  "is_clinical": false,
  "should_offer_save": false
}
''';
  }

  String _langName(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'বাংলা (Bengali)',
        AssistantLang.hi => 'हिन्दी (Hindi)',
        AssistantLang.en => 'English',
      };

  AssistantLang _parseLang(String code) => switch (code.toLowerCase()) {
        'bn' => AssistantLang.bn,
        'hi' => AssistantLang.hi,
        'en' => AssistantLang.en,
        _ => AssistantLang.bn,
      };

  // ── Heuristic language detection (offline / non-JSON fallback) ───────────
  // Counts Bengali vs Devanagari vs Latin codepoints in the input.
  AssistantLang _heuristicLang(String input, AssistantLang fallback) {
    int bn = 0, hi = 0, en = 0;
    for (final rune in input.runes) {
      if (rune >= 0x0980 && rune <= 0x09FF) {
        bn++;
      } else if (rune >= 0x0900 && rune <= 0x097F) {
        hi++;
      } else if ((rune >= 0x0041 && rune <= 0x007A)) {
        en++;
      }
    }
    if (bn > hi && bn > en) return AssistantLang.bn;
    if (hi > bn && hi > en) return AssistantLang.hi;
    if (en > bn && en > hi) return AssistantLang.en;
    return fallback;
  }

  AssistantResponse _offlineFallback(String input, AssistantLang appLanguage) {
    final detected = _heuristicLang(input, appLanguage);
    return AssistantResponse(
      text: _offlineMessage(detected),
      detectedLanguage: detected,
      isClinical: false,
      shouldOfferSave: false,
    );
  }

  String _offlineMessage(AssistantLang l) => switch (l) {
        AssistantLang.bn =>
          'এখন ইন্টারনেট সংযোগ নেই। আপনার প্রশ্ন মনে রাখুন — অনলাইন হলে উত্তর দেবো। এখন আপনি ট্রায়াজ চালু রাখতে পারেন।',
        AssistantLang.hi =>
          'अभी इंटरनेट नहीं है। आपका सवाल याद रखें — ऑनलाइन होते ही जवाब दूँगी। अभी आप ट्रायाज जारी रख सकती हैं।',
        AssistantLang.en =>
          'No internet right now. Hold the question — I\'ll answer when we\'re online. Triage still works offline.',
      };

  String _genericReply(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'বুঝেছি দিদি, বলুন।',
        AssistantLang.hi => 'समझ गई दीदी, बताइए।',
        AssistantLang.en => 'I understand. Please tell me more.',
      };
}
