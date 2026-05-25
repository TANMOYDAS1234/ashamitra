import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../features/auth/controller/auth_controller.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../admin/controller/admin_controller.dart';

class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key});
  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = Get.find<AdminController>();
      ctrl.loadStats();
      ctrl.loadReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminController>();
    final auth = Get.find<AuthController>();

    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.background),
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await ctrl.loadStats();
            await ctrl.loadReports();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────
                Row(
                  children: [
                    Obx(() => UserAvatar(
                          user: auth.user.value,
                          size: 44,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          textColor: AppColors.primary,
                        )),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('admin_panel'.tr, style: AppTextStyles.h3),
                          Obx(() => Text(
                                auth.user.value?.name ?? 'Admin',
                                style: AppTextStyles.caption,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Stats grid ───────────────────────────────────
                Obx(() => GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.55,
                      children: [
                        _StatTile('admin_total_asha'.tr, '${ctrl.totalWorkers}',
                            Icons.people_alt_rounded, AppColors.primary),
                        _StatTile('admin_total_patients'.tr, '${ctrl.totalPatients}',
                            Icons.groups_rounded, AppColors.sky),
                        _StatTile('admin_total_reports'.tr, '${ctrl.totalReports}',
                            Icons.analytics_rounded, AppColors.purple),
                        _StatTile('admin_emergency_red'.tr, '${ctrl.redReports}',
                            Icons.gpp_bad_rounded, AppColors.emergencyRed),
                        _StatTile('admin_warning_yellow'.tr, '${ctrl.yellowReports}',
                            Icons.warning_amber_rounded, AppColors.warningYellow),
                        _StatTile('admin_safe_green'.tr, '${ctrl.greenReports}',
                            Icons.check_circle_rounded, AppColors.safeGreen),
                      ],
                    )),
                const SizedBox(height: 28),

                // ── Recent reports ───────────────────────────────
                Text('Recent Reports', style: AppTextStyles.label),
                const SizedBox(height: 12),
                Obx(() {
                  if (ctrl.isLoading.value) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2));
                  }
                  if (ctrl.reports.isEmpty) {
                    return Center(
                      child: Text('admin_no_reports'.tr, style: AppTextStyles.bodySm),
                    );
                  }
                  final recent = ctrl.reports.take(5).toList();
                  return Column(
                    children: recent
                        .map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _RecentReportCard(r: r),
                            ))
                        .toList(),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlR,
        boxShadow: AppShadows.tinted(color),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: AppRadius.smR),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(value,
              style: AppTextStyles.h2.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                height: 1.1,
              )),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecentReportCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _RecentReportCard({required this.r});

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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Center(
              child: Text(band.isNotEmpty ? band[0] : '?',
                  style: AppTextStyles.label.copyWith(color: color)),
            ),
          ),
          const SizedBox(width: 10),
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
              ],
            ),
          ),
          Text(fmtDate, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}
