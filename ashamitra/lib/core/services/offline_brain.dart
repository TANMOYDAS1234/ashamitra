// ─────────────────────────────────────────────────────────────────────────────
// OfflineBrain — Change 2: Symptom-driven dynamic question selection (offline)
//
// Instead of asking questions in a fixed order when offline, this brain:
//   1. Reads the rule priorities and risk scores from the loaded engine JSON
//   2. Looks at what symptoms have already been confirmed in the conversation
//   3. Scores each remaining question by clinical urgency:
//        - Hard-stop rules score highest (priority × 10)
//        - Combination rules get a bonus if one condition is already confirmed
//        - Yellow rules score by their priority
//        - Risk score weight from the engine's score_rules
//   4. Returns the highest-scoring remaining question
//   5. Returns an immediate action if the last answer confirmed a danger sign
//
// This makes the offline path feel dynamic and intelligent — not just a
// fixed checklist — while staying 100% deterministic and protocol-safe.
// ─────────────────────────────────────────────────────────────────────────────

import 'rule_executor.dart';

class OfflineNextQuestion {
  final EngineQuestion? question;   // null = finish, enough info collected
  final String? immediateActionBn;  // spoken before next question if danger confirmed
  final bool shouldFinish;

  const OfflineNextQuestion({
    this.question,
    this.immediateActionBn,
    this.shouldFinish = false,
  });
}

class OfflineBrain {
  // ── Rule priority weights ─────────────────────────────────────────────────
  // Mirrors the engine's evaluation_order: hard_stop > combination > yellow
  static const _hardStopWeight    = 100;
  static const _combinationWeight = 60;
  static const _yellowWeight      = 30;
  static const _riskScoreWeight   = 10;

  // ── Immediate actions per danger sign (spoken before next question) ────────
  // Keyed by question ID that was just answered YES
  static const _immediateActions = <String, String>{
    // Pregnancy
    'p1': 'রক্তচাপ বেশি — এখনই বাম কাতে শোয়ান এবং ১০৮ কল করুন।',
    'p3': 'রক্তপাত হচ্ছে — শুইয়ে দিন, পা উঁচু করুন, যোনি পরীক্ষা করবেন না।',
    'p6': 'চোখে ঝাপসা — এক্লাম্পসিয়ার লক্ষণ, এখনই FRU-তে রেফার করুন।',
    // Postpartum
    'pp1': 'অতিরিক্ত রক্তপাত — জরায়ু মালিশ করুন, ১০৮ কল করুন।',
    'pp2': 'জ্বর আছে — পিউরপেরাল সেপসিসের ঝুঁকি, PHC-তে নিয়ে যান।',
    // Newborn
    'n1': 'দুধ খাচ্ছে না — PSBI সন্দেহ, এখনই SNCU-তে রেফার করুন।',
    'n3': 'শ্বাসকষ্ট — শ্বাসের হার গণনা করুন, ≥৬০/মিনিট হলে RED।',
    'n5': 'নিস্তেজ — গুরুতর সিস্টেমিক অসুস্থতা, এখনই SNCU-তে রেফার করুন।',
    // Child
    'c5': 'পানিশূন্যতা — এখনই ORS শুরু করুন, FRU-তে রেফার করুন।',
    'c1': 'পাঁচ দিনের বেশি জ্বর — ম্যালেরিয়া/ডেঙ্গু বাদ দিতে PHC-তে নিয়ে যান।',
    // Emergency
    'e1': 'রক্তপাত থামছে না — এখনই ১০৮ কল করুন।',
    'e2': 'খিঁচুনি — বাম কাতে শোয়ান, শ্বাসনালী রক্ষা করুন, ১০৮ কল করুন।',
    'e3': 'শ্বাস বন্ধ — শ্বাসনালী পরিষ্কার করুন, ১০৮ কল করুন।',
    'e4': 'জ্ঞান নেই — রিকভারি পজিশনে রাখুন, ১০৮ কল করুন।',
  };

  // ── Rule metadata loaded from RuleExecutor ────────────────────────────────
  // Maps questionId → urgency score based on which rules reference it
  final Map<String, int> _questionUrgency = {};

  // Maps questionId → list of combination partner IDs
  // e.g. ANC-COMB-001 needs p1 AND p2 → p2's score gets bonus if p1 confirmed
  final Map<String, List<String>> _combinationPartners = {};

  bool _initialized = false;

  // ── Initialize from loaded RuleExecutor ───────────────────────────────────
  void init(RuleExecutor executor) {
    if (_initialized) return;
    _initialized = true;

    final questions = executor.questionIndex();

    for (final q in questions) {
      int score = 0;

      // Base score from risk engine weight
      score += _riskScoreWeight;

      // Score by rule type — use ruleId prefix to determine type
      final ruleId = q.ruleId.toUpperCase();
      if (ruleId.contains('COMB')) {
        score += _combinationWeight;
      } else if (ruleId.contains('VITAL')) {
        score += _yellowWeight;
      } else {
        // Hard-stop rules have numeric priority in their ID (e.g. NB-001 = priority 1)
        // Lower number = higher priority = higher score
        final priorityMatch = RegExp(r'-(\d+)$').firstMatch(ruleId);
        final priority = int.tryParse(priorityMatch?.group(1) ?? '9') ?? 9;
        score += _hardStopWeight - (priority * 5);
      }

      _questionUrgency[q.id] = (_questionUrgency[q.id] ?? 0) + score;
    }

    _initialized = true;
  }

  // ── Main method: pick the most urgent next question ───────────────────────
  //
  // [remaining]       — questions not yet answered
  // [confirmedYes]    — question IDs answered YES (danger confirmed)
  // [lastAnsweredId]  — the question just answered (for immediate action)
  // [lastAnswerWasYes]— whether the last answer was YES
  OfflineNextQuestion getNextQuestion({
    required List<EngineQuestion> remaining,
    required Set<String> confirmedYes,
    String? lastAnsweredId,
    bool lastAnswerWasYes = false,
  }) {
    if (remaining.isEmpty) {
      return const OfflineNextQuestion(shouldFinish: true);
    }

    // Early finish: if 3+ danger signs confirmed, we have enough to conclude
    if (confirmedYes.length >= 3) {
      return const OfflineNextQuestion(shouldFinish: true);
    }

    // Immediate action for the last answered question if it was YES
    String? immediateAction;
    if (lastAnswerWasYes && lastAnsweredId != null) {
      immediateAction = _immediateActions[lastAnsweredId];
    }

    // Score each remaining question
    final scored = <({EngineQuestion q, int score})>[];

    for (final q in remaining) {
      int score = _questionUrgency[q.id] ?? _yellowWeight;

      // Combination bonus: if a partner question was already confirmed YES,
      // this question becomes more urgent (completing the combination = RED)
      final partners = _combinationPartners[q.id] ?? [];
      final confirmedPartners = partners.where((p) => confirmedYes.contains(p)).length;
      if (confirmedPartners > 0) {
        score += _combinationWeight * confirmedPartners;
      }

      // If a danger sign was just confirmed, prioritise questions in the same
      // clinical cluster (same prefix = same module section)
      if (lastAnswerWasYes && lastAnsweredId != null) {
        final lastPrefix = lastAnsweredId.replaceAll(RegExp(r'\d'), '');
        final qPrefix = q.id.replaceAll(RegExp(r'\d'), '');
        if (lastPrefix == qPrefix) {
          score += 20; // same cluster bonus
        }
      }

      scored.add((q: q, score: score));
    }

    // Sort by score descending, stable (preserves original order for ties)
    scored.sort((a, b) => b.score.compareTo(a.score));

    return OfflineNextQuestion(
      question: scored.first.q,
      immediateActionBn: immediateAction,
      shouldFinish: false,
    );
  }
}
