import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../../app/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared/components/app_header.dart';
import '../../../admin/controller/admin_controller.dart';
import '../../../../features/auth/data/models/user_model.dart';

class AdminAshaListScreen extends StatelessWidget {
  const AdminAshaListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminController>();

    // Always reload fresh data from Atlas when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.loadAshaWorkers());
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: 'admin_asha_list'.tr,
                actions: [
                  HeaderActionCircle(
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: () => Get.toNamed(AppRoutes.adminAddAsha),
                    tooltip: 'Add ASHA',
                  ),
                ],
              ),
              Expanded(
                child: Obx(() {
                  if (ctrl.isLoading.value) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 3));
                  }
                  if (ctrl.ashaWorkers.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline_rounded,
                              size: 64,
                              color: AppColors.textSecondary.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text('admin_no_asha'.tr, style: AppTextStyles.labelLg),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: ctrl.loadAshaWorkers,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: ctrl.ashaWorkers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          _AshaCard(worker: ctrl.ashaWorkers[i], ctrl: ctrl),
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
}

class _AshaCard extends StatelessWidget {
  final UserModel worker;
  final AdminController ctrl;

  const _AshaCard({required this.worker, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final statusColor =
        worker.isActive ? AppColors.safeGreen : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlR,
        boxShadow: AppShadows.low,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.xlR,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(
                    worker.name.isNotEmpty ? worker.name[0].toUpperCase() : 'A',
                    style: AppTextStyles.h3.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(worker.name, style: AppTextStyles.labelLg),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.phone_android_rounded,
                            size: 13,
                            color: AppColors.textSecondary.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(worker.phone, style: AppTextStyles.caption),
                      ]),
                      if (worker.block.isNotEmpty || worker.district.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.location_on_outlined,
                              size: 13,
                              color: AppColors.textSecondary.withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('${worker.block}, ${worker.district}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: AppRadius.smR),
                      child: Text(
                        worker.isActive ? 'admin_active'.tr : 'admin_inactive'.tr,
                        style: AppTextStyles.overline.copyWith(color: statusColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _confirmToggle(context),
                      borderRadius: AppRadius.smR,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                            color: (worker.isActive
                                    ? AppColors.emergencyRed
                                    : AppColors.safeGreen)
                                .withValues(alpha: 0.08),
                            borderRadius: AppRadius.smR),
                        child: Text(
                          worker.isActive ? 'admin_remove'.tr : 'admin_reactivate'.tr,
                          style: AppTextStyles.overline.copyWith(
                            color: worker.isActive
                                ? AppColors.emergencyRed
                                : AppColors.safeGreen,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmToggle(BuildContext context) {
    final bool isRemove = worker.isActive;
    final String titleText =
        isRemove ? 'admin_remove_title'.tr : 'admin_reactivate_title'.tr;
    final String actionText =
        isRemove ? 'admin_remove'.tr : 'admin_reactivate'.tr;
    final Color actionColor =
        isRemove ? AppColors.emergencyRed : AppColors.safeGreen;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xxlR),
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(
                    isRemove
                        ? Icons.person_remove_rounded
                        : Icons.person_add_alt_1_rounded,
                    color: actionColor,
                    size: 32),
              ),
              const SizedBox(height: 20),
              Text(titleText, style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Text(
                'admin_confirm_action'.tr
                    .replaceAll('@name', worker.name)
                    .replaceAll('@action', actionText),
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Get.back(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.lgR,
                            side: const BorderSide(color: Color(0xFFE2E8F0))),
                      ),
                      child: Text('cancel'.tr,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Get.back();
                        if (isRemove) {
                          await ctrl.removeAshaWorker(worker.id);
                        } else {
                          await ctrl.reactivateAshaWorker(worker.id);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: actionColor,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.lgR),
                      ),
                      child: Text(actionText, style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }
}
