import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/components/app_header.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/risk_badge.dart';
import '../../controller/patient_controller.dart';

class PatientProfileScreen extends StatelessWidget {
  const PatientProfileScreen({super.key});

  // Case icon — handles both English (manual patients) and Bengali
  // (triage-created patients) type strings.
  String _caseIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('pregnan') || type.contains('গর্ভ')) return '🤰';
    if (t.contains('postpartum') || type.contains('প্রসব')) return '🤱';
    if (t.contains('newborn') || type.contains('নবজাতক')) return '👶';
    if (t.contains('child') || type.contains('শিশু')) return '🧒';
    if (t.contains('immun') || type.contains('টিকা')) return '💉';
    if (t.contains('emergency') || type.contains('জরুরি')) return '🚑';
    return '🏥';
  }

  @override
  Widget build(BuildContext context) {
    final args = (Get.arguments as Map<String, dynamic>?) ?? {};
    final patientId = (args['id'] as String?)?.trim() ?? '';
    final name = (args['name'] as String?)?.trim().isNotEmpty == true
        ? args['name'] as String
        : 'Unknown';
    final type = args['type'] as String? ?? 'Other';
    final village = (args['village'] as String?)?.trim() ?? '';
    final mobile = (args['mobile'] as String?)?.trim() ?? '';
    final lastVisit = (args['lastVisit'] as String?)?.trim();

    // ── Real triage assessment data carried by PatientModel ───────────────
    final outcome = args['outcome'] as String?;
    final reason = (args['reason'] as String?)?.trim() ?? '';
    final nextStep = (args['nextStep'] as String?)?.trim() ?? '';
    final situation = (args['situation'] as String?)?.trim() ?? '';

    final qaHistory = <({String q, String a})>[];
    final qaRaw = args['qaHistory'];
    if (qaRaw is List) {
      for (final e in qaRaw) {
        if (e is Map) {
          final q = (e['question'] ?? '').toString().trim();
          final a = (e['answer'] ?? '').toString().trim();
          if (q.isNotEmpty || a.isNotEmpty) qaHistory.add((q: q, a: a));
        }
      }
    }

    // Risk — derive from outcome so the badge matches the patient list card.
    final riskRaw = args['risk'];
    final risk = switch (outcome) {
      'emergency' => RiskLevel.emergency,
      'attention' => RiskLevel.high,
      'safe'      => RiskLevel.safe,
      _ => riskRaw is RiskLevel
          ? riskRaw
          : switch (riskRaw?.toString() ?? '') {
              'emergency' => RiskLevel.emergency,
              'high'      => RiskLevel.high,
              'moderate'  => RiskLevel.moderate,
              _           => RiskLevel.safe,
            },
    };

    final hasAssessment = (outcome != null && outcome.isNotEmpty) ||
        reason.isNotEmpty ||
        nextStep.isNotEmpty ||
        situation.isNotEmpty ||
        qaHistory.isNotEmpty;

    // Past triage reports linked to this patient (by id, name as fallback).
    final history = <Map<String, dynamic>>[];
    if (Get.isRegistered<PatientController>()) {
      for (final r in Get.find<PatientController>().reports) {
        final rid = (r['patientId'] ?? '').toString();
        final rname = (r['patientName'] ?? '').toString();
        final byId = patientId.isNotEmpty && rid == patientId;
        final byName = name != 'Unknown' && rname.isNotEmpty && rname == name;
        if (byId || (rid.isEmpty && byName)) {
          history.add(Map<String, dynamic>.from(r));
        }
      }
      history.sort((a, b) => (b['createdAt'] ?? '')
          .toString()
          .compareTo((a['createdAt'] ?? '').toString()));
    }

    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Patient Profile'),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Column(
                    children: [
                      // ── Patient header card ──────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppRadius.xlR,
                          boxShadow: AppShadows.mid,
                        ),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'patient_avatar_$patientId',
                              child: Container(
                                width: 64, height: 64,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [AppColors.primary, AppColors.purple],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    initial,
                                    style: AppTextStyles.display.copyWith(
                                      fontSize: 26,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.h2,
                                  ),
                                  if (village.isNotEmpty && village != '—')
                                    Text(
                                      'Village: $village',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.bodySm,
                                    ),
                                  if (mobile.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.phone_rounded,
                                              size: 13,
                                              color: AppColors.textSecondary),
                                          const SizedBox(width: 4),
                                          Text(mobile, style: AppTextStyles.bodySm),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  RiskBadge(level: risk),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ── Info cards ───────────────────────────────────
                      Row(
                        children: [
                          _InfoCard('${_caseIcon(type)} Case', type,
                              Icons.assignment_rounded, AppColors.primary),
                          const SizedBox(width: 10),
                          _InfoCard('Last Visit',
                              lastVisit?.isNotEmpty == true ? lastVisit! : '—',
                              Icons.calendar_month_rounded, AppColors.sky),
                          const SizedBox(width: 10),
                          _InfoCard('Status', risk.label,
                              Icons.favorite_rounded,
                              risk == RiskLevel.emergency
                                  ? AppColors.emergencyRed
                                  : risk == RiskLevel.high
                                      ? AppColors.warningYellow
                                      : AppColors.safeGreen),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AppButton(
                        label: 'Start Voice Checkup',
                        onPressed: () => Get.toNamed(
                          AppRoutes.selectCase,
                          arguments: {
                            if (patientId.isNotEmpty) 'patientId': patientId,
                            'patientName': name,
                          },
                        ),
                        icon: Icons.mic_rounded,
                        width: double.infinity,
                      ),
                      const SizedBox(height: 24),
                      // ── Last assessment — real triage data ───────────
                      if (hasAssessment) ...[
                        const _SectionTitle('Last Assessment'),
                        const SizedBox(height: 12),
                        if (outcome != null && outcome.isNotEmpty)
                          _AssessmentCard(
                              outcome: outcome,
                              reason: reason,
                              nextStep: nextStep),
                        if (situation.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _TextCard(
                              title: 'Reported Situation', body: situation),
                        ],
                        if (qaHistory.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _QaCard(qaHistory: qaHistory),
                        ],
                      ] else
                        const _EmptyAssessment(),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const _SectionTitle('Report History'),
                        const SizedBox(height: 12),
                        _ReportHistory(reports: history),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on RiskLevel {
  String get label => switch (this) {
        RiskLevel.safe => 'Safe',
        RiskLevel.moderate => 'Moderate',
        RiskLevel.high => 'High Risk',
        RiskLevel.emergency => 'Emergency',
      };
}

// ── Section title ─────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: AppTextStyles.h3),
      );
}

// ── Assessment card — color-coded by triage outcome ───────────────────────
class _AssessmentCard extends StatelessWidget {
  final String outcome;
  final String reason;
  final String nextStep;

  const _AssessmentCard({
    required this.outcome,
    required this.reason,
    required this.nextStep,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, border, textColor, label, icon) = switch (outcome) {
      'emergency' => (
          const Color(0xFFFFEBEB),
          AppColors.emergencyRed,
          const Color(0xFF7F1D1D),
          'Emergency',
          Icons.emergency_rounded,
        ),
      'attention' => (
          const Color(0xFFFFFBEB),
          AppColors.warningYellow,
          const Color(0xFF78350F),
          'Attention',
          Icons.warning_amber_rounded,
        ),
      _ => (
          const Color(0xFFECFDF5),
          AppColors.safeGreen,
          const Color(0xFF064E3B),
          'Safe',
          Icons.check_circle_outline_rounded,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: border, size: 18),
              const SizedBox(width: 8),
              Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: border, letterSpacing: 0.4)),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(reason,
                style: TextStyle(fontSize: 14, color: textColor, height: 1.6)),
          ],
          if (nextStep.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.arrow_forward_rounded, size: 13, color: border),
                      const SizedBox(width: 5),
                      Text('NEXT STEP',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: border, letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(nextStep,
                      style: TextStyle(fontSize: 13, color: textColor,
                          height: 1.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Plain text card (reported situation) ──────────────────────────────────
class _TextCard extends StatelessWidget {
  final String title;
  final String body;

  const _TextCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.primary, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(body,
                style: const TextStyle(fontSize: 14,
                    color: AppColors.onBackground, height: 1.5)),
          ],
        ),
      );
}

// ── Q&A history from the actual triage ────────────────────────────────────
class _QaCard extends StatelessWidget {
  final List<({String q, String a})> qaHistory;

  const _QaCard({required this.qaHistory});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ASSESSMENT Q&A',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.primary, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            for (var i = 0; i < qaHistory.length; i++) ...[
              if (qaHistory[i].q.isNotEmpty) ...[
                Text(qaHistory[i].q,
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.textSecondary, height: 1.4)),
                const SizedBox(height: 3),
              ],
              Text(qaHistory[i].a.isNotEmpty ? qaHistory[i].a : '—',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.onBackground)),
              if (i != qaHistory.length - 1)
                const Divider(height: 16, color: Color(0xFFE0E7FF)),
            ],
          ],
        ),
      );
}

// ── Empty state — manually added patient with no triage yet ───────────────
class _EmptyAssessment extends StatelessWidget {
  const _EmptyAssessment();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        child: Column(
          children: [
            Icon(Icons.assignment_outlined, size: 40,
                color: AppColors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No assessment recorded yet',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: AppColors.onBackground)),
            const SizedBox(height: 4),
            const Text(
                'Start a voice checkup to record the first triage assessment '
                'for this patient.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary,
                    height: 1.5)),
          ],
        ),
      );
}

// ── Past triage reports linked to this patient ────────────────────────────
class _ReportHistory extends StatelessWidget {
  final List<Map<String, dynamic>> reports;

  const _ReportHistory({required this.reports});

  static String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E7FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('REPORT HISTORY (${reports.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.primary, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            for (var i = 0; i < reports.length; i++) ...[
              _row(reports[i]),
              if (i != reports.length - 1)
                const Divider(height: 18, color: Color(0xFFE0E7FF)),
            ],
          ],
        ),
      );

  Widget _row(Map<String, dynamic> r) {
    final outcome = (r['outcome'] ?? 'safe').toString();
    final (color, label) = switch (outcome) {
      'emergency' => (AppColors.emergencyRed, 'Emergency'),
      'attention' => (AppColors.warningYellow, 'Attention'),
      _           => (AppColors.safeGreen, 'Safe'),
    };
    final date = _formatDate((r['createdAt'] ?? '').toString());
    final caseLabel = (r['caseLabel'] ?? '').toString().trim();
    final reason = (r['reason'] ?? '').toString().trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10, height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                          color: color)),
                  const Spacer(),
                  if (date.isNotEmpty)
                    Text(date,
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.textSecondary)),
                ],
              ),
              if (caseLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(caseLabel,
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.textSecondary)),
              ],
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(reason,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12,
                        color: AppColors.onBackground, height: 1.4)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Info card ─────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgR,
          boxShadow: AppShadows.tinted(color),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.label,
            ),
            Text(
              label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}
