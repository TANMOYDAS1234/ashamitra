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
import '../../../admin/controller/admin_controller.dart';
import 'admin_report_detail.dart';

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => Get.find<AdminController>().loadReports());
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminController>();

    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.background),
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Reports', style: AppTextStyles.h2),
                  ),
                  Obx(() {
                    final activeCount = [
                      ctrl.selectedWorkerId.value,
                      ctrl.selectedDistrict.value,
                      ctrl.selectedBlock.value,
                    ].where((e) => e != null).length;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          onPressed: () => _openFilterSheet(context, ctrl),
                          style: IconButton.styleFrom(
                            backgroundColor: activeCount > 0
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.grey.shade100,
                            padding: const EdgeInsets.all(10),
                          ),
                          icon: const Icon(Icons.filter_alt_rounded,
                              color: AppColors.primary, size: 20),
                          tooltip: 'Filter by worker / location',
                        ),
                        if (activeCount > 0)
                          Positioned(
                            top: 4, right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                              child: Text(
                                '$activeCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(width: 8),
                  Obx(() => IconButton(
                        onPressed: ctrl.filteredReports.isEmpty
                            ? null
                            : () => _downloadPdf(ctrl.filteredReports.toList()),
                        style: IconButton.styleFrom(
                          backgroundColor: ctrl.filteredReports.isEmpty
                              ? Colors.grey.shade200
                              : AppColors.primary,
                          padding: const EdgeInsets.all(10),
                        ),
                        icon: Icon(Icons.download_rounded,
                            color: ctrl.filteredReports.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.onPrimary,
                            size: 20),
                        tooltip: 'Download PDF',
                      )),
                ],
              ),
            ),

            // ── Filter chips ─────────────────────────────────────
            Obx(() => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      _FilterChip(
                          label: 'admin_filter_all'.tr,
                          selected: ctrl.filterMode.value == 'all',
                          onTap: () => ctrl.setFilter('all')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '🔴 Red',
                          selected: ctrl.filterMode.value == 'red',
                          color: AppColors.emergencyRed,
                          onTap: () => ctrl.setFilter('red')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '🟡 Yellow',
                          selected: ctrl.filterMode.value == 'yellow',
                          color: AppColors.warningYellow,
                          onTap: () => ctrl.setFilter('yellow')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '🟢 Green',
                          selected: ctrl.filterMode.value == 'green',
                          color: AppColors.safeGreen,
                          onTap: () => ctrl.setFilter('green')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '📅 Day',
                          selected: ctrl.filterMode.value == 'day',
                          onTap: () => _pickDate(context, ctrl, 'day')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '📆 Month',
                          selected: ctrl.filterMode.value == 'month',
                          onTap: () => _pickDate(context, ctrl, 'month')),
                      const SizedBox(width: 8),
                      _FilterChip(
                          label: '🗓 Year',
                          selected: ctrl.filterMode.value == 'year',
                          onTap: () => _pickDate(context, ctrl, 'year')),
                    ],
                  ),
                )),

            // ── Summary row ──────────────────────────────────────
            Obx(() => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Row(
                    children: [
                      _SummaryChip('Total ${ctrl.totalReports}',
                          AppColors.primary),
                      const SizedBox(width: 8),
                      _SummaryChip('🔴 ${ctrl.redReports}',
                          AppColors.emergencyRed),
                      const SizedBox(width: 8),
                      _SummaryChip('🟡 ${ctrl.yellowReports}',
                          AppColors.warningYellow),
                      const SizedBox(width: 8),
                      _SummaryChip('🟢 ${ctrl.greenReports}',
                          AppColors.safeGreen),
                    ],
                  ),
                )),

            // ── Report list ──────────────────────────────────────
            Expanded(
              child: Obx(() {
                if (ctrl.isLoading.value) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 3));
                }
                if (ctrl.filteredReports.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart_outlined,
                            size: 64,
                            color: AppColors.textSecondary
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('admin_no_reports'.tr, style: AppTextStyles.bodySm),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: ctrl.loadReports,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: ctrl.filteredReports.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = ctrl.filteredReports[i];
                      return _ReportCard(
                        r: r,
                        onTap: () => showAdminReportDetail(context, r),
                      );
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, AdminController ctrl, String mode) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: ctrl.filterDate.value ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode:
          mode == 'year' ? DatePickerMode.year : DatePickerMode.day,
      helpText: mode == 'day'
          ? 'Select Day'
          : mode == 'month'
              ? 'Select Month'
              : 'Select Year',
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
            pw.Text('ASHA Mitra — Admin Reports',
                style: pw.TextStyle(
                    fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
                'Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600)),
            pw.Text('Total: ${reports.length}',
                style: const pw.TextStyle(
                    fontSize: 11, color: PdfColors.grey700)),
            pw.Divider(height: 20),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Patient', 'Case', 'Band', 'Facility'],
              data: reports.map((item) {
                final Map<String, dynamic> r = item is Map
                    ? Map<String, dynamic>.from(item)
                    : {};
                return [
                  _fmtDate(r['createdAt']?.toString() ?? ''),
                  r['patientName']?.toString() ?? '',
                  r['caseLabel']?.toString() ?? '',
                  r['finalBand']?.toString() ?? '',
                  r['facilityType']?.toString() ?? '',
                ];
              }).toList(),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.indigo100),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
      await PdfHelper.saveAndOpen(
          doc,
          'admin_reports_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      Get.snackbar('Error', 'Could not generate PDF: $e',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  String _fmtDate(String iso) {
    try {
      return DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  void _openFilterSheet(BuildContext context, AdminController ctrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Obx(() {
            final workers = ctrl.ashaWorkers;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Filter reports', style: AppTextStyles.h2)),
                      if (ctrl.selectedWorkerId.value != null ||
                          ctrl.selectedDistrict.value != null ||
                          ctrl.selectedBlock.value   != null)
                        TextButton.icon(
                          onPressed: () { ctrl.clearLocationFilters(); Get.back(); },
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          label: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Worker ─────────────────────────────────────────────
                  Text('ASHA WORKER', style: AppTextStyles.overline),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: ctrl.selectedWorkerId.value,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('সব ASHA — All workers')),
                      for (final w in workers)
                        DropdownMenuItem<String?>(
                          value: w.id,
                          child: Text('${w.name} · ${w.phone}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => ctrl.selectedWorkerId.value = v,
                  ),
                  const SizedBox(height: 16),

                  // ── District ──────────────────────────────────────────
                  Text('DISTRICT', style: AppTextStyles.overline),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: ctrl.selectedDistrict.value,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('সব জেলা — All districts')),
                      for (final d in ctrl.districts)
                        DropdownMenuItem<String?>(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => ctrl.selectedDistrict.value = v,
                  ),
                  const SizedBox(height: 16),

                  // ── Block ─────────────────────────────────────────────
                  Text('BLOCK', style: AppTextStyles.overline),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: ctrl.selectedBlock.value,
                    isExpanded: true,
                    decoration: const InputDecoration(),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('সব ব্লক — All blocks')),
                      for (final b in ctrl.blocks)
                        DropdownMenuItem<String?>(value: b, child: Text(b)),
                    ],
                    onChanged: (v) => ctrl.selectedBlock.value = v,
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () { ctrl.applyLocationFilters(); Get.back(); },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Apply filters'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: selected ? c : AppColors.surface,
      borderRadius: AppRadius.pillR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillR,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c : AppColors.surface,
            borderRadius: AppRadius.pillR,
            border: Border.all(
                color: selected ? c : AppColors.cardBorder),
          ),
          child: Text(label,
              style: AppTextStyles.label.copyWith(
                color: selected ? AppColors.onPrimary : AppColors.textSecondary,
              )),
        ),
      ),
    );
  }
}

// ── Summary chip ───────────────────────────────────────────────────────────────
class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppRadius.smR),
      child: Text(label,
          style: AppTextStyles.overline.copyWith(color: color)),
    );
  }
}

// ── Report card ────────────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> r;
  final VoidCallback onTap;
  const _ReportCard({required this.r, required this.onTap});

  Color get _bandColor {
    final band = r['finalBand']?.toString().toUpperCase() ?? '';
    if (band == 'RED') return AppColors.emergencyRed;
    if (band == 'YELLOW') return AppColors.warningYellow;
    return AppColors.safeGreen;
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor;
    final band = r['finalBand']?.toString().toUpperCase() ?? '-';
    final caseLabel = r['caseLabel']?.toString() ?? '';
    final patientName = r['patientName']?.toString() ?? '';
    String fmtDate = '';
    try {
      fmtDate = DateFormat('dd MMM, HH:mm')
          .format(DateTime.parse(r['createdAt']?.toString() ?? ''));
    } catch (_) {}

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgR,
            border: Border.all(color: color.withValues(alpha: 0.25)),
            boxShadow: AppShadows.low,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    band.isNotEmpty ? band[0] : '?',
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
                      Text(caseLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.label),
                    if (patientName.isNotEmpty)
                      Text(patientName, style: AppTextStyles.caption),
                    if ((r['ashaName']?.toString() ?? '').isNotEmpty)
                      Text('ASHA: ${r['ashaName']}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          )),
                    Text(fmtDate, style: AppTextStyles.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.smR),
                child: Text(band,
                    style: AppTextStyles.overline.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── (report detail moved to admin_report_detail.dart) ───────────────────────
