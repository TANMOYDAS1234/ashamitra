import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';

/// Single shimmering rounded-rect placeholder. Use for tiny pieces inside a
/// composed skeleton card (a name line, a chip, a circle avatar, etc.).
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 6,
    this.circle = false,
  });

  const SkeletonBox.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        circle = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps a subtree in the shimmer effect. Compose `SkeletonBox` widgets inside.
/// Don't wrap actual content in this — it ignores child colors.
class SkeletonShimmer extends StatelessWidget {
  final Widget child;
  const SkeletonShimmer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF3F4F6),
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// A list-row skeleton matching the shape of `PatientCard`: avatar + 3 text
/// lines + a trailing chip. Used in PatientList loading state.
class SkeletonPatientCard extends StatelessWidget {
  const SkeletonPatientCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.low,
      ),
      child: const SkeletonShimmer(
        child: Row(
          children: [
            SkeletonBox.circle(size: 48),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 15),
                  SizedBox(height: 8),
                  SkeletonBox(width: 200, height: 12),
                  SizedBox(height: 6),
                  SkeletonBox(width: 80, height: 11),
                ],
              ),
            ),
            SizedBox(width: 8),
            SkeletonBox(width: 72, height: 22, radius: 999),
          ],
        ),
      ),
    );
  }
}

/// A small card skeleton matching the shape of `_StatCard` on the Reports
/// screen: icon + big number + small label.
class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgR,
          boxShadow: AppShadows.low,
        ),
        child: const SkeletonShimmer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonBox.circle(size: 32),
              SizedBox(height: 8),
              SkeletonBox(width: 28, height: 18),
              SizedBox(height: 4),
              SkeletonBox(width: 44, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Report-card-shaped skeleton: a row with circular icon, 3 text lines, and
/// a small chip on the right.
class SkeletonReportCard extends StatelessWidget {
  const SkeletonReportCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.low,
      ),
      child: const SkeletonShimmer(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox.circle(size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 120, height: 14),
                  SizedBox(height: 6),
                  SkeletonBox(width: 90, height: 11),
                  SizedBox(height: 4),
                  SkeletonBox(width: 70, height: 10),
                ],
              ),
            ),
            SizedBox(width: 8),
            SkeletonBox(width: 62, height: 22, radius: 999),
          ],
        ),
      ),
    );
  }
}

/// Convenience: a list of skeleton items. Pass `builder` to render any
/// custom skeleton shape repeatedly.
class SkeletonList extends StatelessWidget {
  final int count;
  final WidgetBuilder builder;
  final EdgeInsetsGeometry padding;

  const SkeletonList({
    super.key,
    required this.count,
    required this.builder,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: count,
      itemBuilder: (ctx, _) => builder(ctx),
    );
  }
}
