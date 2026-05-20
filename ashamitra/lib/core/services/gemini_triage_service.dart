import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_config.dart';

// Result of a single conversational turn — Gemini picks the next question
// and optionally provides an immediate action if a danger sign was just confirmed.
class NextQuestionResult {
  final String? questionId;
  final String? questionTextBn;
  final List<String> options;
  final String? immediateActionBn;
  final bool shouldFinish;

  const NextQuestionResult({
    this.questionId,
    this.questionTextBn,
    this.options = const ['হ্যাঁ', 'না'],
    this.immediateActionBn,
    this.shouldFinish = false,
  });
}

class GeminiTriageService {
  // Key injected at build time: flutter run --dart-define=GEMINI_API_KEY=...
  // Falls back to offline mode gracefully when key is absent.
  static String get _url => AppConfig.geminiUrlWithKey;

  /// Online path: Gemini reads the situation and returns enriched engine
  /// questions — same IDs, same deterministic evaluation, but situation-aware
  /// preamble and smarter options for the worker.
  ///
  /// Returns list of {id, text_bn, options} — id is always a real engine ID.
  /// Falls back to plain engine questions if Gemini fails.
  Future<List<Map<String, dynamic>>> enrichQuestions({
    required String caseType,
    required String situation,
    required List<Map<String, String>> moduleQuestions,
  }) async {
    final questionList = moduleQuestions
        .map((q) => '${q['id']}: ${q['text_bn']}')
        .join('\n');

    final prompt = '''
You are a clinical triage assistant for ASHA workers in rural India.
Case type: $caseType
Worker described the situation: "$situation"

Protocol questions (id: Bengali text):
$questionList

Your tasks:
1. Order the questions — most clinically urgent for THIS situation first
2. For each question, write a short situation-aware Bengali preamble (1 sentence max) that references what the worker said, then the question
3. Provide 2-3 Bengali answer options. The FIRST option must always map to YES (danger present), the SECOND to NO (danger absent). Optional third for uncertainty.

RULES:
- Return ALL question IDs — never drop any
- Keep the clinical meaning identical — only the phrasing changes
- If situation is vague, skip the preamble and use the original question text
- Bengali only

Respond with ONLY this JSON array (no markdown):
[
  {"id": "n1", "text_bn": "enriched question text", "options": ["হ্যাঁ", "না"]},
  {"id": "n3", "text_bn": "enriched question text", "options": ["হ্যাঁ", "না", "কিছুটা"]}
]
''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 1024},
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return _plainQuestions(moduleQuestions);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (body['candidates'][0]['content']['parts'][0]['text'] as String)
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

      // Validate: every returned ID must exist in the module
      final validIds = moduleQuestions.map((q) => q['id']!).toSet();
      final validated = list.where((q) => validIds.contains(q['id'])).toList();

      // Append any missing questions in default order
      final returnedIds = validated.map((q) => q['id'] as String).toSet();
      for (final q in moduleQuestions) {
        if (!returnedIds.contains(q['id'])) {
          validated.add({'id': q['id'], 'text_bn': q['text_bn'], 'options': ['হ্যাঁ', 'না']});
        }
      }

      // Ensure options always have at least হ্যাঁ and না
      for (final q in validated) {
        final opts = (q['options'] as List?)?.cast<String>() ?? [];
        if (opts.length < 2) q['options'] = ['হ্যাঁ', 'না'];
      }

      return validated;
    } catch (_) {
      return _plainQuestions(moduleQuestions);
    }
  }

  List<Map<String, dynamic>> _plainQuestions(
          List<Map<String, String>> moduleQuestions) =>
      moduleQuestions
          .map((q) => {'id': q['id']!, 'text_bn': q['text_bn']!, 'options': ['হ্যাঁ', 'না']})
          .toList();

  // ── CHANGE 1: Turn-by-turn conversational question selection ──────────────
  // Called after EVERY answer. Gemini sees the full situation + all Q&A so far
  // + remaining questions, and returns:
  //   1. The single most clinically urgent next question ID
  //   2. An enriched Bengali question text (situation-aware)
  //   3. An immediate action to speak if the last answer confirmed a danger sign
  //   4. shouldFinish=true if enough info to conclude
  Future<NextQuestionResult> getNextQuestion({
    required String caseType,
    required String situation,
    required List<Map<String, String>> conversationHistory,
    required List<Map<String, String>> remainingQuestions,
  }) async {
    if (remainingQuestions.isEmpty) {
      return const NextQuestionResult(shouldFinish: true);
    }

    final historyText = conversationHistory.isEmpty
        ? 'এখনো কোনো প্রশ্নোত্তর হয়নি।'
        : conversationHistory
            .map((h) => 'প্রশ্ন: \${h[\'q\']}\nউত্তর: \${h[\'a\']}')
            .join('\n\n');

    final remainingText = remainingQuestions
        .map((q) => '\${q[\'id\']}: \${q[\'text_bn\']}')
        .join('\n');

    final lastAnswer =
        conversationHistory.isNotEmpty ? conversationHistory.last : null;
    final lastAnswerContext = lastAnswer != null
        ? 'সর্বশেষ উত্তর: "\${lastAnswer[\'a\']}" (প্রশ্ন: "\${lastAnswer[\'q\']}")':
        '';

    final prompt = '''
তুমি একজন বিশেষজ্ঞ ক্লিনিক্যাল ট্রায়াজ সহকারী যিনি গ্রামীণ ভারতের ASHA কর্মীদের সাহায্য করেন।

কেস টাইপ: $caseType
ASHA কর্মী পরিস্থিতি বর্ণনা করেছেন: "$situation"

এখন পর্যন্ত কথোপকথন:
$historyText

$lastAnswerContext

বাকি প্রশ্নগুলো (id: বাংলা প্রশ্ন):
$remainingText

তোমার কাজ:
1. সর্বশেষ উত্তরটি বিশ্লেষণ করো — যদি বিপদচিহ্ন (হ্যাঁ/তীব্র/অনেক) নিশ্চিত হয়, তাহলে একটি তাৎক্ষণিক পদক্ষেপ দাও
2. বাকি প্রশ্নগুলো থেকে এই মুহূর্তে সবচেয়ে জরুরি প্রশ্নটি বেছে নাও
3. যদি ইতিমধ্যে ৩+ বিপদচিহ্ন নিশ্চিত হয়েছে, তাহলে should_finish: true দাও

নিয়ম:
- শুধুমাত্র বাকি প্রশ্নের তালিকা থেকে id বেছে নাও
- immediate_action_bn শুধু তখনই দাও যখন সত্যিকারের বিপদচিহ্ন নিশ্চিত হয়
- options এর প্রথমটি সবসময় বিপদ আছে (হ্যাঁ), দ্বিতীয়টি বিপদ নেই (না)
- বাংলায় উত্তর দাও

শুধুমাত্র এই JSON দিয়ে উত্তর দাও (কোনো markdown নয়):
{"next_question_id": "p1", "question_text_bn": "পরিস্থিতি-সচেতন প্রশ্নের বাংলা টেক্সট", "options": ["হ্যাঁ", "না"], "immediate_action_bn": null, "should_finish": false}
''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [{'text': prompt}]
            }
          ],
          'generationConfig': {'temperature': 0.15, 'maxOutputTokens': 512},
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return _fallbackNext(remainingQuestions);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw =
          (body['candidates'][0]['content']['parts'][0]['text'] as String)
              .trim()
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final validIds = remainingQuestions.map((q) => q['id']!).toSet();

      if (json['should_finish'] == true) {
        return const NextQuestionResult(shouldFinish: true);
      }

      final returnedId = json['next_question_id'] as String?;
      if (returnedId == null || !validIds.contains(returnedId)) {
        return _fallbackNext(remainingQuestions);
      }

      final opts =
          (json['options'] as List?)?.cast<String>() ?? ['হ্যাঁ', 'না'];
      final action = json['immediate_action_bn'] as String?;

      return NextQuestionResult(
        questionId: returnedId,
        questionTextBn: json['question_text_bn'] as String?,
        options: opts.length >= 2 ? opts : ['হ্যাঁ', 'না'],
        immediateActionBn:
            (action != null && action.isNotEmpty) ? action : null,
        shouldFinish: false,
      );
    } catch (_) {
      return _fallbackNext(remainingQuestions);
    }
  }

  NextQuestionResult _fallbackNext(List<Map<String, String>> remaining) {
    if (remaining.isEmpty) return const NextQuestionResult(shouldFinish: true);
    return NextQuestionResult(
      questionId: remaining.first['id'],
      questionTextBn: remaining.first['text_bn'],
      options: const ['হ্যাঁ', 'না'],
    );
  }

  /// Online path: Gemini reads the situation and returns a prioritised
  /// ordered list of engine question IDs to ask the worker.
  /// The app then asks those exact engine questions — no free-form generation.
  ///
  /// [moduleQuestions] — list of {id, text_bn, text_en} from the engine
  /// Returns ordered question IDs, most relevant first.
  /// Falls back to default order if Gemini fails.
  Future<List<String>> prioritiseQuestions({
    required String caseType,
    required String situation,
    required List<Map<String, String>> moduleQuestions,
  }) async {
    final questionList = moduleQuestions
        .map((q) => '${q['id']}: ${q['text_bn']} (${q['text_en']})')
        .join('\n');

    final prompt = '''
You are a clinical triage assistant for ASHA workers in rural India.
Case type: $caseType
Worker described: "$situation"

Available protocol questions (id: Bengali text):
$questionList

Task: Return the question IDs in the order they should be asked, most clinically urgent first given the described situation.
If the situation is vague or irrelevant, return all IDs in default order.

Respond with ONLY a JSON array of question IDs, e.g.: ["n3", "n1", "n2", "n5", "n4", "n6"]
No explanation, no markdown.
''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 128},
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return _defaultOrder(moduleQuestions);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (body['candidates'][0]['content']['parts'][0]['text'] as String)
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final ids = (jsonDecode(raw) as List).map((e) => e.toString()).toList();
      // Validate: only return IDs that actually exist in the module
      final validIds = moduleQuestions.map((q) => q['id']!).toSet();
      final filtered = ids.where((id) => validIds.contains(id)).toList();
      // Append any missing IDs at the end (safety net)
      for (final q in moduleQuestions) {
        if (!filtered.contains(q['id'])) filtered.add(q['id']!);
      }
      return filtered;
    } catch (_) {
      return _defaultOrder(moduleQuestions);
    }
  }

  List<String> _defaultOrder(List<Map<String, String>> moduleQuestions) =>
      moduleQuestions.map((q) => q['id']!).toList();

  /// Generate ALL follow-up questions in ONE API call based on the situation.
  /// Returns a list of {question, options} maps.
  Future<List<Map<String, dynamic>>> generateQuestions({
    required String caseType,
    required String situation,
  }) async {
    final caseContext = _caseContext(caseType);

    final prompt = '''
You are an expert ASHA worker medical triage assistant for rural India.
The ASHA worker selected case type: $caseType ($caseContext)
The worker described the situation as: "$situation"

IMPORTANT RULES:
- The situation describes the PATIENT (beneficiary), not the ASHA worker herself
- If the description is vague, unclear, or about the worker (e.g. "I don't feel well", "I am here", "hello"), IGNORE it and generate standard protocol questions for the case type
- If the description mentions symptoms unrelated to $caseType, still generate questions focused on $caseType danger signs
- Always generate clinically relevant questions for $caseType regardless of what the worker said
- All questions must be in Bengali (বাংলা)
- Each question must have 2-4 short Bengali answer options
- Include the most critical danger-sign questions for this case type first
- Progress from most critical to least critical

Generate 5-6 focused triage questions. Respond with ONLY this JSON array (no markdown, no explanation):
[
  {"question": "প্রশ্ন ১?", "options": ["বিকল্প ১", "বিকল্প ২", "বিকল্প ৩"]},
  {"question": "প্রশ্ন ২?", "options": ["বিকল্প ১", "বিকল্প ২"]},
  {"question": "প্রশ্ন ৩?", "options": ["বিকল্প ১", "বিকল্প ২", "বিকল্প ৩"]},
  {"question": "প্রশ্ন ৪?", "options": ["বিকল্প ১", "বিকল্প ২", "বিকল্প ৩"]},
  {"question": "প্রশ্ন ৫?", "options": ["বিকল্প ১", "বিকল্প ২", "বিকল্প ৩"]}
]
''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [{'text': prompt}]
            }
          ],
          'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024}
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return fallbackQuestions(caseType);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (body['candidates'][0]['content']['parts'][0]['text'] as String)
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return fallbackQuestions(caseType);
    }
  }

  /// Summarize the full conversation into a triage outcome.
  Future<({String outcome, String reason, String nextStep})> summarize({
    required String caseType,
    required String situation,
    required List<Map<String, String>> history,
  }) async {
    final historyText = history.isEmpty
        ? 'কোনো প্রশ্নোত্তর নেই।'
        : history.map((h) => 'প্রশ্ন: ${h['q']}\nউত্তর: ${h['a']}').join('\n\n');

    final prompt = '''
You are an expert ASHA worker medical triage assistant for rural India.
Based on the patient assessment below, provide a triage outcome in Bengali.

Case type: $caseType
Initial description: "$situation"

Assessment:
$historyText

Respond with ONLY this JSON (no markdown):
{"outcome": "safe", "reason": "বাংলায় সংক্ষিপ্ত কারণ।", "nextStep": "বাংলায় পরবর্তী পদক্ষেপ।"}

outcome must be exactly one of: "safe", "attention", "emergency"
''';

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [{'text': prompt}]
            }
          ],
          'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 300}
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return _fallbackSummary(history);

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (body['candidates'][0]['content']['parts'][0]['text'] as String)
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        outcome: json['outcome'] as String? ?? 'attention',
        reason: json['reason'] as String? ?? '',
        nextStep: json['nextStep'] as String? ?? '',
      );
    } catch (_) {
      return _fallbackSummary(history);
    }
  }

  // ── Case context hints for better Gemini prompting ───────────
  String _caseContext(String caseType) => switch (caseType) {
    'pregnancy'    => 'Pregnant mother checkup — focus on danger signs like bleeding, BP, swelling, fetal movement',
    'postpartum'   => 'Post-delivery checkup — focus on bleeding, fever, breast issues, wound healing',
    'newborn'      => 'Newborn 0-28 days — focus on feeding, breathing, jaundice, umbilicus, temperature',
    'infant'       => 'Infant 1-12 months — focus on feeding, fever, diarrhea, breathing, weight',
    'child'        => 'Child 1-5 years — focus on fever duration, cough, diarrhea, nutrition, dehydration',
    'immunization' => 'Missed immunization — focus on age, which vaccine missed, current health status',
    'emergency'    => 'Emergency case — focus on bleeding, seizures, breathing difficulty, consciousness',
    _              => 'General health assessment',
  };

  // ── Hardcoded fallback questions per case (used when offline/API fails) ──
  List<Map<String, dynamic>> fallbackQuestions(String caseType) =>
      switch (caseType) {
        'pregnancy' => [
          {'question': 'কতদিন ধরে এই সমস্যা হচ্ছে?', 'options': ['১ দিন', '২-৩ দিন', '১ সপ্তাহের বেশি']},
          {'question': 'রক্তচাপ বেশি বা মাথা ব্যথা হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'মাঝে মাঝে']},
          {'question': 'পা বা মুখ ফুলে যাচ্ছে?', 'options': ['হ্যাঁ', 'না', 'কিছুটা']},
          {'question': 'শিশুর নড়াচড়া কমে গেছে?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
          {'question': 'রক্তপাত বা তীব্র পেট ব্যথা আছে?', 'options': ['হ্যাঁ', 'না', 'হালকা']},
          {'question': 'চোখে ঝাপসা বা মাথা ঘোরা হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'মাঝে মাঝে']},
        ],
        'postpartum' => [
          {'question': 'প্রসবের কতদিন পর এই সমস্যা?', 'options': ['১-৩ দিন', '৪-৭ দিন', '১ সপ্তাহের বেশি']},
          {'question': 'অতিরিক্ত রক্তপাত হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'কিছুটা']},
          {'question': 'জ্বর বা ঠান্ডা লাগছে?', 'options': ['হ্যাঁ', 'না', 'মাঝে মাঝে']},
          {'question': 'স্তনে ব্যথা বা ফোলা আছে?', 'options': ['হ্যাঁ', 'না', 'কিছুটা']},
          {'question': 'পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
        ],
        'newborn' => [
          {'question': 'শিশুর বয়স কতদিন?', 'options': ['১-৭ দিন', '৮-১৪ দিন', '১৫-২৮ দিন']},
          {'question': 'শিশু বুকের দুধ খেতে পারছে?', 'options': ['হ্যাঁ', 'না', 'খুব কম']},
          {'question': 'শিশুর শরীরে জ্বর আছে?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
          {'question': 'শ্বাস-প্রশ্বাস দ্রুত বা কষ্টকর?', 'options': ['হ্যাঁ', 'না', 'কিছুটা']},
          {'question': 'ত্বক হলুদ বা নীলাভ দেখাচ্ছে?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
        ],
        'infant' => [
          {'question': 'শিশুর বয়স কত মাস?', 'options': ['১-৩ মাস', '৪-৬ মাস', '৭-১২ মাস']},
          {'question': 'কতদিন ধরে এই সমস্যা?', 'options': ['১ দিন', '২-৩ দিন', '৩ দিনের বেশি']},
          {'question': 'জ্বর আছে?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
          {'question': 'ডায়রিয়া বা বমি হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'মাঝে মাঝে']},
          {'question': 'শ্বাসকষ্ট বা বুকে শব্দ হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'হালকা']},
        ],
        'child' => [
          {'question': 'শিশুর বয়স কত বছর?', 'options': ['১-২ বছর', '২-৩ বছর', '৩-৫ বছর']},
          {'question': 'কতদিন ধরে জ্বর?', 'options': ['১-২ দিন', '৩-৫ দিন', '৫ দিনের বেশি']},
          {'question': 'কাশি বা শ্বাসকষ্ট আছে?', 'options': ['হ্যাঁ', 'না', 'হালকা']},
          {'question': 'ডায়রিয়া বা বমি হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'মাঝে মাঝে']},
          {'question': 'খাওয়া-দাওয়া বন্ধ করে দিয়েছে?', 'options': ['হ্যাঁ', 'না', 'কিছুটা কম']},
        ],
        'immunization' => [
          {'question': 'শিশুর বয়স কত?', 'options': ['০-৬ মাস', '৬-১২ মাস', '১-৫ বছর']},
          {'question': 'কোন টিকা মিস হয়েছে?', 'options': ['BCG/OPV', 'DPT/Pentavalent', 'Measles/MMR', 'নিশ্চিত না']},
          {'question': 'কতদিন আগে টিকা দেওয়ার কথা ছিল?', 'options': ['১ সপ্তাহ', '১ মাস', '৩ মাসের বেশি']},
          {'question': 'শিশুর এখন কোনো অসুস্থতা আছে?', 'options': ['হ্যাঁ', 'না', 'হালকা জ্বর']},
          {'question': 'আগে কোনো টিকায় পার্শ্বপ্রতিক্রিয়া হয়েছিল?', 'options': ['হ্যাঁ', 'না', 'মনে নেই']},
        ],
        'emergency' => [
          {'question': 'সমস্যা কতক্ষণ ধরে হচ্ছে?', 'options': ['কয়েক মিনিট', '১ ঘণ্টা', 'কয়েক ঘণ্টা']},
          {'question': 'অতিরিক্ত রক্তপাত হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'একটু']},
          {'question': 'খিঁচুনি বা অজ্ঞান হয়েছে?', 'options': ['হ্যাঁ', 'না', 'একবার']},
          {'question': 'শ্বাস নিতে খুব কষ্ট হচ্ছে?', 'options': ['হ্যাঁ', 'না', 'অনেক']},
          {'question': 'রোগী সাড়া দিচ্ছে?', 'options': ['হ্যাঁ', 'না', 'আংশিক']},
        ],
        _ => [
          {'question': 'কতদিন ধরে এই সমস্যা?', 'options': ['১ দিন', '২-৩ দিন', '১ সপ্তাহের বেশি']},
          {'question': 'ব্যথা বা অস্বস্তির মাত্রা কেমন?', 'options': ['হালকা', 'মাঝারি', 'তীব্র']},
          {'question': 'জ্বর আছে?', 'options': ['হ্যাঁ', 'না', 'নিশ্চিত না']},
          {'question': 'খাওয়া-দাওয়া স্বাভাবিক আছে?', 'options': ['হ্যাঁ', 'না', 'কিছুটা কম']},
          {'question': 'আগে এই সমস্যা হয়েছিল?', 'options': ['হ্যাঁ', 'না', 'মনে নেই']},
        ],
      };

  ({String outcome, String reason, String nextStep}) _fallbackSummary(
      List<Map<String, String>> history) {
    final dangerCount = history
        .where((h) => h['a'] == 'হ্যাঁ' || h['a'] == 'তীব্র' || h['a'] == 'অনেক')
        .length;
    if (dangerCount >= 3) {
      return (
        outcome: 'emergency',
        reason: 'একাধিক গুরুতর বিপদচিহ্ন পাওয়া গেছে।',
        nextStep: 'এখনই অ্যাম্বুলেন্স কল করুন।',
      );
    } else if (dangerCount >= 1) {
      return (
        outcome: 'attention',
        reason: 'কিছু বিপদচিহ্ন পাওয়া গেছে।',
        nextStep: 'আজই নিকটতম PHC-তে রেফার করুন।',
      );
    }
    return (
      outcome: 'safe',
      reason: 'কোনো গুরুতর বিপদচিহ্ন পাওয়া যায়নি।',
      nextStep: '২ দিন পর রুটিন ফলো-আপ করুন।',
    );
  }
}
