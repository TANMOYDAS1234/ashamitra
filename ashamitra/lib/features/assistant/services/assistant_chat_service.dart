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

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/services/ai_response_cache.dart';
import '../../../core/services/api_service.dart';

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

  /// MP3 bytes returned by the combined /chat-with-voice endpoint.
  /// When non-null the caller can play these directly via
  /// [TtsService.speakBytes] and skip the separate /tts round-trip,
  /// saving ~200-500ms on Render cold-start / weak signal.
  final List<int>? prefetchedAudio;

  const AssistantResponse({
    required this.text,
    required this.detectedLanguage,
    required this.isClinical,
    required this.shouldOfferSave,
    this.prefetchedAudio,
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

    // On-device cache check first — same normalized prompt has been
    // answered before → instant reply, zero network, works offline.
    // Same disk store as the triage flow (AiResponseCache), so any
    // prompt either path warms also helps the other.
    final cache = AiResponseCache();
    final cached = await cache.get(prompt);
    Map<String, dynamic>? body;
    if (cached != null) {
      body = cached;
    } else {
      // Combined /chat-with-voice — one round-trip for text + MP3 instead
      // of the legacy two-call pattern. voiceField='spoken_text' tells the
      // server to pull only that sub-field from the LLM's structured JSON
      // for synthesis (so the user doesn't hear "is_clinical: true" etc).
      try {
        body = await ApiService.chatWithVoice(
          prompt: prompt,
          voiceField: 'spoken_text',
          tone: 'normal',
          timeout: const Duration(seconds: 25),
        );
      } catch (_) { /* fall through to offline */ }
    }

    // Fall back to legacy /api/chat if combined endpoint failed (e.g.
    // older server before the route landed, or transient 503).
    if (body == null) {
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
        return await _offlineFallback(userInput, appLanguage);
      }
      if (res.statusCode != 200) {
        return await _offlineFallback(userInput, appLanguage);
      }
      body = jsonDecode(res.body) as Map<String, dynamic>;
    }

    // Cache for offline reuse — strip the audio bytes (MP3s are cached
    // separately by VapiTtsService at the MP3 layer, and writing them
    // here would bloat the JSON cache fast). Fire-and-forget so the
    // user-facing latency isn't tied to disk write.
    if (cached == null && (body['text'] as String? ?? '').isNotEmpty) {
      final cachePayload = Map<String, dynamic>.from(body)
        ..remove('audio')
        ..remove('audioMime')
        ..remove('audioTone');
      unawaited(cache.put(prompt, cachePayload));
    }

    final raw = (body['text'] as String? ?? '')
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    List<int>? audioBytes;
    final audioB64 = body['audio'] as String?;
    if (audioB64 != null && audioB64.isNotEmpty) {
      try {
        audioBytes = base64Decode(audioB64);
      } catch (_) { /* fall back to /tts */ }
    }

    // Robust JSON extraction. The LLM sometimes returns prose + a JSON
    // block (especially Groq for short conversational prompts), e.g.
    //   "Sure, here's how:\n{\"spoken_text\":\"...\",...}"
    // jsonDecode(raw) fails in that case, and the old catch branch
    // rendered the whole blob — JSON included — as the chat message.
    // Now we scan for the first balanced {...} substring and parse
    // that; if no JSON is present at all we fall through to the
    // plain-text path (and strip any leftover JSON-looking tail).
    final jsonStr = _extractJsonObject(raw);
    if (jsonStr != null) {
      try {
        final j = jsonDecode(jsonStr) as Map<String, dynamic>;
        final spoken = (j['spoken_text'] as String? ?? '').trim();
        if (spoken.isNotEmpty) {
          return AssistantResponse(
            text: spoken,
            detectedLanguage: _parseLang(
                j['detected_language']?.toString() ?? appLanguage.code),
            isClinical: (j['is_clinical'] as bool?) ?? false,
            shouldOfferSave: (j['should_offer_save'] as bool?) ?? false,
            prefetchedAudio: audioBytes,
          );
        }
      } catch (_) { /* malformed JSON — fall through */ }
    }

    // No usable JSON — strip any trailing {...} from the prose so the
    // chat bubble never shows raw structured fields. If the whole reply
    // was prose, this is a no-op.
    final plainText = raw.replaceAll(
      RegExp(r'\s*\{[\s\S]*\}\s*$', multiLine: true), '',
    ).trim();
    return AssistantResponse(
      text: plainText.isEmpty ? _genericReply(appLanguage) : plainText,
      detectedLanguage: _heuristicLang(userInput, appLanguage),
      isClinical: false,
      shouldOfferSave: false,
      prefetchedAudio: audioBytes,
    );
  }

  /// Scans [raw] for the first balanced JSON object {...} and returns
  /// it as a substring, or null if no balanced object is found.
  /// Naive brace counter — good enough since our schema has no
  /// nested braces inside strings.
  String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    for (var i = start; i < raw.length; i++) {
      final c = raw[i];
      if (c == '{') depth++;
      else if (c == '}') {
        depth--;
        if (depth == 0) return raw.substring(start, i + 1);
      }
    }
    return null;
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
তুমি "আশামিত্র" — পশ্চিমবঙ্গের ASHA দিদিদের জন্য একজন অভিজ্ঞ বড় দিদি।
তুমি কথা বলো ঠিক যেমন বাংলার একজন বুদ্ধিমান, যত্নশীল দিদি কথা বলেন —
সহজ, উষ্ণ, কাজের কথা। কখনো বইয়ের মতো বা মেশিনের মতো নয়।

── কীভাবে কথা বলবে (অত্যন্ত গুরুত্বপূর্ণ — মানুষের মতো ভাব আনতে) ──
✅ ব্যবহার করো (স্বাভাবিক বাংলা/ভারতীয় কথ্য ভঙ্গি):
   - সম্বোধন: "দিদি", "ও দিদি" (অতিরিক্ত নয় — মাঝে মাঝে)
   - কথোপকথনের শব্দ: "আচ্ছা", "হ্যাঁ গো", "শুনুন তো", "জানেন কি"
   - সহজ পরামর্শ: "একটু দেখুন তো", "আস্তে আস্তে বলুন", "চিন্তা করবেন না"
   - মিশ্র ভাষা যেখানে স্বাভাবিক: "ORS করতে হবে", "BP মাপুন", "vaccine দিতে হবে"
   - ছোট বাক্য, কথ্য ছন্দ — বইয়ের ভাষা নয়

❌ এড়াও (যান্ত্রিক / অস্বাভাবিক):
   - "অনুগ্রহ করে অবগত হোন যে..." — আরে না!
   - "এটি একটি গুরুত্বপূর্ণ বিষয়" — পরিবর্তে: "এটা খুব দরকারি ব্যাপার"
   - একই শব্দ দিয়ে প্রতিবার শুরু করা ("নমস্কার..." প্রতি উত্তরে নয়)
   - তালিকা বানিয়ে বলা ("প্রথমত, দ্বিতীয়ত, তৃতীয়ত" — না)
   - অতিরিক্ত আনুষ্ঠানিক টোন
   - একই বাক্যাংশ বারবার ("আমি বুঝতে পারছি..." প্রতিবার)

── উদাহরণ (এই ভাবেই বলো) ──
ASHA: "জ্বর কত হলে নবজাতকের বিপদ?"
ভালো: "নবজাতকের ক্ষেত্রে ৩৭.৫°C-এর উপরে গেলেই কিন্তু বিপদ, দিদি।
       সঙ্গে সঙ্গে SNCU বা PHC-তে রেফার করুন।"
খারাপ: "নবজাতকের জন্য জ্বরের সীমা ৩৭.৫°C। এই সীমার অধিক হইলে চিকিৎসকের
       পরামর্শ গ্রহণ করুন।" ← বইয়ের ভাষা, যান্ত্রিক

ASHA: "একটু ক্লান্ত লাগছে।"
ভালো: "আরে দিদি, এতো কাজ করেন, একটু চা খেয়ে নিন তো। জল খান বেশি করে।
       কোনো রোগীর কথা বলবেন?"
খারাপ: "আপনার বিশ্রামের প্রয়োজন। পর্যাপ্ত জল পান করুন।" ← উষ্ণতা নেই

── ভাষার নিয়ম (গুরুত্বপূর্ণ) ──
- অ্যাপের নির্বাচিত ভাষা: ${_langName(appLanguage)}
- ASHA যেই ভাষায় কথা বলেন, সেই ভাষায় উত্তর — বাংলা/হিন্দি/ইংরেজি
- হিন্দিতে: ভারতীয় টোন, "दीदी" সম্বোধন, "जी" শেষে
- ইংরেজিতে: ভারতীয় English-ই — "Tell me, didi" / "Don't worry, it's manageable"
- কোড-মিশ্র স্বাভাবিক — যেমন ASHA বলেন তেমনই
- নিজে থেকে ভাষা বদলাবে না

── উত্তরের ধরন ──
- ১-৩ ছোট বাক্য — কথোপকথন, লেকচার নয়
- ক্লিনিক্যাল হলে — সঠিক সংখ্যা / ডোজ স্বাভাবিকভাবে বুনে দাও
- কখনো "আমি জানি না" বলবে না — যা পারো বলো
- প্রশ্নের উত্তর দাও, তারপর প্রয়োজনে নরমভাবে কেসে ফেরাও

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

তোমার সম্পূর্ণ উত্তর হবে শুধুমাত্র নিচের JSON অবজেক্ট — অন্য কিছু নয়।
JSON-এর আগে বা পরে কোনো বাক্য, কোনো প্রস্তাবনা, কোনো ```json``` ফেন্স লিখবে না।
JSON খোলা ব্রেস `{` দিয়ে শুরু হবে, বন্ধ ব্রেস `}` দিয়ে শেষ হবে।
তোমার আসল উত্তরটি (যা ASHA শুনবে) "spoken_text" ফিল্ডের ভিতরে যাবে।

{
  "spoken_text": "১-৩ বাক্যের প্রাকৃতিক উত্তর — ASHA-র ভাষায়",
  "detected_language": "bn|hi|en",
  "is_clinical": false,
  "should_offer_save": false
}

❌ ভুল (এটা করবে না):
   আরে দিদি, চা বানানোর জন্য পানি ফুটতে দিন।
   {"spoken_text": "...", ...}
   ← JSON-এর আগে বাক্য লিখো না!

✅ সঠিক:
   {"spoken_text": "আরে দিদি, চা বানানোর জন্য পানি ফুটতে দিন।", "detected_language": "bn", "is_clinical": false, "should_offer_save": false}
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

  /// Returns the right fallback message based on WHY the network call
  /// failed. Without this check, every server-side failure (cold-start,
  /// rate-limit, 503) was reported as "no internet" — which made the
  /// worker blame their connection even when they had full bars. Now we
  /// actually verify connectivity first and choose the message accordingly.
  Future<AssistantResponse> _offlineFallback(
      String input, AssistantLang appLanguage) async {
    final detected = _heuristicLang(input, appLanguage);
    final connectivity = await Connectivity().checkConnectivity();
    final hasNetwork =
        connectivity.any((c) => c != ConnectivityResult.none);
    return AssistantResponse(
      text: hasNetwork
          ? _serverSlowMessage(detected)
          : _offlineMessage(detected),
      detectedLanguage: detected,
      isClinical: false,
      shouldOfferSave: false,
    );
  }

  String _offlineMessage(AssistantLang l) => switch (l) {
        AssistantLang.bn =>
          'এখন ইন্টারনেট সংযোগ নেই। অনলাইন হলে আবার চেষ্টা করুন। এখন আপনি ট্রায়াজ চালু রাখতে পারেন।',
        AssistantLang.hi =>
          'अभी इंटरनेट नहीं है। ऑनलाइन होने पर फिर कोशिश करें। अभी आप ट्रायाज जारी रख सकती हैं।',
        AssistantLang.en =>
          'No internet right now. Please try again when online. Triage still works offline.',
      };

  String _serverSlowMessage(AssistantLang l) => switch (l) {
        AssistantLang.bn =>
          'সার্ভার এখন একটু ধীর, একটু অপেক্ষা করে আবার চেষ্টা করুন।',
        AssistantLang.hi =>
          'सर्वर अभी थोड़ा धीमा है, थोड़ी देर बाद फिर पूछें।',
        AssistantLang.en =>
          'The server is slow right now, please try again in a moment.',
      };

  String _genericReply(AssistantLang l) => switch (l) {
        AssistantLang.bn => 'বুঝেছি দিদি, বলুন।',
        AssistantLang.hi => 'समझ गई दीदी, बताइए।',
        AssistantLang.en => 'I understand. Please tell me more.',
      };
}
