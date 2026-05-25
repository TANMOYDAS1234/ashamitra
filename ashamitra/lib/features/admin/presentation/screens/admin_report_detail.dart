import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Full-detail bottom sheet for a single triage report. Shared by the admin
/// Reports tab and the worker-detail sheet, so an admin can drill into any
/// report from either place.
void showAdminReportDetail(BuildContext context, Map<String, dynamic> r) {
  final band = r['finalBand']?.toString().toUpperCase() ?? '';
  final color = band == 'RED'
      ? AppColors.emergencyRed
      : band == 'YELLOW'
          ? AppColors.warningYellow
          : AppColors.safeGreen;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Band badge + case label
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: AppRadius.smR),
                  child: Text(band,
                      style: AppTextStyles.label.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(r['caseLabel']?.toString() ?? '', style: AppTextStyles.h3),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow('Patient', r['patientName']?.toString() ?? '-'),
            _DetailRow('ASHA Worker', r['ashaName']?.toString() ?? '-'),
            _DetailRow('ASHA Phone', r['ashaPhone']?.toString() ?? '-'),
            _DetailRow('Risk Score', '${r['riskScore'] ?? 0}'),
            _DetailRow('Risk Level', r['riskLevel']?.toString() ?? '-'),
            _DetailRow('Facility', r['facilityType']?.toString() ?? '-'),
            _DetailRow('Recheck After', '${r['recheckAfterHours'] ?? 0} hrs'),
            if ((r['reason']?.toString() ?? '').isNotEmpty)
              _DetailRow('Reason', r['reason'].toString()),
            if ((r['nextStep']?.toString() ?? '').isNotEmpty)
              _DetailRow('Next Step', r['nextStep'].toString()),
            if ((r['situation']?.toString() ?? '').isNotEmpty)
              _DetailRow('Situation', r['situation'].toString()),
            if ((r['dangerSigns'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Danger Signs',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (r['dangerSigns'] as List)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.emergencyRed
                                  .withValues(alpha: 0.08),
                              borderRadius: AppRadius.smR),
                          child: Text(s.toString(),
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.emergencyRed,
                              )),
                        ))
                    .toList(),
              ),
            ],
            ..._qaSection(r['qaHistory']),
            const SizedBox(height: 8),
            Text(
              _fmtDate(r['createdAt']?.toString() ?? ''),
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Renders the triage Q&A history, if any.
List<Widget> _qaSection(dynamic raw) {
  final pairs = <(String, String)>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        final q = (e['question'] ?? '').toString().trim();
        final a = (e['answer'] ?? '').toString().trim();
        if (q.isNotEmpty || a.isNotEmpty) pairs.add((q, a));
      }
    }
  }
  if (pairs.isEmpty) return const [];
  return [
    const SizedBox(height: 12),
    Text('Assessment Q&A',
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700,
        )),
    const SizedBox(height: 6),
    for (final (q, a) in pairs)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (q.isNotEmpty)
              Text(q, style: AppTextStyles.caption),
            Text(a.isNotEmpty ? a : '—', style: AppTextStyles.label),
          ],
        ),
      ),
  ];
}

String _fmtDate(String iso) {
  try {
    return DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(iso));
  } catch (_) {
    return iso;
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == '-') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                )),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.label.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onBackground,
                )),
          ),
        ],
      ),
    );
  }
}
