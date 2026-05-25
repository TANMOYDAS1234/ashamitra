import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../auth/controller/auth_controller.dart';
import '../../../notifications/controller/notification_controller.dart';
import '../../../notifications/data/notification_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_text_styles.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key});

  void _showNotifications(BuildContext context) {
    final ctrl = Get.find<NotificationController>();
    ctrl.fetchLatest(); // fresh fetch on open
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text('Notifications', style: AppTextStyles.h2),
                    const Spacer(),
                    Obx(() => ctrl.unreadCount.value > 0
                        ? TextButton.icon(
                            onPressed: () => ctrl.markAllRead(),
                            icon: const Icon(Icons.done_all_rounded, size: 16),
                            label: const Text('Mark all read'),
                          )
                        : const SizedBox.shrink()),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Obx(() {
                    if (ctrl.isLoading.value && ctrl.items.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                    }
                    if (ctrl.items.isEmpty) {
                      return _EmptyNotifications(onRefresh: ctrl.fetchLatest);
                    }
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: ctrl.fetchLatest,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: ctrl.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _NotificationTile(
                          n: ctrl.items[i],
                          onTap: () => ctrl.markRead(ctrl.items[i].id),
                          onDismiss: () => ctrl.dismiss(ctrl.items[i].id),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Obx(() => Text(
                      'greeting'.trParams({'name': auth.user.value?.name ?? 'Didi'}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h1,
                    )),
                const SizedBox(height: 2),
                Text('todays_tasks'.tr, style: AppTextStyles.bodySm),
              ],
            ),
          ),
          _NotificationBell(onTap: () => _showNotifications(context)),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final VoidCallback onTap;
  const _NotificationBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<NotificationController>();
    return Material(
      shape: const CircleBorder(),
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Ink(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                boxShadow: AppShadows.tinted(AppColors.primary, strength: 1),
              ),
              child: const Icon(Icons.notifications_rounded, color: AppColors.primary, size: 22),
            ),
            // Real unread badge — only renders when count > 0
            Obx(() {
              final count = ctrl.unreadCount.value;
              if (count == 0) return const SizedBox.shrink();
              return Positioned(
                top: -2,
                right: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.emergencyRed,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Visual treatment for a single notification — colour/icon driven by `type`.
class _NotificationTile extends StatelessWidget {
  final NotificationModel n;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _NotificationTile({required this.n, required this.onTap, required this.onDismiss});

  (IconData, Color) _styleForType() {
    switch (n.type) {
      case 'red_band':
        return (Icons.emergency_rounded, AppColors.emergencyRed);
      case 'yellow_band':
        return (Icons.warning_amber_rounded, AppColors.warningYellow);
      case 'welcome':
        return (Icons.waving_hand_rounded, AppColors.accent);
      case 'follow_up':
        return (Icons.schedule_rounded, AppColors.warningYellow);
      case 'sync':
        return (Icons.cloud_done_rounded, AppColors.safeGreen);
      default:
        return (Icons.notifications_rounded, AppColors.primary);
    }
  }

  String _relativeTime() {
    final diff = DateTime.now().difference(n.createdAt);
    if (diff.inMinutes < 1) return 'এখন';
    if (diff.inMinutes < 60) return '${diff.inMinutes} মিনিট আগে';
    if (diff.inHours   < 24) return '${diff.inHours} ঘণ্টা আগে';
    if (diff.inDays    < 7)  return '${diff.inDays} দিন আগে';
    return '${diff.inDays ~/ 7} সপ্তাহ আগে';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _styleForType();
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: AppColors.emergencyRed,
          borderRadius: AppRadius.lgR,
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: n.read ? AppColors.surface : AppColors.primarySoft,
        borderRadius: AppRadius.lgR,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lgR,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(n.title, style: AppTextStyles.labelLg)),
                          if (!n.read) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(n.body, style: AppTextStyles.bodySm),
                      ],
                      const SizedBox(height: 4),
                      Text(_relativeTime(), style: AppTextStyles.caption.copyWith(color: AppColors.textLight)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyNotifications({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_off_rounded,
                size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text('কোনো নোটিফিকেশন নেই', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text(
            'জরুরি কেস তৈরি হলে এখানে দেখাবে',
            style: AppTextStyles.bodySm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
