import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import '../../../../shared/widgets/referral_map/referral_map_widget.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/pdf_helper.dart';
import '../../../../shared/components/app_header.dart';
import '../../../../shared/components/bottom_nav.dart';
import '../../../../shared/widgets/count_up.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../patients/controller/patient_controller.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ── Filter state ────────────────────────────────────────────────────────
  // Worker only sees their own reports — no need for worker/district axes.
  // Band: 'all' | 'emergency' | 'attention' | 'safe'
  // Time: 'all' | 'today' | 'week' | 'month'
  String _bandFilter = 'all';
  String _timeFilter = 'all';

  bool _matchesFilters(Map<String, dynamic> r) {
    if (_bandFilter != 'all' && r['outcome']?.toString() != _bandFilter) {
      return false;
    }
    if (_timeFilter == 'all') return true;
    final created = DateTime.tryParse(r['createdAt']?.toString() ?? '');
    if (created == null) return false;
    final now = DateTime.now();
    switch (_timeFilter) {
      case 'today':
        return created.year == now.year &&
            created.month == now.month &&
            created.day == now.day;
      case 'week':
        return now.difference(created).inDays < 7;
      case 'month':
        return created.year == now.year && created.month == now.month;
    }
    return true;
  }

  Color _outcomeColor(String outcome) => switch (outcome) {
        'emergency' => AppColors.emergencyRed,
        'attention' => AppColors.warningYellow,
        _ => AppColors.safeGreen,
      };

  IconData _outcomeIcon(String outcome) => switch (outcome) {
        'emergency' => Icons.emergency_rounded,
        'attention' => Icons.warning_amber_rounded,
        _ => Icons.check_circle_rounded,
      };

  String _outcomeLabel(String outcome) => switch (outcome) {
        'emergency' => 'জরুরি',
        'attention' => 'মনোযোগ দরকার',
        _ => 'নিরাপদ',
      };

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // ── Band colour helpers for PDF ──────────────────────────────────────────
  PdfColor _pdfBandColor(String outcome) => switch (outcome) {
    'emergency' => const PdfColor.fromInt(0xFFDC2626),
    'attention' => const PdfColor.fromInt(0xFFD97706),
    _ => const PdfColor.fromInt(0xFF16A34A),
  };

  String _bandLabel(String outcome) => switch (outcome) {
    'emergency' => 'RED — জরুরি',
    'attention' => 'YELLOW — মনোযোগ দরকার',
    _ => 'GREEN — নিরাপদ',
  };

  // ── Section heading widget ────────────────────────────────────────────────
  pw.Widget _sectionHeading(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 20, bottom: 8),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFEEF2FF),
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(title,
            style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF3730A3))),
      );

  // ── Key-value row ─────────────────────────────────────────────────────────
  pw.Widget _kvRow(String key, String value, {bool highlight = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(key,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey700)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 10,
                      color: highlight
                          ? const PdfColor.fromInt(0xFFDC2626)
                          : PdfColors.grey900,
                      fontWeight: highlight
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal)),
            ),
          ],
        ),
      );

  // ── Stat box ──────────────────────────────────────────────────────────────
  pw.Widget _statBox(String label, String value, PdfColor color) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 10),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.white)),
            ],
          ),
        ),
      );

  Future<void> _downloadPdf(List<Map<String, dynamic>> reports) async {
    // Defense-in-depth: catch ANY exception thrown during font load, page
    // assembly, or save. Previously a font-network failure or a malformed
    // report row would propagate as an unhandled exception, crashing the
    // app in release builds (where R8 strips most error UI). Now the worst
    // case is a red snackbar with the actual error message.
    try {
      // Empty-list guard. PDF generation on zero reports would technically
      // succeed (an empty document), but the percentage math hits 0/0 and
      // some report-row code paths assume at least one entry. Easier to
      // tell the user "nothing to export" than to render a blank file.
      if (reports.isEmpty) {
        Get.snackbar(
          'No reports to export',
          'Complete at least one triage session first.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: AppColors.warningYellow,
          colorText: Colors.white,
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
          duration: const Duration(seconds: 3),
        );
        return;
      }

      final theme = await PdfHelper.bengaliTheme();
      final doc = pw.Document(theme: theme);
      final now = DateTime.now();
      final generatedAt =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}  '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final total = reports.length;
    final emergency = reports.where((r) => r['outcome'] == 'emergency').length;
    final attention = reports.where((r) => r['outcome'] == 'attention').length;
    final safe = reports.where((r) => r['outcome'] == 'safe').length;

    // ── Case type breakdown ───────────────────────────────────────────────
    final caseBreakdown = <String, int>{};
    for (final r in reports) {
      final label = r['caseLabel']?.toString() ?? 'অন্যান্য';
      caseBreakdown[label] = (caseBreakdown[label] ?? 0) + 1;
    }

    // ── Danger sign frequency ─────────────────────────────────────────────
    final dangerFreq = <String, int>{};
    for (final r in reports) {
      for (final s in (r['dangerSigns'] as List? ?? []).cast<String>()) {
        dangerFreq[s] = (dangerFreq[s] ?? 0) + 1;
      }
    }
    final topDangerSigns = dangerFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── Page 1: Cover ─────────────────────────────────────────────────────
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header band
            pw.Container(
              color: const PdfColor.fromInt(0xFF4F46E5),
              padding: const pw.EdgeInsets.fromLTRB(40, 48, 40, 40),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('আশামিত্র',
                      style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 4),
                  pw.Text('ASHA Mitra — Clinical Triage Report',
                      style: const pw.TextStyle(
                          fontSize: 14, color: PdfColors.white)),
                  pw.SizedBox(height: 20),
                  pw.Text('Generated: $generatedAt',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.white)),
                  pw.Text('Total Sessions: $total',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.white)),
                ],
              ),
            ),
            // Summary stat boxes
            pw.Container(
              color: const PdfColor.fromInt(0xFFF8F9FF),
              padding: const pw.EdgeInsets.fromLTRB(36, 32, 36, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('SUMMARY',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey600,
                          letterSpacing: 1.5)),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    children: [
                      _statBox('মোট কেস', '$total',
                          const PdfColor.fromInt(0xFF4F46E5)),
                      _statBox('জরুরি (RED)', '$emergency',
                          const PdfColor.fromInt(0xFFDC2626)),
                      _statBox('মনোযোগ (YELLOW)', '$attention',
                          const PdfColor.fromInt(0xFFD97706)),
                      _statBox('নিরাপদ (GREEN)', '$safe',
                          const PdfColor.fromInt(0xFF16A34A)),
                    ],
                  ),
                  pw.SizedBox(height: 28),
                  // Case type breakdown table
                  pw.Text('CASE TYPE BREAKDOWN',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey600,
                          letterSpacing: 1.5)),
                  pw.SizedBox(height: 10),
                  pw.TableHelper.fromTextArray(
                    headers: ['Case Type', 'Count', '% of Total'],
                    data: caseBreakdown.entries
                        .map((e) => [
                              e.key,
                              '${e.value}',
                              '${(e.value / total * 100).toStringAsFixed(1)}%',
                            ])
                        .toList(),
                    headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: PdfColors.white),
                    headerDecoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF4F46E5)),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.center,
                      2: pw.Alignment.center,
                    },
                    oddRowDecoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFF0F0FF)),
                  ),
                  if (topDangerSigns.isNotEmpty) ...[
                    pw.SizedBox(height: 24),
                    pw.Text('TOP DANGER SIGNS DETECTED',
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey600,
                            letterSpacing: 1.5)),
                    pw.SizedBox(height: 10),
                    pw.TableHelper.fromTextArray(
                      headers: ['Danger Sign', 'Frequency'],
                      data: topDangerSigns
                          .take(8)
                          .map((e) => [e.key, '${e.value} cases'])
                          .toList(),
                      headerStyle: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: PdfColors.white),
                      headerDecoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFDC2626)),
                      cellStyle: const pw.TextStyle(fontSize: 10),
                      oddRowDecoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFFFF0F0)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // ── Pages 2+: Per-session detail ──────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 36),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(
                      color: PdfColor.fromInt(0xFF4F46E5), width: 1.5))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('আশামিত্র — Triage Session Details',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF4F46E5))),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey500)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(
                      color: PdfColors.grey300, width: 0.5))),
          child: pw.Text(
            'ASHA Mitra — Confidential Clinical Record  |  Generated $generatedAt',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey400),
            textAlign: pw.TextAlign.center,
          ),
        ),
        build: (ctx) => [
          _sectionHeading('SESSION DETAILS  (${reports.length} records)'),
          ...reports.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final r = entry.value;
            final outcome = r['outcome']?.toString() ?? 'safe';
            final bandColor = _pdfBandColor(outcome);
            final dangerSigns =
                (r['dangerSigns'] as List? ?? []).cast<String>();
            final suspectedConditions =
                (r['suspectedConditions'] as List? ?? []).cast<String>();
            final triggeredRules =
                (r['triggeredRules'] as List? ?? []).cast<String>();
            final qaHistory = r['qaHistory'] as List? ?? [];
            final riskScore = r['riskScore'] as int? ?? 0;
            final recheckHours = r['recheckAfterHours'] as int? ?? 0;

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfColor(
                      (bandColor.red * 0.4 + 0.6).clamp(0.0, 1.0),
                      (bandColor.green * 0.4 + 0.6).clamp(0.0, 1.0),
                      (bandColor.blue * 0.4 + 0.6).clamp(0.0, 1.0),
                    ),
                    width: 1),
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // ── Session header bar ──────────────────────────────────
                  pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: pw.BoxDecoration(
                      color: bandColor,
                      borderRadius: const pw.BorderRadius.only(
                        topLeft: pw.Radius.circular(5),
                        topRight: pw.Radius.circular(5),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '#$idx  ${r['caseLabel']?.toString() ?? ''}',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white),
                        ),
                        pw.Text(
                          _bandLabel(outcome),
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white),
                        ),
                      ],
                    ),
                  ),

                  // ── Session body ────────────────────────────────────────
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(12),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Basic info
                        _kvRow('Date / Time',
                            _formatDate(r['createdAt']?.toString() ?? '')),
                        _kvRow('Patient Name',
                            r['patientName']?.toString().isNotEmpty == true
                                ? r['patientName'].toString()
                                : 'Not recorded'),
                        _kvRow('Risk Score',
                            riskScore > 0 ? '$riskScore / 100' : '—'),
                        _kvRow('Risk Level',
                            r['riskLevel']?.toString().toUpperCase() ?? '—'),
                        _kvRow('Facility Referral',
                            r['facilityType']?.toString().isNotEmpty == true
                                ? r['facilityType'].toString()
                                : '—'),
                        if (recheckHours > 0)
                          _kvRow('Follow-up In', '$recheckHours hours'),

                        // Situation
                        if ((r['situation']?.toString() ?? '').isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Text('Situation Reported',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700)),
                          pw.SizedBox(height: 3),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: const pw.BoxDecoration(
                              color: PdfColor.fromInt(0xFFF8F9FF),
                              borderRadius: pw.BorderRadius.all(
                                  pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              r['situation'].toString(),
                              style: const pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey800),
                            ),
                          ),
                        ],

                        // Clinical decision
                        pw.SizedBox(height: 8),
                        pw.Text('Clinical Decision',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700)),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColor(
                                (bandColor.red * 0.08 + 0.92).clamp(0.0, 1.0),
                                (bandColor.green * 0.08 + 0.92).clamp(0.0, 1.0),
                                (bandColor.blue * 0.08 + 0.92).clamp(0.0, 1.0),
                              ),
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(4)),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                r['reason']?.toString() ?? '',
                                style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey900),
                              ),
                              if ((r['nextStep']?.toString() ?? '').isNotEmpty) ...[
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Next Step: ${r['nextStep']}',
                                  style: pw.TextStyle(
                                      fontSize: 10,
                                      fontWeight: pw.FontWeight.bold,
                                      color: bandColor),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Danger signs
                        if (dangerSigns.isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Text('Danger Signs Detected',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFFDC2626))),
                          pw.SizedBox(height: 4),
                          pw.Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: dangerSigns
                                .map((s) => pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: const pw.BoxDecoration(
                                        color:
                                            PdfColor.fromInt(0xFFFFEBEB),
                                        borderRadius: pw.BorderRadius.all(
                                            pw.Radius.circular(4)),
                                      ),
                                      child: pw.Text(s,
                                          style: pw.TextStyle(
                                              fontSize: 9,
                                              fontWeight:
                                                  pw.FontWeight.bold,
                                              color: const PdfColor
                                                  .fromInt(0xFFDC2626))),
                                    ))
                                .toList(),
                          ),
                        ],

                        // Suspected conditions
                        if (suspectedConditions.isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Text('Suspected Conditions',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: const PdfColor.fromInt(0xFFD97706))),
                          pw.SizedBox(height: 4),
                          pw.Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: suspectedConditions
                                .map((s) => pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: const pw.BoxDecoration(
                                        color:
                                            PdfColor.fromInt(0xFFFFFBEB),
                                        borderRadius: pw.BorderRadius.all(
                                            pw.Radius.circular(4)),
                                      ),
                                      child: pw.Text(s,
                                          style: pw.TextStyle(
                                              fontSize: 9,
                                              fontWeight:
                                                  pw.FontWeight.bold,
                                              color: const PdfColor
                                                  .fromInt(0xFFD97706))),
                                    ))
                                .toList(),
                          ),
                        ],

                        // Triggered rules
                        if (triggeredRules.isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Text('Triggered Rules',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700)),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            triggeredRules.join('  •  '),
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey600),
                          ),
                        ],

                        // Q&A history
                        if (qaHistory.isNotEmpty) ...[
                          pw.SizedBox(height: 8),
                          pw.Text('Conversation Q&A',
                              style: pw.TextStyle(
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.grey700)),
                          pw.SizedBox(height: 4),
                          pw.TableHelper.fromTextArray(
                            headers: ['Question', 'Answer'],
                            data: qaHistory.map((qa) {
                              final m = qa is Map ? qa : {};
                              return [
                                m['question']?.toString() ?? '',
                                m['answer']?.toString() ?? '',
                              ];
                            }).toList(),
                            headerStyle: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 9,
                                color: PdfColors.white),
                            headerDecoration: const pw.BoxDecoration(
                                color: PdfColor.fromInt(0xFF6366F1)),
                            cellStyle:
                                const pw.TextStyle(fontSize: 9),
                            columnWidths: {
                              0: const pw.FlexColumnWidth(2),
                              1: const pw.FlexColumnWidth(3),
                            },
                            oddRowDecoration: const pw.BoxDecoration(
                                color: PdfColor.fromInt(0xFFF5F5FF)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );

      await PdfHelper.saveAndOpen(
          doc,
          'asha_mitra_report_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf');
    } catch (e, st) {
      // Never let a PDF-build failure crash the app. Show the user the real
      // error (truncated) so they can report it; full stack stays in logcat.
      // ignore: avoid_print
      print('[PDF] build failed: $e\n$st');
      Get.snackbar(
        'PDF generation failed',
        e.toString().length > 200
            ? '${e.toString().substring(0, 200)}...'
            : e.toString(),
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppColors.emergencyRed,
        colorText: Colors.white,
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
        duration: const Duration(seconds: 6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fix GetX warning: find controller in build, not initState of StatefulWidget
    final ctrl = Get.find<PatientController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() {
                final visibleReports = ctrl.reports.where(_matchesFilters).toList();
                return AppHeader(
                  title: 'রিপোর্ট',
                  subtitle: 'সকল ট্রায়াজ সেশন',
                  showBack: false,
                  actions: [
                    HeaderActionPill(
                      icon: Icons.download_rounded,
                      label: 'PDF',
                      onTap: () => _downloadPdf(visibleReports),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 8),

              // ── Filter chips ────────────────────────────────────────────
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _ChipBtn(
                      label: 'সব',
                      selected: _bandFilter == 'all',
                      onTap: () => setState(() => _bandFilter = 'all'),
                    ),
                    _ChipBtn(
                      label: 'জরুরি',
                      color: AppColors.emergencyRed,
                      selected: _bandFilter == 'emergency',
                      onTap: () => setState(() => _bandFilter = 'emergency'),
                    ),
                    _ChipBtn(
                      label: 'মনোযোগ',
                      color: AppColors.warningYellow,
                      selected: _bandFilter == 'attention',
                      onTap: () => setState(() => _bandFilter = 'attention'),
                    ),
                    _ChipBtn(
                      label: 'নিরাপদ',
                      color: AppColors.safeGreen,
                      selected: _bandFilter == 'safe',
                      onTap: () => setState(() => _bandFilter = 'safe'),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      color: AppColors.cardBorder,
                    ),
                    _ChipBtn(
                      label: 'সব সময়',
                      selected: _timeFilter == 'all',
                      onTap: () => setState(() => _timeFilter = 'all'),
                    ),
                    _ChipBtn(
                      label: 'আজ',
                      selected: _timeFilter == 'today',
                      onTap: () => setState(() => _timeFilter = 'today'),
                    ),
                    _ChipBtn(
                      label: '৭ দিন',
                      selected: _timeFilter == 'week',
                      onTap: () => setState(() => _timeFilter = 'week'),
                    ),
                    _ChipBtn(
                      label: 'এই মাস',
                      selected: _timeFilter == 'month',
                      onTap: () => setState(() => _timeFilter = 'month'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Fix overflow bottom: Expanded wraps the reactive list
              Expanded(
                child: Obx(() {
                  if (ctrl.isLoading.value) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: const [
                        Row(
                          children: [
                            SkeletonStatCard(),
                            SizedBox(width: 8),
                            SkeletonStatCard(),
                            SizedBox(width: 8),
                            SkeletonStatCard(),
                            SizedBox(width: 8),
                            SkeletonStatCard(),
                          ],
                        ),
                        SizedBox(height: 20),
                        SkeletonReportCard(),
                        SkeletonReportCard(),
                        SkeletonReportCard(),
                        SkeletonReportCard(),
                      ],
                    );
                  }

                  final allReports = ctrl.reports;
                  final reports = allReports.where(_matchesFilters).toList();

                  if (allReports.isEmpty) {
                    return const EmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'এখনো কোনো রিপোর্ট নেই',
                      subtitle: 'ট্রায়াজ সম্পন্ন করলে এখানে রিপোর্ট দেখাবে',
                    );
                  }
                  if (reports.isEmpty) {
                    return EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'এই ফিল্টারে কোনো রিপোর্ট নেই',
                      subtitle: 'অন্য ব্যান্ড বা সময় বেছে নিন',
                      action: FilledButton.icon(
                        onPressed: () => setState(() {
                          _bandFilter = 'all';
                          _timeFilter = 'all';
                        }),
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        label: const Text('ফিল্টার মুছে ফেলুন'),
                      ),
                    );
                  }

                  final total = reports.length;
                  final emergency = reports
                      .where((r) => r['outcome'] == 'emergency')
                      .length;
                  final attention = reports
                      .where((r) => r['outcome'] == 'attention')
                      .length;
                  final safe =
                      reports.where((r) => r['outcome'] == 'safe').length;

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: ctrl.syncFromServer,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Stats row ──────────────────────────────
                        // Fix overflow right: use Row with Expanded instead of
                        // fixed-width ListView so cards fill available width
                        Row(
                          children: [
                            _StatCard(
                                label: 'মোট কেস',
                                count: '$total',
                                icon: Icons.assignment_rounded,
                                color: AppColors.primary),
                            const SizedBox(width: 8),
                            _StatCard(
                                label: 'জরুরি',
                                count: '$emergency',
                                icon: Icons.emergency_rounded,
                                color: AppColors.emergencyRed),
                            const SizedBox(width: 8),
                            _StatCard(
                                label: 'মনোযোগ',
                                count: '$attention',
                                icon: Icons.warning_amber_rounded,
                                color: AppColors.warningYellow),
                            const SizedBox(width: 8),
                            _StatCard(
                                label: 'নিরাপদ',
                                count: '$safe',
                                icon: Icons.check_circle_rounded,
                                color: AppColors.safeGreen),
                          ],
                        ),
                        const SizedBox(height: 20),

                        _CaseBreakdown(reports: reports.toList()),
                        const SizedBox(height: 20),

                        Text('সেশন ইতিহাস', style: AppTextStyles.h3),
                        const SizedBox(height: 10),

                        ...reports.map((r) => _ReportCard(
                              r: r,
                              outcomeColor: _outcomeColor(
                                  r['outcome']?.toString() ?? 'safe'),
                              outcomeIcon: _outcomeIcon(
                                  r['outcome']?.toString() ?? 'safe'),
                              outcomeLabel: _outcomeLabel(
                                  r['outcome']?.toString() ?? 'safe'),
                              formatDate: _formatDate,
                            )),
                      ],
                    ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNav(currentIndex: 3),
    );
  }
}

// ── Stat card — Expanded so all 4 fill the row width equally ─────────────────
class _StatCard extends StatelessWidget {
  final String label;
  final String count;  // String for backwards-compatibility — parsed to int below
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgR,
          boxShadow: AppShadows.tinted(color),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.smR,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            CountUp(
              value: int.tryParse(count) ?? 0,
              style: AppTextStyles.h2.copyWith(color: color),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Individual report card (expandable) ──────────────────────────────────────
class _ReportCard extends StatefulWidget {
  final Map<String, dynamic> r;
  final Color outcomeColor;
  final IconData outcomeIcon;
  final String outcomeLabel;
  final String Function(String) formatDate;

  const _ReportCard({
    required this.r,
    required this.outcomeColor,
    required this.outcomeIcon,
    required this.outcomeLabel,
    required this.formatDate,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final outcomeColor = widget.outcomeColor;
    final dangerSigns = (r['dangerSigns'] as List? ?? []).cast<String>();
    final suspectedConditions = (r['suspectedConditions'] as List? ?? []).cast<String>();
    final triggeredRules = (r['triggeredRules'] as List? ?? []).cast<String>();
    final qaHistory = r['qaHistory'] as List? ?? [];
    final riskScore = r['riskScore'] as int? ?? 0;
    final facilityType = r['facilityType']?.toString() ?? '';
    final recheckHours = r['recheckAfterHours'] as int? ?? 0;
    final reason = r['reason']?.toString() ?? '';
    final nextStep = r['nextStep']?.toString() ?? '';
    final situation = r['situation']?.toString() ?? '';
    final transportAction = r['transportAction']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.tinted(outcomeColor),
      ),
      child: Column(
        children: [
          // ── Summary row (always visible) ──────────────────────────────
          Material(
            color: Colors.transparent,
            borderRadius: AppRadius.lgR,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: AppRadius.lgR,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          color: outcomeColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle),
                      child: Icon(widget.outcomeIcon, color: outcomeColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['caseLabel']?.toString() ?? '',
                            style: AppTextStyles.labelLg,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r['patientName']?.toString().isNotEmpty == true ? r['patientName'].toString() : 'অজ্ঞাত রোগী',
                            style: AppTextStyles.bodySm,
                          ),
                          Text(
                            widget.formatDate(r['createdAt']?.toString() ?? ''),
                            style: AppTextStyles.caption.copyWith(color: AppColors.textLight),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: outcomeColor.withValues(alpha: 0.12),
                            borderRadius: AppRadius.pillR,
                          ),
                          child: Text(
                            widget.outcomeLabel,
                            style: AppTextStyles.caption.copyWith(
                              color: outcomeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (riskScore > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Score: $riskScore',
                            style: AppTextStyles.caption.copyWith(color: AppColors.textLight, fontSize: 10),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Icon(
                          _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expanded detail section ───────────────────────────────────
          if (_expanded) ...[
            Divider(height: 1, color: outcomeColor.withValues(alpha: 0.15)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Danger signs
                  if (dangerSigns.isNotEmpty) ...[
                    _sectionLabel('বিপদচিহ্ন', Icons.warning_amber_rounded, AppColors.emergencyRed),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: dangerSigns.map((s) => _chip(s, AppColors.emergencyRed)).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Suspected conditions
                  if (suspectedConditions.isNotEmpty) ...[
                    _sectionLabel('সম্ভাব্য অবস্থা', Icons.medical_information_rounded, AppColors.warningYellow),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: suspectedConditions.map((s) => _chip(s, AppColors.warningYellow)).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Clinical decision
                  if (reason.isNotEmpty) ...[
                    _sectionLabel('ক্লিনিক্যাল সিদ্ধান্ত', Icons.assignment_rounded, AppColors.primary),
                    const SizedBox(height: 6),
                    _infoBox(reason, AppColors.primary),
                    const SizedBox(height: 12),
                  ],

                  // Next step
                  if (nextStep.isNotEmpty) ...[
                    _sectionLabel('পরবর্তী পদক্ষেপ', Icons.arrow_forward_rounded, outcomeColor),
                    const SizedBox(height: 6),
                    _infoBox(nextStep, outcomeColor),
                    const SizedBox(height: 12),
                  ],

                  // Situation
                  if (situation.isNotEmpty) ...[
                    _sectionLabel('পরিস্থিতি', Icons.notes_rounded, AppColors.textSecondary),
                    const SizedBox(height: 6),
                    _infoBox(situation, AppColors.textSecondary),
                    const SizedBox(height: 12),
                  ],

                  // Facility & recheck
                  if (facilityType.isNotEmpty && facilityType != 'None') ...[
                    _sectionLabel('রেফার কেন্দ্র', Icons.local_hospital_rounded, AppColors.sky),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _infoBox(facilityType, AppColors.sky)),
                        if (recheckHours > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.sky.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.sky.withValues(alpha: 0.3)),
                            ),
                            child: Text('ফলো-আপ\n${recheckHours}h',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10, color: AppColors.sky, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Transport action
                  if (transportAction.isNotEmpty && transportAction != 'None') ...[
                    _sectionLabel('পরিবহন', Icons.directions_car_rounded, AppColors.purple),
                    const SizedBox(height: 6),
                    _infoBox(transportAction, AppColors.purple),
                    const SizedBox(height: 12),
                  ],

                  // Triggered rules
                  if (triggeredRules.isNotEmpty) ...[
                    _sectionLabel('ট্রিগার্ড রুলস', Icons.rule_rounded, AppColors.textSecondary),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: triggeredRules.map((s) => _chip(s, AppColors.primary)).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Q&A history
                  if (qaHistory.isNotEmpty) ...[
                    _sectionLabel('প্রশ্নোত্তর', Icons.chat_bubble_outline_rounded, AppColors.primary),
                    const SizedBox(height: 8),
                    ...qaHistory.map((qa) {
                      final m = qa is Map ? qa : {};
                      final q = m['question']?.toString() ?? '';
                      final a = m['answer']?.toString() ?? '';
                      if (q.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E7FF)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.4)),
                              const SizedBox(height: 4),
                              Text(a, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onBackground)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  // Nearest referral map
                  if (facilityType.isNotEmpty && facilityType != 'None') ...[
                    const SizedBox(height: 4),
                    ReferralMapWidget(facilityType: facilityType),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, IconData icon, Color color) => Row(
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3)),
    ],
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _infoBox(String text, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.onBackground, height: 1.5)),
  );
}

// ── Case breakdown bar chart ──────────────────────────────────────────────────
class _CaseBreakdown extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  const _CaseBreakdown({required this.reports});

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final r in reports) {
      final label = r['caseLabel']?.toString() ?? 'অন্যান্য';
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final total = reports.length;
    final colors = [
      AppColors.primary,
      AppColors.purple,
      AppColors.sky,
      AppColors.safeGreen,
      AppColors.warningYellow,
      AppColors.emergencyRed,
      const Color(0xFF6366F1),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.mid,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('কেস ধরন বিভাজন', style: AppTextStyles.h3),
          const SizedBox(height: 14),
          ...counts.entries.toList().asMap().entries.map((entry) {
            final i = entry.key;
            final label = entry.value.key;
            final count = entry.value.value;
            final color = colors[i % colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: AppTextStyles.label)),
                      Text(
                        '$count কেস',
                        style: AppTextStyles.label.copyWith(color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: count / total,
                      backgroundColor: color.withValues(alpha: 0.10),
                      color: color,
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Filter chip used by the worker's reports filter row ─────────────────────
class _ChipBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _ChipBtn({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? accent : AppColors.surface,
        borderRadius: AppRadius.pillR,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillR,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent : AppColors.surface,
              borderRadius: AppRadius.pillR,
              boxShadow: selected
                  ? AppShadows.tinted(accent, strength: 2)
                  : AppShadows.low,
            ),
            child: Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
