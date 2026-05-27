import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../features/onboarding/presentation/screens/splash_screen.dart';
import '../features/onboarding/presentation/screens/welcome_screen.dart';
import '../features/onboarding/presentation/screens/language_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/otp_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/triage/presentation/screens/select_case_screen.dart';
import '../features/triage/presentation/screens/case_confirm_screen.dart';
import '../features/triage/presentation/screens/voice_triage_screen.dart';
import '../features/triage/presentation/screens/dynamic_triage_screen.dart';
import '../features/triage/presentation/screens/triage_result_screen.dart';
import '../features/patients/presentation/screens/patient_list_screen.dart';
import '../features/patients/presentation/screens/add_patient_screen.dart';
import '../features/patients/presentation/screens/patient_profile_screen.dart';
import '../features/emergency/presentation/screens/emergency_screen.dart';
import '../features/reports/presentation/screens/reports_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/admin/presentation/screens/admin_shell.dart';
import '../features/admin/presentation/screens/admin_asha_list_screen.dart';
import '../features/admin/presentation/screens/admin_add_asha_screen.dart';
import '../features/admin/presentation/screens/admin_reports_screen.dart';
import '../features/admin/presentation/screens/admin_profile_screen.dart';
import '../features/assistant/presentation/screens/assistant_screen.dart';

/// Route-typed transition vocabulary.
///
/// - `fadeIn`         (180ms) — peer-level swaps (bottom-nav siblings)
/// - `rightToLeftWithFade` (260ms) — forward step in a guided flow
/// - `downToUp`       (320ms) — modal/emergency sheets (gravity feel)
/// - `zoom`           (280ms) — entering the voice/triage flow (mic-centric)
/// - `fade`           (240ms) — splash → next (calm reveal)
class AppRoutes {
  static const splash          = '/';
  static const welcome         = '/welcome';
  static const language        = '/language';
  static const login           = '/login';
  static const otp             = '/otp';
  static const home            = '/home';
  static const selectCase      = '/triage/select';
  static const caseConfirm     = '/triage/confirm';
  static const voiceTriage     = '/triage/voice';
  static const dynamicTriage   = '/triage/dynamic';
  static const triageResult    = '/triage/result';
  static const patientList     = '/patients';
  static const addPatient      = '/patients/add';
  static const patientProfile  = '/patients/profile';
  static const emergency       = '/emergency';
  static const reports         = '/reports';
  static const profile         = '/profile';
  static const assistant       = '/assistant';
  // Admin
  static const adminDashboard  = '/admin';
  static const adminAshaList   = '/admin/asha';
  static const adminAddAsha    = '/admin/asha/add';
  static const adminReports    = '/admin/reports';
  static const adminProfile    = '/admin/profile';

  // ── Duration tokens for transitions ────────────────────────────────────
  static const _fast   = Duration(milliseconds: 180);
  static const _medium = Duration(milliseconds: 260);
  static const _calm   = Duration(milliseconds: 320);

  static final pages = [
    // Splash — calm reveal
    GetPage(
      name: splash,
      page: () => const SplashScreen(),
      transition: Transition.fade,
      transitionDuration: Duration(milliseconds: 240),
      curve: Curves.easeOut,
    ),

    // Onboarding flow — forward step
    GetPage(
      name: language,
      page: () => const LanguageScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
      curve: Curves.easeOutCubic,
    ),
    GetPage(
      name: welcome,
      page: () => const WelcomeScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
      curve: Curves.easeOutCubic,
    ),
    GetPage(
      name: login,
      page: () => const LoginScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
      curve: Curves.easeOutCubic,
    ),
    GetPage(
      name: otp,
      page: () => const OtpScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
      curve: Curves.easeOutCubic,
    ),

    // Bottom-nav peers — instant fade (these swap via offAllNamed)
    GetPage(
      name: home,
      page: () => const HomeScreen(),
      transition: Transition.fadeIn,
      transitionDuration: _fast,
    ),
    GetPage(
      name: patientList,
      page: () => const PatientListScreen(),
      transition: Transition.fadeIn,
      transitionDuration: _fast,
    ),
    GetPage(
      name: reports,
      page: () => const ReportsScreen(),
      transition: Transition.fadeIn,
      transitionDuration: _fast,
    ),
    GetPage(
      name: profile,
      page: () => const ProfileScreen(),
      transition: Transition.fadeIn,
      transitionDuration: _fast,
    ),

    // AI Assistant — Gemini-Live-style voice-first chat. zoom transition
    // reinforces "you are entering a conversation".
    GetPage(
      name: assistant,
      page: () => const AssistantScreen(),
      transition: Transition.zoom,
      transitionDuration: Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ),

    // Triage entry — zoom (mic-centric, "enter the conversation")
    GetPage(
      name: selectCase,
      page: () => const SelectCaseScreen(),
      transition: Transition.zoom,
      transitionDuration: Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ),

    // Triage continuation — forward step
    GetPage(
      name: caseConfirm,
      page: () => const CaseConfirmScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
    ),
    GetPage(
      name: voiceTriage,
      page: () => const VoiceTriageScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
    ),
    GetPage(
      name: dynamicTriage,
      page: () => const DynamicTriageScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
    ),
    GetPage(
      name: triageResult,
      page: () => const TriageResultScreen(),
      transition: Transition.fadeIn,
      transitionDuration: _medium,
    ),

    // Patient detail screens — forward step
    GetPage(
      name: addPatient,
      page: () => const AddPatientScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
    ),
    GetPage(
      name: patientProfile,
      page: () => const PatientProfileScreen(),
      transition: Transition.rightToLeftWithFade,
      transitionDuration: _medium,
      curve: Curves.easeOutCubic,
    ),

    // Emergency — slides up like a sheet (gravity / urgency feel)
    GetPage(
      name: emergency,
      page: () => const EmergencyScreen(),
      transition: Transition.downToUp,
      transitionDuration: _calm,
      curve: Curves.easeOutCubic,
    ),

    // Admin — forward step
    GetPage(name: adminDashboard, page: () => const AdminShell(),
        transition: Transition.fadeIn, transitionDuration: _fast),
    GetPage(name: adminAshaList,  page: () => const AdminAshaListScreen(),
        transition: Transition.rightToLeftWithFade, transitionDuration: _medium),
    GetPage(name: adminAddAsha,   page: () => const AdminAddAshaScreen(),
        transition: Transition.rightToLeftWithFade, transitionDuration: _medium),
    GetPage(name: adminReports,   page: () => const AdminReportsScreen(),
        transition: Transition.rightToLeftWithFade, transitionDuration: _medium),
    GetPage(name: adminProfile,   page: () => const AdminProfileScreen(),
        transition: Transition.rightToLeftWithFade, transitionDuration: _medium),
  ];
}
