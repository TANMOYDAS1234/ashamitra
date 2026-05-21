import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
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
তুমি আশামিত্র — একজন বিশেষজ্ঞ মেডিক্যাল সহকারী যিনি গ্রামীণ ভারতের ASHA কর্মীদের সাহায্য করেন।
তুমি একজন অভিজ্ঞ ডাক্তারের মতো কথা বলো — সহানুভূতিশীল, স্পষ্ট, এবং সরাসরি।

কেস টাইপ: $caseType
ক্লিনিক্যাল মডিউল: $moduleId

তোমার কাজ:
1. ASHA যা বলেছেন তা মনোযোগ দিয়ে শোনো — যেকোনো ভাষা বা উপভাষায়
2. যদি কোনো বিপদচিহ্ন থাকে — তাৎক্ষণিক পদক্ষেপ বলো
3. সবচেয়ে গুরুত্বপূর্ণ একটি প্রশ্ন জিজ্ঞেস করো
4. স্বাভাবিক কথোপকথনের মতো উত্তর দাও — ফর্মের মতো নয়

ভাষার নিয়ম:
- সবসময় সহজ বাংলায় উত্তর দাও
- বাংলা, হিন্দি, ইংরেজি, মিশ্র — সব বুঝবে
- সংক্ষিপ্ত রাখো — ২-৩ বাক্যের বেশি নয়

${_moduleContext(caseType)}

অনিশ্চয়তা নিয়ম:
- "মনে হয়", "একটু", "হয়তো" বললে — extracted_answers-এ false রাখো
- শুধু নিশ্চিত তথ্য true করো
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
    final historyText = history.isEmpty
        ? ''
        : history
            .map((t) => t.role == 'asha' ? 'ASHA: ${t.text}' : 'আশামিত্র: ${t.text}')
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

তোমার কাজ (এই ক্রমে):
1. ASHA যা বললেন স্বীকার করো — ১ বাক্যে
2. যদি বিপদচিহ্ন নিশ্চিত হয় — তাৎক্ষণিক পদক্ষেপ বলো (১ বাক্য)
3. উপরের "সবচেয়ে জরুরি অজানা প্রশ্ন" টি জিজ্ঞেস করো — শুধু সেটাই
4. ইতিমধ্যে জানা প্রশ্ন আবার জিজ্ঞেস করবে না
5. কথোপকথন থেকে নিশ্চিত তথ্য extracted_answers-এ রাখো
6. should_finish: true দাও যদি — ২+ RED বিপদচিহ্ন নিশ্চিত, বা সব অজানা প্রশ্নের উত্তর পাওয়া গেছে, বা turn $turnNumber >= $maxTurns

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

    // ── Call backend proxy — key lives on server ──────────────────────────────
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      // ignore: avoid_print
      print('[Chat] HTTP ${response.statusCode}: ${response.body}');
      throw Exception('Backend chat error ${response.statusCode}');
    }

    final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (bodyJson['text'] as String? ?? '')
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Fire partial callback immediately (no streaming from backend)
    if (onPartialResponse != null && raw.isNotEmpty) {
      onPartialResponse(raw);
    }

    final json = jsonDecode(raw) as Map<String, dynamic>;

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

  // ── Offline fallback — stateful: skips already-answered questions ──────────
  ConversationResponse offlineFallback(
    String input,
    String caseType,
    Map<String, bool> answered,
  ) {
    final lower = input.toLowerCase();

    const emergencyWords = [
      'খিঁচুনি', 'খিচুনি', 'অজ্ঞান', 'জ্ঞান নেই', 'জ্ঞান নাই',
      'সাড়া নেই', 'সাড়া নাই', 'শ্বাস বন্ধ', 'দম বন্ধ',
      'রক্ত থামছে না', 'রক্ত থামতেছে না', 'নীল হয়ে', 'মরে গেছে',
      'mirgi', 'behosh', 'hosh nahi', 'sans band', 'khoon band nahi',
      'unconscious', 'seizure', 'convulsion', 'not breathing', 'fits',
    ];
    if (emergencyWords.any((w) => lower.contains(w))) {
      return const ConversationResponse(
        spokenResponse: 'এটি জরুরি অবস্থা! এখনই ১০৮ কল করুন এবং রোগীকে বাম কাতে শোয়ান।',
        extractedAnswers: {},
        shouldFinish: true,
        riskLevel: 'emergency',
      );
    }

    final extracted = <String, bool>{};
    final isNo  = _contains(lower, ['না', 'নেই', 'নাই', 'হয়নি', 'হচ্ছে না', 'no', 'nahi', 'nai']);
    final isYes = !isNo && _contains(lower, ['হ্যাঁ', 'আছে', 'হয়েছে', 'হইছে', 'হচ্ছে', 'yes', 'ache']);

    switch (caseType) {
      case 'pregnancy':
        if (_contains(lower, ['রক্তপাত', 'রক্ত পড়', 'রক্ত যাচ্ছে', 'bleeding', 'khoon aa'])) extracted['p3'] = true;
        if (_contains(lower, ['মাথা ব্যথা', 'মাথা ধরেছে', 'বিপি', 'রক্তচাপ', 'sir dard', 'bp high'])) extracted['p1'] = true;
        if (_contains(lower, ['চোখে ঝাপসা', 'মাথা ঘুরছে', 'chakkar'])) extracted['p6'] = true;
        if (_contains(lower, ['ফুলেছে', 'ফুলছে', 'ফোলা', 'sujan', 'swelling'])) extracted['p2'] = true;
        if (_contains(lower, ['নড়ছে না', 'নড়াচড়া কম', 'movement nahi'])) extracted['p4'] = true;
      case 'postpartum':
        if (_contains(lower, ['রক্তপাত', 'রক্ত পড়', 'অনেক রক্ত', 'bleeding'])) extracted['pp1'] = true;
        if (_contains(lower, ['জ্বর', 'bukhar', 'fever'])) extracted['pp2'] = true;
      case 'newborn':
        if (_contains(lower, ['দুধ খাচ্ছে না', 'দুধ খায় না', 'not feeding', 'doodh nahi'])) extracted['n1'] = true;
        if (_contains(lower, ['জ্বর', 'গা গরম', 'bukhar', 'fever'])) extracted['n2'] = true;
        if (_contains(lower, ['শ্বাস', 'শ্বাসকষ্ট', 'breathing', 'sans'])) extracted['n3'] = true;
        if (_contains(lower, ['নিস্তেজ', 'ঢিলে', 'নড়ছে না', 'lethargic'])) extracted['n5'] = true;
      case 'child':
        if (_contains(lower, ['পাঁচ দিন', '৫ দিন', 'paanch din', '5 din', 'five days'])) extracted['c1'] = true;
        if (_contains(lower, ['কাশি', 'কাশছে', 'শ্বাসকষ্ট', 'khansi', 'cough', 'breathing'])) extracted['c2'] = true;
        if (_contains(lower, ['পাতলা পায়খানা', 'ডায়রিয়া', 'বমি', 'dast', 'diarrh', 'ulti'])) extracted['c3'] = true;
        if (_contains(lower, ['খাচ্ছে না', 'খাওয়া বন্ধ', 'khana nahi'])) extracted['c4'] = true;
        if (_contains(lower, ['চোখ গর্তে', 'ঠোঁট শুকনো', 'sunken', 'dehydrat'])) extracted['c5'] = true;
    }

    final allAnswered = {...answered, ...extracted};
    final nextQ = _pickNext(caseType, allAnswered, isNo, isYes);

    if (nextQ == null) {
      return ConversationResponse(
        spokenResponse: 'ধন্যবাদ। সব তথ্য পাওয়া গেছে। ফলাফল দেখাচ্ছি।',
        extractedAnswers: extracted,
        shouldFinish: true,
        riskLevel: extracted.values.any((v) => v) ? 'medium' : 'low',
      );
    }

    return ConversationResponse(
      spokenResponse: nextQ,
      extractedAnswers: extracted,
      shouldFinish: false,
      riskLevel: extracted.values.any((v) => v) ? 'medium' : 'low',
    );
  }

  String? _pickNext(String caseType, Map<String, bool> answered, bool lastWasNo, bool lastWasYes) {
    bool u(String id) => !answered.containsKey(id);
    final ack = lastWasNo ? 'ঠিক আছে।' : 'বুঝেছি।';
    switch (caseType) {
      case 'child':
        if (u('c1')) return '$ack পাঁচ দিনের বেশি জ্বর আছে?';
        if (u('c2')) return '$ack কাশি বা শ্বাসকষ্ট আছে?';
        if (u('c3')) return '$ack পাতলা পায়খানা বা বমি হচ্ছে?';
        if (u('c4')) return '$ack খাওয়া বন্ধ করেছে?';
        if (u('c5')) return '$ack চোখ গর্তে বসে গেছে বা ঠোঁট শুকনো?';
        if (u('c6')) return '$ack ওজন অনেক কম মনে হচ্ছে?';
      case 'pregnancy':
        if (u('p1')) return '$ack মাথা ব্যথা বা রক্তচাপ বেশি?';
        if (u('p3')) return '$ack রক্তপাত বা তীব্র পেট ব্যথা আছে?';
        if (u('p6')) return '$ack চোখে ঝাপসা বা মাথা ঘুরছে?';
        if (u('p4')) return '$ack বাচ্চার নড়াচড়া কম মনে হচ্ছে?';
        if (u('p2')) return '$ack পা বা মুখ ফুলেছে?';
        if (u('p5')) return '$ack ANC চেকআপ মিস হয়েছে?';
      case 'postpartum':
        if (u('pp1')) return '$ack অতিরিক্ত রক্তপাত বা দুর্গন্ধ স্রাব হচ্ছে?';
        if (u('pp2')) return '$ack জ্বর বা ঠান্ডা লাগছে?';
        if (u('pp4')) return '$ack পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা?';
        if (u('pp6')) return '$ack খুব দুর্বল বা মাথা ঘুরছে?';
        if (u('pp3')) return '$ack স্তনে ব্যথা বা ফোলা?';
        if (u('pp5')) return '$ack প্রস্রাবে জ্বালা হচ্ছে?';
      case 'newborn':
        if (u('n1')) return '$ack শিশু কি বুকের দুধ খেতে পারছে?';
        if (u('n2')) return '$ack জ্বর আছে?';
        if (u('n3')) return '$ack শ্বাসকষ্ট বা দ্রুত শ্বাস আছে?';
        if (u('n5')) return '$ack শিশু নিস্তেজ বা কম নড়ছে?';
        if (u('n4')) return '$ack নাভিতে লালভাব বা পুঁজ আছে?';
        if (u('n6')) return '$ack ত্বক হলুদ বা নীলাভ?';
    }
    return null;
  }

  bool _contains(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}
