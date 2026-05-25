import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text_styles.dart';
import 'risk_badge.dart';

class PatientCard extends StatelessWidget {
  final String name;
  final String caseType;
  final String village;
  final String lastVisit;
  final RiskLevel riskLevel;
  final VoidCallback? onTap;
  final VoidCallback? onCallTap;

  /// Tag for the Hero animation between this card's avatar and the patient
  /// profile screen's big gradient avatar. Pass the patient id.
  final String? heroTag;

  const PatientCard({
    super.key,
    required this.name,
    required this.caseType,
    required this.village,
    required this.lastVisit,
    this.riskLevel = RiskLevel.safe,
    this.onTap,
    this.onCallTap,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final avatar = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.10),
      ),
      child: Center(
        child: Text(
          initial,
          style: AppTextStyles.h3.copyWith(color: AppColors.primary),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.tinted(AppColors.primary),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgR,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          borderRadius: AppRadius.lgR,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (heroTag != null)
                  Hero(tag: 'patient_avatar_$heroTag', child: avatar)
                else
                  avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTextStyles.labelLg),
                      const SizedBox(height: 3),
                      Text(
                        '$caseType · $village',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lastVisit,
                        style: AppTextStyles.caption.copyWith(color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
                if (onCallTap != null) ...[
                  const SizedBox(width: 4),
                  Material(
                    color: AppColors.safeGreen.withValues(alpha: 0.12),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onCallTap,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.phone_rounded,
                            size: 18, color: AppColors.safeGreen),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                RiskBadge(level: riskLevel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
