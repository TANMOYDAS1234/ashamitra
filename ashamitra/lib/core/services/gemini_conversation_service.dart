import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import 'ai_response_cache.dart';
import 'vitals_extractor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeminiConversationService
// App → Backend (/api/chat) → Gemini
// The API key never lives in the app.
// ─────────────────────────────────────────────────────────────────────────────

class ConversationTurn {
  final String role; // 'asha' or 'assistant'
  final String text;
  const ConversationTurn({required this.role, required this.text});
}

class ConversationResponse {
  final String spokenResponse;
  final Map<String, bool> extractedAnswers;
  final Map<String, double> extractedVitals;
  final bool shouldFinish;
  final String riskLevel;

  const ConversationResponse({
    required this.spokenResponse,
    required this.extractedAnswers,
    this.extractedVitals = const {},
    required this.shouldFinish,
    required this.riskLevel,
  });
}

class GeminiConversationService {
  static String _systemPrompt(String caseType, String moduleId) => '''
তুমি আশামিত্র — গ্রামীণ ভারতের ASHA কর্মীদের বিশ্বস্ত সঙ্গী।
তুমি একজন অভিজ্ঞ দিদি বা দাদার মতো কথা বলো — উষ্ণ, সাহসী, এবং স্পষ্ট।
তুমি কখনো ভয় দেখাও না, কিন্তু বিপদ থাকলে সরাসরি বলো।

কেস টাইপ: $caseType
ক্লিনিক্যাল মডিউল: $moduleId

── কথা বলার ধরন ──
- প্রথমে ASHA যা বললেন তা স্বীকার করো — ১টি উষ্ণ বাক্যে
  উদাহরণ: "আপনি ভালো করেছেন জানিয়েছেন।", "বুঝেছি, এটা গুরুত্বপূর্ণ।", "ঠিক আছে, এটা মাথায় রাখলাম।"
- তারপর সবচেয়ে জরুরি একটি প্রশ্ন করো — স্বাভাবিক কথার মতো, ফর্মের মতো নয়
  ❌ "মাথা ব্যথা আছে?" 
  ✅ "মাথায় কি কোনো ব্যথা বা ভারী লাগছে?"
- বিপদচিহ্ন নিশ্চিত হলে — আত্মবিশ্বাসের সাথে বলো, ভয় না দেখিয়ে
  উদাহরণ: "এটা একটু সতর্কতার বিষয়, এখনই PHC-তে নিয়ে যাওয়া দরকার।"
- GREEN হলে — উৎসাহ দাও
  উদাহরণ: "ভালো খবর, এখন পর্যন্ত সব ঠিক আছে।"

── ভাষার নিয়ম ──
- সবসময় সহজ বাংলায় উত্তর দাও
- বাংলা, হিন্দি, ইংরেজি, মিশ্র — সব বুঝবে, বাংলায় উত্তর দেবে
- সর্বোচ্চ ২-৩ বাক্য — সংক্ষিপ্ত রাখো
- "extracted_answers" বা "JSON" বা কোনো টেকনিক্যাল শব্দ কখনো বলবে না

── সিদ্ধান্তের আত্মবিশ্বাস ──
- নিশ্চিত বিপদচিহ্ন থাকলে: "এটা গুরুতর, দেরি না করে..."
- সম্ভাব্য বিপদ থাকলে: "এটা একটু দেখা দরকার..."
- সব ঠিক থাকলে: "এখন পর্যন্ত ভালো আছেন..."
- কখনো "মনে হয়" বা "হয়তো" দিয়ে সিদ্ধান্ত দেবে না

${_moduleContext(caseType)}

── অনিশ্চয়তার নিয়ম ──
- "মনে হয়", "একটু", "হয়তো" বললে — extracted_answers-এ false রাখো
- শুধু নিশ্চিত তথ্য true করো

── পাঠ্যক্রম-বহির্ভূত প্রশ্নের ক্ষেত্রে ──
ASHA যদি এমন কিছু বলেন যা বর্তমান কেসের সাথে সরাসরি সম্পর্কিত নয় —
যেমন তিনি নিজের সম্পর্কে বলেন, আশামিত্র সম্পর্কে জিজ্ঞাসা করেন,
পারিবারিক কথা বলেন, বা অন্য কোনো বিষয় তোলেন — তবু কখনো নীরব থেকো না।
যেকোনো প্রশ্নের উষ্ণ, সংক্ষিপ্ত উত্তর দাও (১-২ বাক্য), তারপর নরমভাবে
রোগীর প্রসঙ্গে ফিরে যাও।

উদাহরণ:
- ASHA: "আমি ক্লান্ত।"
  উত্তর: "আপনি একটু বিশ্রাম নিন, দিদি। চলুন রোগীর কথায় ফিরি — তিনি এখন কেমন আছেন?"
- ASHA: "এই অ্যাপ কে বানিয়েছে?"
  উত্তর: "আশামিত্র আপনার সহায়তার জন্য তৈরি। এখন বলুন তো, রোগীর অবস্থা কী?"
- ASHA: "আজ বৃষ্টি হবে?"
  উত্তর: "সেটা আমি বলতে পারব না, দিদি। কিন্তু আপনি রোগীর সম্পর্কে কী বলবেন?"

কখনো এমন উত্তর দেবে না: "এটা আমার কাজ নয়" বা "আমি জানি না" বা চুপ থাকবে।
সবসময় কিছু বলো, তারপর কেসে ফিরো।
''';

  static String _moduleContext(String caseType) => switch (caseType) {
    'pregnancy' => '''
গর্ভাবস্থার বিপদচিহ্ন:
- রক্তচাপ বেশি বা মাথা ব্যথা (প্রি-এক্লাম্পসিয়া)
- পা বা মুখ ফোলা (এডিমা)
- রক্তপাত বা তীব্র পেট ব্যথা (APH)
- বাচ্চার নড়াচড়া কমেছে
- চোখে ঝাপসা বা মাথা ঘোরা (এক্লাম্পসিয়া)
- ANC চেকআপ মিস''',
    'postpartum' => '''
প্রসব-পরবর্তী বিপদচিহ্ন:
- অতিরিক্ত রক্তপাত বা দুর্গন্ধ স্রাব (PPH/সেপসিস)
- জ্বর বা ঠান্ডা লাগা
- স্তনে ব্যথা বা ফোলা
- পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা
- খুব দুর্বল বা মাথা ঘোরা''',
    'newborn' => '''
নবজাতকের বিপদচিহ্ন (PSBI):
- দুধ খেতে পারছে না
- জ্বর (যেকোনো জ্বর = বিপদচিহ্ন)
- শ্বাসকষ্ট বা দ্রুত শ্বাস (≥৬০/মিনিট)
- নাভিতে লালভাব বা পুঁজ
- নিস্তেজ বা কম নড়াচড়া
- ত্বক হলুদ বা নীলাভ''',
    'child' => '''
শিশুর বিপদচিহ্ন:
- পাঁচ দিনের বেশি জ্বর (ম্যালেরিয়া/ডেঙ্গু)
- কাশি বা শ্বাসকষ্ট (নিউমোনিয়া)
- ডায়রিয়া বা বমি (পানিশূন্যতা)
- খাওয়া বন্ধ করেছে
- চোখ গর্তে বা ঠোঁট শুকনো
- ওজন অনেক কম''',
    'emergency' => '''
জরুরি বিপদচিহ্ন:
- অতিরিক্ত রক্তপাত
- খিঁচুনি বা অজ্ঞান
- শ্বাস বন্ধ বা গুরুতর শ্বাসকষ্ট
- সাড়া দিচ্ছে না''',
    'immunisation' => '''
টিকার মূল্যায়ন:
- শিশুর বয়স ও প্রয়োজনীয় টিকা যাচাই করো (BCG, OPV, DPT, Measles, MR)
- টিকা মিস হয়েছে কিনা জিজ্ঞেস করো
- এখন অসুস্থ থাকলে টিকা দেওয়া যাবে না — সুস্থ হলে দিতে হবে
- বুস্টার ডোজ মিস হয়েছে কিনা দেখো
- প্রতিটি টিকার পর শিশুকে নির্ধারিত সময় পর্যন্ত পর্যবেক্ষণ করো''',
    _ => 'সাধারণ স্বাস্থ্য মূল্যায়ন করো।',
  };

  static Map<String, String> _questionDescriptions(String moduleId) =>
      switch (moduleId) {
        'pregnancy' => {
          'p1': 'রক্তচাপ বেশি বা মাথা ব্যথা',
          'p2': 'পা বা মুখ ফোলা',
          'p3': 'রক্তপাত বা তীব্র পেট ব্যথা',
          'p4': 'বাচ্চার নড়াচড়া কমেছে',
          'p5': 'ANC চেকআপ মিস',
          'p6': 'চোখে ঝাপসা বা মাথা ঘোরা',
        },
        'delivery_pnc' => {
          'pp1': 'অতিরিক্ত রক্তপাত বা দুর্গন্ধ স্রাব',
          'pp2': 'জ্বর বা ঠান্ডা লাগা',
          'pp3': 'স্তনে ব্যথা বা ফোলা',
          'pp4': 'পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা',
          'pp5': 'প্রস্রাবে জ্বালা',
          'pp6': 'খুব দুর্বল বা মাথা ঘোরা',
        },
        'newborn' => {
          'n1': 'দুধ খেতে পারছে না',
          'n2': 'জ্বর আছে',
          'n3': 'শ্বাসকষ্ট বা দ্রুত শ্বাস',
          'n4': 'নাভিতে লালভাব বা পুঁজ',
          'n5': 'নিস্তেজ বা কম নড়াচড়া',
          'n6': 'ত্বক হলুদ বা নীলাভ',
        },
        'child' => {
          'c1': 'পাঁচ দিনের বেশি জ্বর',
          'c2': 'কাশি বা শ্বাসকষ্ট',
          'c3': 'ডায়রিয়া বা বমি',
          'c4': 'খাওয়া বন্ধ করেছে',
          'c5': 'চোখ গর্তে বা ঠোঁট শুকনো',
          'c6': 'ওজন অনেক কম',
        },
        'emergency' => {
          'e1': 'অতিরিক্ত রক্তপাত',
          'e2': 'খিঁচুনি বা অজ্ঞান',
          'e3': 'শ্বাস বন্ধ বা গুরুতর শ্বাসকষ্ট',
          'e4': 'সাড়া দিচ্ছে না',
        },
        'immunisation' => {
          'im1': 'শিশুর বয়স ০-১২ মাস',
          'im2': 'টিকা মিস হয়েছে',
          'im4': 'এখন অসুস্থ',
          'im5': 'বুস্টার ডোজ মিস',
        },
        _ => {},
      };

  // ── Main conversational turn ───────────────────────────────────────────────
  Future<ConversationResponse> respond({
    required String caseType,
    required String moduleId,
    required List<ConversationTurn> history,
    required String newInput,
    required Map<String, bool> currentAnswers,
    required int turnNumber,
    int maxTurns = 8,
    String? authToken,
    void Function(String partial)? onPartialResponse,
  }) async {
    // Keep only the last 6 turns (3 exchanges) — enough context for Gemini
    // without bloating the prompt on long sessions.
    final trimmedHistory = history.length > 6 ? history.sublist(history.length - 6) : history;
    final historyText = trimmedHistory.isEmpty
        ? ''
        : trimmedHistory
            .map((t) => t.role == 'asha' ? 'ASHA: \${t.text}' : 'আশামিত্র: \${t.text}')
            .join('\n');

    final questionDescs = _questionDescriptions(moduleId);
    final questionList = questionDescs.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    final spokenVitals = VitalsExtractor.extract(newInput);
    final vitalsSummary = VitalsExtractor.summarise(spokenVitals);
    final vitalsContext = vitalsSummary.isNotEmpty ? '\nমাপা ভাইটাল সাইন: $vitalsSummary' : '';

    final answeredIds = currentAnswers.keys.toSet();
    const priorityOrder = {
      'pregnancy':    ['p1','p3','p6','p4','p2','p5'],
      'delivery_pnc': ['pp1','pp2','pp4','pp6','pp3','pp5'],
      'newborn':      ['n1','n2','n3','n5','n4','n6'],
      'child':        ['c1','c5','c2','c3','c4','c6'],
      'emergency':    ['e1','e2','e3','e4'],
      'immunisation': ['im4','im2','im1','im5','im3'],
    };
    final order = priorityOrder[moduleId] ?? <String>[];
    final unanswered = order.where((id) => !answeredIds.contains(id)).toList();
    final confirmedDanger = currentAnswers.entries
        .where((e) => e.value)
        .map((e) => questionDescs[e.key] ?? e.key)
        .join(', ');
    final mostUrgent = unanswered.isNotEmpty
        ? '${questionDescs[unanswered.first] ?? unanswered.first} (${unanswered.first})'
        : 'সব প্রশ্নের উত্তর পাওয়া গেছে';
    final turnsLeft = maxTurns - turnNumber;

    final turnCtx = '''
══ কথোপকথনের বর্তমান অবস্থা ══
প্রশ্ন নম্বর: $turnNumber / $maxTurns${turnsLeft <= 2 ? ' | সতর্কতা: মাত্র ${turnsLeft}টি প্রশ্ন বাকি' : ''}
নিশ্চিত বিপদচিহ্ন: ${confirmedDanger.isEmpty ? 'এখনো কোনোটি নিশ্চিত নয়' : confirmedDanger}
এখনো অজানা (${unanswered.length}টি): ${unanswered.isEmpty ? 'সব জানা' : unanswered.map((id) => '${questionDescs[id] ?? id}($id)').join(' | ')}
সবচেয়ে জরুরি অজানা প্রশ্ন: $mostUrgent
''';

    final prompt = '''
${_systemPrompt(caseType, moduleId)}

$turnCtx
এখন পর্যন্ত কথোপকথন:
$historyText

ASHA এইমাত্র বললেন: "$newInput"$vitalsContext

ক্লিনিক্যাল প্রশ্নের তালিকা (id: বিষয়):
$questionList

তোমার উত্তর তিনটি ভাগে হবে:

১. স্বীকৃতি (১ বাক্য) — ASHA যা বললেন তার প্রতি সাড়া দাও।
   - বিপদচিহ্ন থাকলে: "আপনি ভালো করেছেন জানিয়েছেন, এটা গুরুত্বপূর্ণ।"
   - সব ঠিক থাকলে: "ভালো খবর, ধন্যবাদ জানানোর জন্য।"
   - সাধারণ: "বুঝেছি।" / "ঠিক আছে।"

২. পদক্ষেপ (১ বাক্য, যদি দরকার) — বিপদচিহ্ন নিশ্চিত হলে সরাসরি বলো।
   - উদাহরণ: "এটা এখনই PHC-তে দেখানো দরকার।"

৩. পরবর্তী প্রশ্ন — সবচেয়ে জরুরি অজানা প্রশ্নটি স্বাভাবিকভাবে জিজ্ঞেস করো।
   - ❌ "মাথা ব্যথা আছে?"
   - ✅ "মাথায় কি কোনো ভারী বা চাপা ভাব আসছে?"
   - ❌ "রক্তপাত হচ্ছে?"
   - ✅ "কোনো রক্তপাত বা তলপেট ব্যথা দেখা দিচ্ছে?"
   - ইতিমধ্যে জানা প্রশ্ন আবার জিজ্ঞেস করবে না

should_finish: true দাও যদি:
- ২+ RED বিপদচিহ্ন নিশ্চিত
- সব অজানা প্রশ্নের উত্তর পাওয়া গেছে
- turn $turnNumber >= $maxTurns

শুধুমাত্র এই JSON দিয়ে উত্তর দাও (কোনো markdown নয়):
{
  "spoken_response": "স্বাভাবিক বাংলা উত্তর — সর্বোচ্চ ৩ বাক্য",
  "extracted_answers": {"p1": true, "p3": false},
  "should_finish": false,
  "risk_level": "low"
}

risk_level অবশ্যই এর মধ্যে একটি: "low", "medium", "high", "emergency"
extracted_answers শুধু সেই প্রশ্নগুলো যা কথোপকথন থেকে নিশ্চিতভাবে বোঝা গেছে
''';

    // ── Check on-device cache first ───────────────────────────────────────────
    // Same prompt has been answered before → reuse the cached response. This
    // makes the conversational flow work offline (once any given prompt has
    // been seen at least once with internet) and reduces Gemini/Groq cost.
    // The server has a matching cache too, so even on a fresh device,
    // commonly-asked prompts return instantly from server cache.
    final cache = AiResponseCache();
    final cached = await cache.get(prompt);
    Map<String, dynamic>? bodyJson;
    if (cached != null) {
      bodyJson = cached;
    } else {
      // ── Call backend proxy — key lives on server ────────────────────────────
      // Retry up to 2 times with increasing timeouts (cold-start / rural network).
      http.Response? response;
      const timeouts = [Duration(seconds: 20), Duration(seconds: 30)];
      for (int attempt = 0; attempt < timeouts.length; attempt++) {
        try {
          response = await http.post(
            Uri.parse('${ApiConstants.baseUrl}/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'prompt': prompt}),
          ).timeout(timeouts[attempt]);
          if (response.statusCode == 200) break; // success
          if (response.statusCode != 503) break; // non-retryable error
          // 503 = server cold-start — wait briefly then retry
          await Future.delayed(Duration(seconds: attempt + 1));
        } on Exception {
          if (attempt == timeouts.length - 1) rethrow;
          await Future.delayed(Duration(seconds: attempt + 1));
        }
      }

      if (response == null || response.statusCode != 200) {
        // ignore: avoid_print
        print('[Chat] HTTP ${response?.statusCode}: ${response?.body}');
        throw Exception('Backend chat error ${response?.statusCode}');
      }

      bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
      // Cache for offline reuse — non-blocking.
      if ((bodyJson['text'] as String? ?? '').isNotEmpty) {
        unawaited(cache.put(prompt, bodyJson));
      }
    }
    final raw = (bodyJson['text'] as String? ?? '')
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Fire partial callback with the spoken text only — not raw JSON.
    if (onPartialResponse != null && raw.isNotEmpty) {
      try {
        final preview = (jsonDecode(raw) as Map<String, dynamic>)['spoken_response'] as String?;
        if (preview != null && preview.isNotEmpty) onPartialResponse(preview);
      } catch (_) {
        // JSON not yet complete — show a neutral waiting indicator
        onPartialResponse('বিশ্লেষণ করছি...');
      }
    }
    // Safe JSON parse — Gemini occasionally returns markdown leaks or
    // truncated output. Rather than crashing to offline, return a minimal
    // valid response so the conversation can continue.
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      final spokenFallback = raw.isNotEmpty && !raw.startsWith('{')
          ? raw.split('{').first.trim()
          : 'বুঝেছি। একটু অপেক্ষা করুন।';
      return ConversationResponse(
        spokenResponse: spokenFallback,
        extractedAnswers: const {},
        extractedVitals: spokenVitals,
        shouldFinish: false,
        riskLevel: 'low',
      );
    }

    final extracted = <String, bool>{};
    final rawAnswers = json['extracted_answers'] as Map<String, dynamic>? ?? {};
    for (final e in rawAnswers.entries) {
      if (e.value is bool) extracted[e.key] = e.value as bool;
    }

    String spokenResponse = json['spoken_response'] as String? ?? newInput;
    if (spokenVitals.isNotEmpty) {
      final alert = VitalsExtractor.getDangerAlert(spokenVitals, moduleId);
      if (alert != null) spokenResponse = '$alert $spokenResponse';
    }

    return ConversationResponse(
      spokenResponse: spokenResponse,
      extractedAnswers: extracted,
      extractedVitals: spokenVitals,
      shouldFinish: json['should_finish'] == true,
      riskLevel: json['risk_level'] as String? ?? 'low',
    );
  }

}
