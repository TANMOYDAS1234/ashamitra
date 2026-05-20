import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/utils/pdf_helper.dart';
import '../../../../shared/components/bottom_nav.dart';
import '../../../patients/controller/patient_controller.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
    final doc = pw.Document();
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
              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    const Text('রিপোর্ট',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onBackground)),
                    const Spacer(),
                    // Fix GetX warning: single Obx only where reactive data is read
                    Obx(() {
                      final reports = ctrl.reports.toList();
                      return GestureDetector(
                        onTap: () => _downloadPdf(reports),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded,
                                  color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text('PDF',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 20),
                child: Text('সকল ট্রায়াজ সেশন',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),

              // Fix overflow bottom: Expanded wraps the reactive list
              Expanded(
                child: Obx(() {
                  if (ctrl.isLoading.value) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    );
                  }

                  final reports = ctrl.reports;

                  if (reports.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 56, color: AppColors.textLight),
                          SizedBox(height: 12),
                          Text('এখনো কোনো রিপোর্ট নেই',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.textSecondary)),
                          SizedBox(height: 4),
                          Text('ট্রায়াজ করলে এখানে দেখাবে',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textLight)),
                        ],
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

                        const Text('সেশন ইতিহাস',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onBackground)),
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
  final String count;
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(height: 6),
            Text(count,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ── Individual report card ────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final dangerSigns =
        (r['dangerSigns'] as List? ?? []).cast<String>();
    final riskScore = r['riskScore'] as int? ?? 0;
    final facilityType = r['facilityType']?.toString() ?? '';
    final recheckHours = r['recheckAfterHours'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: outcomeColor.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: outcomeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child:
                    Icon(outcomeIcon, color: outcomeColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['caseLabel']?.toString() ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onBackground)),
                    const SizedBox(height: 2),
                    Text(
                      r['patientName']?.toString().isNotEmpty == true
                          ? r['patientName'].toString()
                          : 'অজ্ঞাত রোগী',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                    Text(
                        formatDate(
                            r['createdAt']?.toString() ?? ''),
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textLight)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Fix overflow right: Column instead of unbounded Row on right side
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: outcomeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(outcomeLabel,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: outcomeColor)),
                  ),
                  if (riskScore > 0) ...[
                    const SizedBox(height: 4),
                    Text('Score: $riskScore',
                        style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textLight)),
                  ],
                ],
              ),
            ],
          ),
          if (dangerSigns.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: dangerSigns
                  .take(3)
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              outcomeColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: outcomeColor
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                fontSize: 9,
                                color: outcomeColor,
                                fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
            ),
          ],
          if (facilityType.isNotEmpty && facilityType != 'None') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.local_hospital_rounded,
                    size: 11, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(facilityType,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary))),
                if (recheckHours > 0)
                  Text('ফলো-আপ: ${recheckHours}h',
                      style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textLight)),
              ],
            ),
          ],
        ],
      ),
    );
  }
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('কেস ধরন বিভাজন',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground)),
          const SizedBox(height: 12),
          ...counts.entries.toList().asMap().entries.map((entry) {
            final i = entry.key;
            final label = entry.value.key;
            final count = entry.value.value;
            final color = colors[i % colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(label,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onBackground))),
                      Text('$count কেস',
                          style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: count / total,
                      backgroundColor:
                          color.withValues(alpha: 0.1),
                      color: color,
                      minHeight: 6,
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
