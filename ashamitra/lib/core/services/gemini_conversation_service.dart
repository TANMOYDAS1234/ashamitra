import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeminiConversationService — True free dialogue, not a question form
//
// Each turn:
//   1. ASHA speaks freely (any language, any length)
//   2. Gemini reads the FULL conversation history + case context
//   3. Returns a natural Bengali response that:
//        - Acknowledges what was said
//        - Gives immediate guidance if a danger sign was mentioned
//        - Asks the single most important follow-up question
//        - Extracts structured answers for the rule engine
//        - Decides when enough info is collected to conclude
// ─────────────────────────────────────────────────────────────────────────────

class ConversationTurn {
  final String role; // 'asha' or 'assistant'
  final String text;
  const ConversationTurn({required this.role, required this.text});
}

class ConversationResponse {
  /// Natural Bengali response to speak aloud — acknowledgement + guidance + next question
  final String spokenResponse;

  /// Structured answers extracted from the full conversation so far
  /// Maps engine question ID → bool (true = danger present)
  final Map<String, bool> extractedAnswers;

  /// True when Gemini has enough info to conclude — triggers rule engine
  final bool shouldFinish;

  /// Risk level Gemini detected: 'low', 'medium', 'high', 'emergency'
  final String riskLevel;

  const ConversationResponse({
    required this.spokenResponse,
    required this.extractedAnswers,
    required this.shouldFinish,
    required this.riskLevel,
  });
}

class GeminiConversationService {
  static String get _url => AppConfig.geminiUrlWithKey;

  // ── System prompt — defines the assistant's persona and rules ─────────────
  static String _systemPrompt(String caseType, String moduleId) => '''
তুমি আশামিত্র — একজন বিশেষজ্ঞ মেডিক্যাল সহকারী যিনি গ্রামীণ ভারতের ASHA কর্মীদের সাহায্য করেন।
তুমি একজন অভিজ্ঞ ডাক্তারের মতো কথা বলো — সহানুভূতিশীল, স্পষ্ট, এবং সরাসরি।

কেস টাইপ: $caseType
ক্লিনিক্যাল মডিউল: $moduleId

তোমার কাজ:
1. ASHA যা বলেছেন তা মনোযোগ দিয়ে শোনো
2. যদি কোনো বিপদচিহ্ন থাকে — তাৎক্ষণিক পদক্ষেপ বলো
3. সবচেয়ে গুরুত্বপূর্ণ একটি প্রশ্ন জিজ্ঞেস করো
4. স্বাভাবিক কথোপকথনের মতো উত্তর দাও — ফর্মের মতো নয়

ভাষার নিয়ম:
- সবসময় বাংলায় উত্তর দাও (ASHA হিন্দি বা ইংরেজিতে বললেও বাংলায় উত্তর দাও)
- সহজ, গ্রামীণ বাংলা ব্যবহার করো
- সংক্ষিপ্ত রাখো — ২-৩ বাক্যের বেশি নয়

${_moduleContext(caseType)}

বিপদচিহ্ন শনাক্ত হলে তাৎক্ষণিক পদক্ষেপ:
- রক্তপাত → "এখনই শুইয়ে দিন, পা উঁচু করুন, ১০৮ কল করুন"
- খিঁচুনি → "বাম কাতে শোয়ান, শ্বাসনালী রক্ষা করুন, ১০৮ কল করুন"
- শ্বাসকষ্ট → "শ্বাসনালী পরিষ্কার করুন, ১০৮ কল করুন"
- উচ্চ রক্তচাপ/মাথা ব্যথা → "বাম কাতে শোয়ান, ১০৮ কল করুন"
- নবজাতক দুধ খাচ্ছে না → "PSBI সন্দেহ, এখনই SNCU-তে রেফার করুন"
- পানিশূন্যতা → "এখনই ORS শুরু করুন"
''';

  static String _moduleContext(String caseType) => switch (caseType) {
    'pregnancy' => '''
গর্ভাবস্থার বিপদচিহ্ন যা জিজ্ঞেস করতে হবে:
- রক্তচাপ বেশি বা মাথা ব্যথা (প্রি-এক্লাম্পসিয়া)
- পা বা মুখ ফোলা (এডিমা)
- রক্তপাত বা তীব্র পেট ব্যথা (APH)
- বাচ্চার নড়াচড়া কমেছে
- চোখে ঝাপসা বা মাথা ঘোরা (এক্লাম্পসিয়া)
- ANC চেকআপ মিস হয়েছে''',
    'postpartum' => '''
প্রসব-পরবর্তী বিপদচিহ্ন:
- অতিরিক্ত রক্তপাত বা দুর্গন্ধ স্রাব (PPH/সেপসিস)
- জ্বর বা ঠান্ডা লাগা (পিউরপেরাল সেপসিস)
- স্তনে ব্যথা বা ফোলা (ম্যাস্টাইটিস)
- পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা
- খুব দুর্বল বা মাথা ঘোরা (রক্তাল্পতা)''',
    'newborn' => '''
নবজাতকের বিপদচিহ্ন (PSBI):
- দুধ খেতে পারছে না
- জ্বর (যেকোনো জ্বর = বিপদচিহ্ন)
- শ্বাসকষ্ট বা দ্রুত শ্বাস (≥৬০/মিনিট)
- নাভিতে লালভাব বা পুঁজ (ওম্ফালাইটিস)
- নিস্তেজ বা কম নড়াচড়া
- ত্বক হলুদ বা নীলাভ''',
    'child' => '''
শিশুর বিপদচিহ্ন:
- পাঁচ দিনের বেশি জ্বর (ম্যালেরিয়া/ডেঙ্গু)
- কাশি বা শ্বাসকষ্ট (নিউমোনিয়া)
- ডায়রিয়া বা বমি (পানিশূন্যতা)
- খাওয়া বন্ধ করেছে
- চোখ গর্তে বা ঠোঁট শুকনো (গুরুতর পানিশূন্যতা)
- ওজন অনেক কম (অপুষ্টি)''',
    'emergency' => '''
জরুরি বিপদচিহ্ন:
- অতিরিক্ত রক্তপাত
- খিঁচুনি বা অজ্ঞান
- শ্বাস বন্ধ বা গুরুতর শ্বাসকষ্ট
- সাড়া দিচ্ছে না''',
    _ => 'সাধারণ স্বাস্থ্য মূল্যায়ন করো।',
  };

  // ── Engine question IDs per module — for structured extraction ────────────
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
  }) async {
    if (!AppConfig.hasGeminiKey) {
      return _offlineFallback(newInput, caseType);
    }

    final historyText = history.isEmpty
        ? ''
        : history
            .map((t) =>
                t.role == 'asha' ? 'ASHA: ${t.text}' : 'আশামিত্র: ${t.text}')
            .join('\n');

    final questionDescs = _questionDescriptions(moduleId);
    final questionList =
        questionDescs.entries.map((e) => '${e.key}: ${e.value}').join('\n');

    final alreadyKnown = currentAnswers.isEmpty
        ? 'এখনো কিছু জানা যায়নি।'
        : currentAnswers.entries
            .map((e) => '${questionDescs[e.key] ?? e.key}: ${e.value ? "আছে" : "নেই"}')
            .join(', ');

    final prompt = '''
${_systemPrompt(caseType, moduleId)}

এখন পর্যন্ত কথোপকথন:
$historyText

ASHA এইমাত্র বললেন: "$newInput"

ইতিমধ্যে জানা তথ্য: $alreadyKnown

ক্লিনিক্যাল প্রশ্নের তালিকা (id: বিষয়):
$questionList

তোমার কাজ:
1. ASHA যা বললেন তার উপর ভিত্তি করে স্বাভাবিকভাবে সাড়া দাও
2. যদি বিপদচিহ্ন থাকে — তাৎক্ষণিক পদক্ষেপ বলো
3. সবচেয়ে গুরুত্বপূর্ণ একটি প্রশ্ন জিজ্ঞেস করো যা এখনো জানা যায়নি
4. কথোপকথন থেকে যা বোঝা গেছে তা structured আকারে বের করো
5. যদি ৩+ বিপদচিহ্ন নিশ্চিত হয়, বা সব গুরুত্বপূর্ণ প্রশ্নের উত্তর পাওয়া গেছে — should_finish: true দাও

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

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 600},
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return _offlineFallback(newInput, caseType);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw =
          (body['candidates'][0]['content']['parts'][0]['text'] as String)
              .trim()
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;

      // Merge extracted answers with current answers
      final extracted = <String, bool>{};
      final rawAnswers = json['extracted_answers'] as Map<String, dynamic>? ?? {};
      for (final e in rawAnswers.entries) {
        if (e.value is bool) extracted[e.key] = e.value as bool;
      }

      return ConversationResponse(
        spokenResponse: json['spoken_response'] as String? ?? newInput,
        extractedAnswers: extracted,
        shouldFinish: json['should_finish'] == true,
        riskLevel: json['risk_level'] as String? ?? 'low',
      );
    } catch (_) {
      return _offlineFallback(newInput, caseType);
    }
  }

  // ── Offline fallback — CLUP-style response without Gemini ─────────────────
  ConversationResponse _offlineFallback(String input, String caseType) {
    final lower = input.toLowerCase();

    // Emergency detection
    final emergencyWords = [
      'খিঁচুনি', 'অজ্ঞান', 'শ্বাস বন্ধ', 'রক্ত থামছে না',
      'seizure', 'unconscious', 'not breathing',
    ];
    if (emergencyWords.any((w) => lower.contains(w))) {
      return const ConversationResponse(
        spokenResponse: 'এটি জরুরি অবস্থা! এখনই ১০৮ কল করুন এবং রোগীকে বাম কাতে শোয়ান।',
        extractedAnswers: {},
        shouldFinish: true,
        riskLevel: 'emergency',
      );
    }

    final responses = switch (caseType) {
      'pregnancy' =>
        'বুঝেছি। রক্তচাপ বেশি বা মাথা ব্যথা হচ্ছে?',
      'newborn' =>
        'বুঝেছি। শিশু কি বুকের দুধ খেতে পারছে?',
      'child' =>
        'বুঝেছি। কতদিন ধরে জ্বর আছে?',
      'postpartum' =>
        'বুঝেছি। অতিরিক্ত রক্তপাত বা জ্বর হচ্ছে?',
      _ =>
        'বুঝেছি। আরো বিস্তারিত বলুন।',
    };

    return ConversationResponse(
      spokenResponse: responses,
      extractedAnswers: const {},
      shouldFinish: false,
      riskLevel: 'low',
    );
  }
}
