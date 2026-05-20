import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_config.dart';
import 'vitals_extractor.dart';

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
  final String spokenResponse;
  final Map<String, bool> extractedAnswers;
  final Map<String, double> extractedVitals; // NEW: BP, temp, MUAC, SpO2 etc.
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
  static String get _url => AppConfig.geminiUrlWithKey;

  // ── System prompt — defines the assistant's persona and rules ─────────────
  static String _systemPrompt(String caseType, String moduleId) => '''
তুমি আশামিত্র — একজন বিশেষজ্ঞ মেডিক্যাল সহকারী যিনি গ্রামীণ ভারতের ASHA কর্মীদের সাহায্য করেন।
তুমি একজন অভিজ্ঞ ডাক্তারের মতো কথা বলো — সহানুভূতিশীল, স্পষ্ট, এবং সরাসরি।

কেস টাইপ: $caseType
ক্লিনিক্যাল মডিউল: $moduleId

তোমার কাজ:
1. ASHA যা বলেছেন তা মনোযোগ দিয়ে শোনো — যেকোনো ভাষা বা উপভাষায়
2. যদি কোনো বিপদচিহ্ন থাকে — তাৎক্ষণিক পদক্ষেপ বলো
3. সবচেয়ে গুরুত্বপূর্ণ একটি প্রশ্ন জিজ্ঞেস করো
4. স্বাভাবিক কথোপকথনের মতো উত্তর দাও — ফর্মের মতো নয়

ভাষা ও উপভাষার নিয়ম (অত্যন্ত গুরুত্বপূর্ণ):
- ASHA যেকোনো ভাষায় বলুক — বাংলা, হিন্দি, ইংরেজি, বা মিশ্র — সবসময় সহজ বাংলায় উত্তর দাও
- পশ্চিমবঙ্গের সব উপভাষা বোঝো এবং সঠিকভাবে ব্যাখ্যা করো:
  * রাঢ়ী: "মাথা ঘুরাইতেছে", "পেট কামড়াইতেছে", "গা জ্বলতেছে"
  * বরেন্দ্রী (মালদা/মুর্শিদাবাদ): "মাথা ঘুরায়", "পেট ব্যথা করে", "জ্বর আইছে"
  * মেদিনীপুর: "মাথা ঘুরছে গো", "পেটে লাগছে", "জ্বর হইছে"
  * কোচবিহার/উত্তরবঙ্গ: "মাথা ঘুরে", "পেট ধরছে", "জ্বর উঠছে"
  * সুন্দরবন: "মাথা ঘুরতেছে", "পেট মোচড়াইতেছে"
- ভারতের অন্যান্য ভাষা বোঝো:
  * হিন্দি/ভোজপুরি: "pet mein dard", "sir ghoom raha", "khoon aa raha"
  * ওড়িয়া: "matha ghuruchi", "pet byatha"
  * সাঁওতালি/সাদরি: "duku", "jor", "pet dard"
  * ছত্তিশগড়ি: "pet dukhath", "bukhar aaye"
- উপভাষার শব্দ থেকে ক্লিনিক্যাল অর্থ বের করো:
  * "ঘুরাইতেছে/ঘুরায়/ঘুরছে" = মাথা ঘোরা (dizziness)
  * "কামড়াইতেছে/কামড়ায়" = ব্যথা (pain)
  * "জ্বলতেছে/জ্বলছে" = জ্বালা বা জ্বর (burning/fever)
  * "আইছে/উঠছে/হইছে" = হয়েছে (has occurred)
  * "গো/রে/হে/তো" = আঞ্চলিক suffix, ক্লিনিক্যাল অর্থ নেই
  * "duku" (সাঁওতালি) = ব্যথা (pain)
  * "jor" (সাদরি/হিন্দি) = জ্বর (fever)
- সংক্ষিপ্ত রাখো — ২-৩ বাক্যের বেশি নয়

${_moduleContext(caseType)}

বিপদচিহ্ন শনাক্ত হলে তাৎক্ষণিক পদক্ষেপ:
- রক্তপাত → "এখনই শুইয়ে দিন, পা উঁচু করুন, ১০৮ কল করুন"
- খিঁচুনি → "বাম কাতে শোয়ান, শ্বাসনালী রক্ষা করুন, ১০৮ কল করুন"
- শ্বাসকষ্ট → "শ্বাসনালী পরিষ্কার করুন, ১০৮ কল করুন"
- উচ্চ রক্তচাপ/মাথা ব্যথা → "বাম কাতে শোয়ান, ১০৮ কল করুন"
- নবজাতক দুধ খাচ্ছে না → "PSBI সন্দেহ, এখনই SNCU-তে রেফার করুন"
- পানিশূন্যতা → "এখনই ORS শুরু করুন"

অনিশ্চয়তা নিয়ম:
- ASHA যদি "মনে হয়", "একটু", "হয়তো", "নিশ্চিত না" বলেন — extracted_answers-এ সেই প্রশ্নটি false রাখো এবং নিশ্চিত করার জন্য follow-up প্রশ্ন করো
- শুধুমাত্র নিশ্চিত তথ্য extracted_answers-এ true করো
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

    // Extract vitals from the new input before sending to Gemini
    final spokenVitals = VitalsExtractor.extract(newInput);
    final vitalsSummary = VitalsExtractor.summarise(spokenVitals);
    final vitalsContext = vitalsSummary.isNotEmpty
        ? '\nমাপা ভাইটাল সাইন: $vitalsSummary'
        : '';

    final prompt = '''
${_systemPrompt(caseType, moduleId)}

এখন পর্যন্ত কথোপকথন:
$historyText

ASHA এইমাত্র বললেন: "$newInput"$vitalsContext

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

      // Prepend vital danger alert to spoken response if needed
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
    } catch (_) {
      return _offlineFallback(newInput, caseType);
    }
  }

  // ── Offline fallback — Gap 3 Fix: symptom-aware, not generic ────────────
  ConversationResponse _offlineFallback(String input, String caseType) {
    final lower = input.toLowerCase();

    // Emergency — full token list covering all dialects
    const _emergencyWords = [
      'খিঁচুনি', 'খিচুনি', 'খিঁচুনি হইছে', 'খিচুনি দিছে',
      'অজ্ঞান', 'জ্ঞান নেই', 'জ্ঞান নাই', 'সাড়া নেই', 'সাড়া নাই',
      'শ্বাস বন্ধ', 'দম বন্ধ', 'শ্বাস নিতে পারছে না', 'শ্বাস নিতে পারতেছে না',
      'রক্ত থামছে না', 'রক্ত থামতেছে না', 'নীল হয়ে', 'মরে গেছে',
      'mirgi', 'behosh', 'hosh nahi', 'sans band', 'khoon band nahi',
      'unconscious', 'seizure', 'convulsion', 'not breathing', 'fits',
      'khichuni', 'nishwas bandi',
    ];
    if (_emergencyWords.any((w) => lower.contains(w))) {
      return const ConversationResponse(
        spokenResponse: 'এটি জরুরি অবস্থা! এখনই ১০৮ কল করুন এবং রোগীকে বাম কাতে শোয়ান।',
        extractedAnswers: {},
        shouldFinish: true,
        riskLevel: 'emergency',
      );
    }

    // Pregnancy danger signs
    if (caseType == 'pregnancy') {
      if (_contains(lower, ['রক্তপাত', 'রক্ত পড়', 'রক্ত যাচ্ছে', 'রক্ত পড়তেছে',
          'khoon aa', 'bleeding', 'rakta paruchi'])) {
        return const ConversationResponse(
          spokenResponse: 'রক্তপাত হচ্ছে — এখনই শুইয়ে দিন, যোনি পরীক্ষা করবেন না। মাথা ব্যথা বা চোখে ঝাপসা হচ্ছে?',
          extractedAnswers: {'p3': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['মাথা ব্যথা', 'মাথা ব্যাথা', 'মাথা ধরেছে', 'মাথা ধরছে',
          'মাথা ঘুরাইতেছে', 'মাথা ঘুরতেছে', 'বিপি', 'রক্তচাপ',
          'sir dard', 'sar dard', 'bp high', 'matha byatha', 'matha ghuruchi'])) {
        return const ConversationResponse(
          spokenResponse: 'মাথা ব্যথা বা রক্তচাপ বেশি — বাম কাতে শোয়ান। পা বা মুখ ফুলেছে?',
          extractedAnswers: {'p1': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['চোখে ঝাপসা', 'ঝাপসা দেখছে', 'মাথা ঘুরছে', 'চোখ ঝাপসা',
          'মাথা ঘুরাইতেছে', 'chakkar', 'aankhon mein dhundla', 'matha ghuruchi'])) {
        return const ConversationResponse(
          spokenResponse: 'চোখে ঝাপসা বা মাথা ঘোরা — এক্লাম্পসিয়ার লক্ষণ। এখনই ১০৮ কল করুন।',
          extractedAnswers: {'p6': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['ফুলেছে', 'ফুলছে', 'ফোলা', 'sujan', 'swelling', 'pada phulichi'])) {
        return const ConversationResponse(
          spokenResponse: 'ফোলা দেখছি — রক্তচাপ বেশি বা মাথা ব্যথা হচ্ছে?',
          extractedAnswers: {'p2': true},
          shouldFinish: false,
          riskLevel: 'medium',
        );
      }
      if (_contains(lower, ['নড়ছে না', 'নড়তেছে না', 'নড়াচড়া কম', 'bachcha hilta nahi',
          'movement nahi', 'pila hiluchi nahi'])) {
        return const ConversationResponse(
          spokenResponse: 'বাচ্চার নড়াচড়া কম — আজই FRU-তে নিয়ে যান। রক্তপাত বা পেট ব্যথা আছে?',
          extractedAnswers: {'p4': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      return const ConversationResponse(
        spokenResponse: 'বুঝেছি। রক্তচাপ বেশি বা মাথা ব্যথা হচ্ছে?',
        extractedAnswers: {},
        shouldFinish: false,
        riskLevel: 'low',
      );
    }

    // Newborn danger signs
    if (caseType == 'newborn') {
      if (_contains(lower, ['দুধ খাচ্ছে না', 'দুধ খাইতেছে না', 'দুধ খায় না', 'দুধ ধরছে না',
          'doodh nahi', 'not feeding', 'dudha khaucha nahi'])) {
        return const ConversationResponse(
          spokenResponse: 'দুধ খাচ্ছে না — PSBI সন্দেহ, এখনই SNCU-তে রেফার করুন। জ্বর বা শ্বাসকষ্ট আছে?',
          extractedAnswers: {'n1': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['জ্বর', 'জ্বর আইছে', 'গা গরম', 'bukhar', 'fever', 'jor', 'jara'])) {
        return const ConversationResponse(
          spokenResponse: 'নবজাতকের জ্বর — যেকোনো জ্বর বিপদচিহ্ন। এখনই SNCU-তে রেফার করুন। শিশু দুধ খাচ্ছে?',
          extractedAnswers: {'n2': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['শ্বাস', 'শ্বাসকষ্ট', 'দম', 'sans', 'breathing', 'nishwas'])) {
        return const ConversationResponse(
          spokenResponse: 'শ্বাসকষ্ট — শ্বাসের হার গণনা করুন। ৬০/মিনিটের বেশি হলে এখনই SNCU-তে রেফার করুন।',
          extractedAnswers: {'n3': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['নিস্তেজ', 'ঢিলে', 'নড়ছে না', 'সাড়া দিচ্ছে না',
          'lethargic', 'hilta nahi', 'dhila'])) {
        return const ConversationResponse(
          spokenResponse: 'শিশু নিস্তেজ — গুরুতর অসুস্থতার লক্ষণ। এখনই SNCU-তে রেফার করুন।',
          extractedAnswers: {'n5': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      return const ConversationResponse(
        spokenResponse: 'বুঝেছি। শিশু কি বুকের দুধ খেতে পারছে?',
        extractedAnswers: {},
        shouldFinish: false,
        riskLevel: 'low',
      );
    }

    // Child danger signs
    if (caseType == 'child') {
      if (_contains(lower, ['পাঁচ দিন', '৫ দিন', 'পাঁচদিন', 'paanch din', '5 din',
          'pancha dina', 'five days'])) {
        return const ConversationResponse(
          spokenResponse: 'পাঁচ দিনের বেশি জ্বর — ম্যালেরিয়া হতে পারে। আজই PHC-তে নিয়ে যান। কাশি বা শ্বাসকষ্ট আছে?',
          extractedAnswers: {'c1': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['পাতলা পায়খানা', 'ডায়রিয়া', 'বমি', 'dast', 'diarrh',
          'ulti', 'jhada', 'loose motion'])) {
        return const ConversationResponse(
          spokenResponse: 'ডায়রিয়া বা বমি — এখনই ORS শুরু করুন। চোখ গর্তে বসে গেছে?',
          extractedAnswers: {'c3': true},
          shouldFinish: false,
          riskLevel: 'medium',
        );
      }
      if (_contains(lower, ['চোখ গর্তে', 'চোখ বসে', 'ঠোঁট শুকনো', 'sunken', 'dehydrat',
          'aankhein andar', 'honth sukhe'])) {
        return const ConversationResponse(
          spokenResponse: 'পানিশূন্যতার লক্ষণ — এখনই ORS শুরু করুন, FRU-তে রেফার করুন।',
          extractedAnswers: {'c5': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      return const ConversationResponse(
        spokenResponse: 'বুঝেছি। কতদিন ধরে জ্বর আছে?',
        extractedAnswers: {},
        shouldFinish: false,
        riskLevel: 'low',
      );
    }

    // Postpartum danger signs
    if (caseType == 'postpartum') {
      if (_contains(lower, ['রক্তপাত', 'রক্ত পড়', 'অনেক রক্ত', 'khoon', 'bleeding'])) {
        return const ConversationResponse(
          spokenResponse: 'রক্তপাত হচ্ছে — জরায়ু মালিশ করুন, ১০৮ কল করুন। জ্বরও আছে?',
          extractedAnswers: {'pp1': true},
          shouldFinish: false,
          riskLevel: 'high',
        );
      }
      if (_contains(lower, ['জ্বর', 'জ্বর হইছে', 'bukhar', 'fever', 'jara'])) {
        return const ConversationResponse(
          spokenResponse: 'জ্বর আছে — পিউরপেরাল সেপসিসের ঝুঁকি। ২৪ ঘণ্টার মধ্যে PHC-তে নিয়ে যান। রক্তপাতও হচ্ছে?',
          extractedAnswers: {'pp2': true},
          shouldFinish: false,
          riskLevel: 'medium',
        );
      }
      return const ConversationResponse(
        spokenResponse: 'বুঝেছি। অতিরিক্ত রক্তপাত বা জ্বর হচ্ছে?',
        extractedAnswers: {},
        shouldFinish: false,
        riskLevel: 'low',
      );
    }

    // Generic
    return ConversationResponse(
      spokenResponse: 'বুঝেছি। আরো বিস্তারিত বলুন — কতদিন ধরে এই সমস্যা?',
      extractedAnswers: const {},
      shouldFinish: false,
      riskLevel: 'low',
    );
  }

  // Helper: check if any keyword exists in text
  bool _contains(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
