import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/pdf_helper.dart';
import '../../../../shared/components/app_header.dart';
import '../../../admin/controller/admin_controller.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminController>();

    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.loadReports());
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: 'admin_reports'.tr,
                actions: [
                  Obx(() => HeaderActionPill(
                        icon: Icons.download_rounded,
                        label: 'PDF',
                        onTap: ctrl.filteredReports.isEmpty
                            ? () {}
                            : () => _downloadPdf(ctrl.filteredReports.toList()),
                      )),
                ],
              ),
              const SizedBox(height: 4),

              // ── Filter bar ───────────────────────────────────────
              Obx(() => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _FilterChip(label: 'admin_filter_all'.tr, selected: ctrl.filterMode.value == 'all', onTap: () => ctrl.setFilter('all')),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'admin_filter_day'.tr, selected: ctrl.filterMode.value == 'day', onTap: () => _pickDate(context, ctrl, 'day')),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'admin_filter_month'.tr, selected: ctrl.filterMode.value == 'month', onTap: () => _pickDate(context, ctrl, 'month')),
                        const SizedBox(width: 8),
                        _FilterChip(label: 'admin_filter_year'.tr, selected: ctrl.filterMode.value == 'year', onTap: () => _pickDate(context, ctrl, 'year')),
                        const SizedBox(width: 12),
                        if (ctrl.filterMode.value != 'all' && ctrl.filterDate.value != null)
                          Text(
                            _filterLabel(ctrl.filterMode.value, ctrl.filterDate.value!),
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),

              // ── Summary chips ────────────────────────────────────
              Obx(() => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        _SummaryChip(label: 'মোট ${ctrl.totalReports}', color: AppColors.primary),
                        const SizedBox(width: 8),
                        _SummaryChip(label: '🔴 ${ctrl.redReports}', color: AppColors.emergencyRed),
                        const SizedBox(width: 8),
                        _SummaryChip(label: '🟡 ${ctrl.yellowReports}', color: AppColors.warningYellow),
                        const SizedBox(width: 8),
                        _SummaryChip(label: '🟢 ${ctrl.greenReports}', color: AppColors.safeGreen),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),

              // ── Report list ──────────────────────────────────────
              Expanded(
                child: Obx(() {
                  if (ctrl.isLoading.value) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                  }
                  if (ctrl.filteredReports.isEmpty) {
                    return Center(
                      child: Text('admin_no_reports'.tr, style: AppTextStyles.bodySm),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: ctrl.loadReports,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: ctrl.filteredReports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ReportCard(r: ctrl.filteredReports[i]),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _filterLabel(String mode, DateTime dt) {
    return switch (mode) {
      'day' => DateFormat('dd MMM yyyy').format(dt),
      'month' => DateFormat('MMM yyyy').format(dt),
      'year' => dt.year.toString(),
      _ => '',
    };
  }

  Future<void> _pickDate(BuildContext context, AdminController ctrl, String mode) async {
    final now = DateTime.now();

    // Configures calendar directly to year mode if tracking years
    final initialView = mode == 'year' ? DatePickerMode.year : DatePickerMode.day;

    final picked = await showDatePicker(
      context: context,
      initialDate: ctrl.filterDate.value ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDatePickerMode: initialView,
      helpText: mode == 'day'
          ? 'দিন বেছে নিন'
          : mode == 'month'
              ? 'মাস বেছে নিন'
              : 'বছর বেছে নিন',
    );
    if (picked != null) ctrl.setFilter(mode, date: picked);
  }

  Future<void> _downloadPdf(List<dynamic> reports) async {
    try {
      final theme = await PdfHelper.bengaliTheme();
      final doc = pw.Document(theme: theme);
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Text('ASHA Mitra — Admin Reports', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.Text('Total: ${reports.length}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.Divider(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'ASHA', 'Case', 'Band', 'Facility'],
              data: reports.map((item) {
                // Defensive runtime mapping checking types dynamically
                final Map<String, dynamic> r = item is Map ? Map<String, dynamic>.from(item) : item.toMap();
                return [
                  _fmtDate(r['createdAt']?.toString() ?? ''),
                  r['ashaName']?.toString() ?? '',
                  r['caseLabel']?.toString() ?? '',
                  r['finalBand']?.toString() ?? '',
                  r['facilityType']?.toString() ?? '',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo100),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
      await PdfHelper.saveAndOpen(doc, 'admin_reports_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      Get.snackbar('Error', 'Could not generate PDF: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('dd/MM/yy HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: AppRadius.pillR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillR,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: AppRadius.pillR,
            border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
          ),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Summary chip ──────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.smR,
      ),
      child: Text(
        label,
        style: AppTextStyles.overline.copyWith(color: color),
      ),
    );
  }
}

// ── Report card ───────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final dynamic r; // Typed safely at fallback values below
  const _ReportCard({required this.r});

  Color get _bandColor {
    final String band = (r is Map ? r['finalBand'] : r.finalBand)?.toString().toUpperCase() ?? '';
    if (band == 'RED') return AppColors.emergencyRed;
    if (band == 'YELLOW') return AppColors.warningYellow;
    if (band == 'GREEN') return AppColors.safeGreen;
    return AppColors.safeGreen;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> data = r is Map ? Map<String, dynamic>.from(r) : r.toMap();

    final color = _bandColor;
    final band = data['finalBand']?.toString().toUpperCase() ?? '-';
    final bandChar = band.isNotEmpty ? band[0] : '?';
    final date = data['createdAt']?.toString() ?? '';
    String fmtDate = date;
    try {
      fmtDate = DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(date));
    } catch (_) {}

    final caseLabel = data['caseLabel']?.toString() ?? '';
    final ashaName = data['ashaName']?.toString() ?? '';
    final patientName = data['patientName']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: AppShadows.low,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(
              child: Text(
                bandChar,
                style: AppTextStyles.label.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caseLabel.isNotEmpty)
                  Text(
                    caseLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label,
                  ),
                const SizedBox(height: 2),
                if (ashaName.isNotEmpty)
                  Text(
                    'ASHA: $ashaName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                if (patientName.isNotEmpty)
                  Text(
                    '${'admin_patient'.tr}: $patientName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                Text(fmtDate, style: AppTextStyles.caption.copyWith(color: AppColors.textLight)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smR,
            ),
            child: Text(
              band,
              style: AppTextStyles.overline.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
