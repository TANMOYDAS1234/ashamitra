// Smoke tests for critical UI widgets.
//
// These verify that key shared widgets and design-system tokens render
// without throwing. They do NOT exercise backend logic or navigation.
// To run: `flutter test`
//
// The google_fonts package is set to refuse runtime fetches so tests
// stay offline (any Bengali text will fall back to the platform font).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:asha_mitra/core/theme/app_colors.dart';
import 'package:asha_mitra/core/theme/app_radius.dart';
import 'package:asha_mitra/core/theme/app_shadows.dart';
import 'package:asha_mitra/shared/widgets/risk_badge.dart';
import 'package:asha_mitra/shared/widgets/empty_state.dart';
import 'package:asha_mitra/shared/widgets/skeleton.dart';

void main() {
  setUpAll(() {
    // Allow runtime fetching but the test cache will use local fallback if
    // offline. Setting to true avoids "font not found" exceptions when
    // constructing TextStyles.
    GoogleFonts.config.allowRuntimeFetching = true;
  });

  // Helper to wrap a widget in a MaterialApp with the project's theme.
  Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          useMaterial3: true,
        ),
        home: Scaffold(body: Center(child: child)),
      );

  group('Design tokens', () {
    test('AppRadius tokens have expected values', () {
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 20);
      expect(AppRadius.pill, 999);
    });

    test('AppShadows returns non-empty box-shadow lists', () {
      expect(AppShadows.low, isNotEmpty);
      expect(AppShadows.mid, isNotEmpty);
      expect(AppShadows.high, isNotEmpty);
      expect(AppShadows.tinted(AppColors.primary), isNotEmpty);
    });

    test('Triage band colors are distinct', () {
      expect(AppColors.safeGreen, isNot(AppColors.warningYellow));
      expect(AppColors.warningYellow, isNot(AppColors.emergencyRed));
      expect(AppColors.safeGreen, isNot(AppColors.emergencyRed));
    });
  });

  group('RiskBadge', () {
    for (final level in RiskLevel.values) {
      testWidgets('renders for ${level.name} without errors', (tester) async {
        await tester.pumpWidget(wrap(RiskBadge(level: level)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(RiskBadge), findsOneWidget);
      });
    }

    testWidgets('emergency level renders the label', (tester) async {
      await tester.pumpWidget(wrap(const RiskBadge(level: RiskLevel.emergency)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Emergency'), findsOneWidget);
    });

    testWidgets('safe level renders the label', (tester) async {
      await tester.pumpWidget(wrap(const RiskBadge(level: RiskLevel.safe)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Safe'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders title + subtitle', (tester) async {
      await tester.pumpWidget(wrap(const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No items',
        subtitle: 'Add one to get started',
      )));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No items'), findsOneWidget);
      expect(find.text('Add one to get started'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('renders action when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyState(
        icon: Icons.add,
        title: 'Empty',
        action: FilledButton(
          onPressed: () => tapped = true,
          child: const Text('Add'),
        ),
      )));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Add'));
      expect(tapped, isTrue);
    });
  });

  group('Skeleton widgets', () {
    testWidgets('SkeletonBox renders', (tester) async {
      await tester.pumpWidget(wrap(
        const SkeletonBox(width: 100, height: 20),
      ));
      expect(find.byType(SkeletonBox), findsOneWidget);
    });

    testWidgets('SkeletonPatientCard renders without errors', (tester) async {
      await tester.pumpWidget(wrap(const SkeletonPatientCard()));
      expect(find.byType(SkeletonPatientCard), findsOneWidget);
    });

    testWidgets('SkeletonReportCard renders without errors', (tester) async {
      await tester.pumpWidget(wrap(const SkeletonReportCard()));
      expect(find.byType(SkeletonReportCard), findsOneWidget);
    });
  });
}
