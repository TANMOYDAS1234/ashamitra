// ─────────────────────────────────────────────────────────────────────────────
// ImmediateActionEngine — Change 3
//
// Fires protocol-correct Bengali immediate actions mid-conversation the moment
// a danger sign is confirmed (answer = YES / danger option).
//
// Used by BOTH online (Gemini) and offline (OfflineBrain) paths so the ASHA
// always gets actionable guidance immediately — not just at the final result.
//
// Design:
//   - Primary actions: spoken immediately when a single danger sign confirmed
//   - Combination actions: spoken when two related danger signs both confirmed
//   - Escalation actions: spoken when 3+ danger signs confirmed (before finish)
// ─────────────────────────────────────────────────────────────────────────────

class ImmediateAction {
  final String textBn;
  final bool isEmergency; // true = RED-level, false = YELLOW-level

  const ImmediateAction({required this.textBn, required this.isEmergency});
}

class ImmediateActionEngine {
  // ── Single danger sign actions ────────────────────────────────────────────
  static const _singleActions = <String, ImmediateAction>{
    // ── Pregnancy ──────────────────────────────────────────────────────────
    'p1': ImmediateAction(
      textBn: 'রক্তচাপ বেশি বা মাথা ব্যথা — এখনই বাম কাতে শোয়ান। ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'p2': ImmediateAction(
      textBn: 'পা বা মুখ ফুলেছে — বিশ্রাম নিন, পা উঁচু রাখুন। ২৪ ঘণ্টার মধ্যে PHC।',
      isEmergency: false,
    ),
    'p3': ImmediateAction(
      textBn: 'রক্তপাত বা তীব্র পেট ব্যথা — শুইয়ে দিন, যোনি পরীক্ষা করবেন না। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'p4': ImmediateAction(
      textBn: 'বাচ্চার নড়াচড়া কমেছে — মাকে বাম কাতে শোয়ান। আজই FRU-তে নিয়ে যান।',
      isEmergency: true,
    ),
    'p6': ImmediateAction(
      textBn: 'চোখে ঝাপসা বা মাথা ঘোরা — এক্লাম্পসিয়ার লক্ষণ। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),

    // ── Postpartum ─────────────────────────────────────────────────────────
    'pp1': ImmediateAction(
      textBn: 'অতিরিক্ত রক্তপাত — জরায়ু মালিশ করুন, পা উঁচু রাখুন। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'pp2': ImmediateAction(
      textBn: 'জ্বর আছে — পিউরপেরাল সেপসিসের ঝুঁকি। ২৪ ঘণ্টার মধ্যে PHC-তে নিয়ে যান।',
      isEmergency: false,
    ),
    'pp3': ImmediateAction(
      textBn: 'স্তনে ব্যথা বা ফোলা — বুকের দুধ চালিয়ে যান, গরম সেঁক দিন। PHC-তে অ্যান্টিবায়োটিক নিন।',
      isEmergency: false,
    ),
    'pp4': ImmediateAction(
      textBn: 'পেটে তীব্র ব্যথা বা সেলাইয়ে সমস্যা — ক্ষত সংক্রমণের ঝুঁকি। ২৪ ঘণ্টার মধ্যে PHC।',
      isEmergency: false,
    ),
    'pp6': ImmediateAction(
      textBn: 'খুব দুর্বল বা মাথা ঘোরা — রক্তাল্পতার লক্ষণ। PHC-তে Hb পরীক্ষা করুন।',
      isEmergency: false,
    ),

    // ── Newborn ────────────────────────────────────────────────────────────
    'n1': ImmediateAction(
      textBn: 'শিশু দুধ খাচ্ছে না — PSBI সন্দেহ। এখনই SNCU/FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n2': ImmediateAction(
      textBn: 'নবজাতকের জ্বর — যেকোনো জ্বর বিপদচিহ্ন। এখনই SNCU/FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n3': ImmediateAction(
      textBn: 'শ্বাসকষ্ট — শ্বাসের হার গণনা করুন। ৬০/মিনিটের বেশি হলে এখনই SNCU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n4': ImmediateAction(
      textBn: 'নাভিতে সংক্রমণ — ওম্ফালাইটিস কয়েক ঘণ্টায় সেপসিসে পরিণত হতে পারে। এখনই FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n5': ImmediateAction(
      textBn: 'শিশু নিস্তেজ — গুরুতর সিস্টেমিক অসুস্থতা। এখনই SNCU/FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n6': ImmediateAction(
      textBn: 'ত্বক হলুদ বা নীলাভ — জন্ডিস বা সায়ানোসিস। এখনই SNCU-তে রেফার করুন।',
      isEmergency: true,
    ),

    // ── Child ──────────────────────────────────────────────────────────────
    'c1': ImmediateAction(
      textBn: 'পাঁচ দিনের বেশি জ্বর — ম্যালেরিয়া বা ডেঙ্গু হতে পারে। আজই PHC/DH-তে নিয়ে যান।',
      isEmergency: true,
    ),
    'c2': ImmediateAction(
      textBn: 'কাশি বা শ্বাসকষ্ট — শ্বাসের হার গণনা করুন। বুকে ইনড্রয়িং থাকলে RED।',
      isEmergency: false,
    ),
    'c3': ImmediateAction(
      textBn: 'ডায়রিয়া বা বমি — এখনই ORS শুরু করুন। পানিশূন্যতার লক্ষণ দেখুন।',
      isEmergency: false,
    ),
    'c5': ImmediateAction(
      textBn: 'পানিশূন্যতার লক্ষণ — এখনই ORS শুরু করুন। IV তরলের জন্য FRU-তে রেফার করুন।',
      isEmergency: true,
    ),

    // ── Emergency ──────────────────────────────────────────────────────────
    'e1': ImmediateAction(
      textBn: 'অতিরিক্ত রক্তপাত — এখনই ১০৮ কল করুন। প্রসব-পরবর্তী হলে জরায়ু মালিশ করুন।',
      isEmergency: true,
    ),
    'e2': ImmediateAction(
      textBn: 'খিঁচুনি বা অজ্ঞান — বাম কাতে শোয়ান, শ্বাসনালী রক্ষা করুন। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'e3': ImmediateAction(
      textBn: 'শ্বাস বন্ধ — শ্বাসনালী পরিষ্কার করুন। নবজাতক হলে উদ্দীপনা দিন। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'e4': ImmediateAction(
      textBn: 'জ্ঞান নেই — রিকভারি পজিশনে রাখুন, শ্বাস পরীক্ষা করুন। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
  };

  // ── Combination actions — fired when BOTH questions confirmed YES ──────────
  // Key format: 'id1+id2' (sorted alphabetically)
  static const _combinationActions = <String, ImmediateAction>{
    'p1+p2': ImmediateAction(
      textBn: 'উচ্চ রক্তচাপ এবং ফোলা একসাথে — প্রি-এক্লাম্পসিয়া। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'p2+p6': ImmediateAction(
      textBn: 'ফোলা এবং ঝাপসা দৃষ্টি — আসন্ন এক্লাম্পসিয়া। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'pp1+pp2': ImmediateAction(
      textBn: 'রক্তপাত এবং জ্বর একসাথে — পিউরপেরাল সেপসিস। এখনই ১০৮ কল করুন।',
      isEmergency: true,
    ),
    'pp2+pp4': ImmediateAction(
      textBn: 'পেট ব্যথা এবং জ্বর — পেরিটোনাইটিসের ঝুঁকি। এখনই FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'c2+c5': ImmediateAction(
      textBn: 'শ্বাসকষ্ট এবং পানিশূন্যতা — গুরুতর নিউমোনিয়া। এখনই FRU-তে রেফার করুন।',
      isEmergency: true,
    ),
    'n2+n3': ImmediateAction(
      textBn: 'জ্বর এবং শ্বাসকষ্ট — গুরুতর PSBI। এখনই SNCU-তে রেফার করুন।',
      isEmergency: true,
    ),
  };

  // ── Escalation action — 3+ danger signs confirmed ─────────────────────────
  static const _escalationAction = ImmediateAction(
    textBn: 'একাধিক গুরুতর বিপদচিহ্ন পাওয়া গেছে। এখনই ১০৮ কল করুন এবং নিকটতম FRU-তে রেফার করুন।',
    isEmergency: true,
  );

  /// Returns the immediate action to speak after an answer, or null if none.
  ///
  /// [answeredId]   — question ID just answered
  /// [answerWasYes] — true if the danger option was selected
  /// [confirmedYes] — all question IDs answered YES so far (including current)
  static ImmediateAction? getAction({
    required String answeredId,
    required bool answerWasYes,
    required Set<String> confirmedYes,
  }) {
    if (!answerWasYes) return null;

    // Check escalation first (3+ danger signs)
    if (confirmedYes.length >= 3) return _escalationAction;

    // Check combination actions
    for (final entry in _combinationActions.entries) {
      final parts = entry.key.split('+');
      if (parts.length == 2 &&
          confirmedYes.contains(parts[0]) &&
          confirmedYes.contains(parts[1])) {
        return entry.value;
      }
    }

    // Single danger sign action
    return _singleActions[answeredId];
  }
}
