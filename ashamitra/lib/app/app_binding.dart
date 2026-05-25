import 'package:get/get.dart';
import '../features/auth/controller/auth_controller.dart';
import '../features/triage/controller/triage_controller.dart';
import '../features/patients/controller/patient_controller.dart';
import '../features/admin/controller/admin_controller.dart';
import '../features/notifications/controller/notification_controller.dart';
import '../core/services/case_detection_service.dart';
import '../core/services/decision_trace_service.dart';
import '../core/services/mdsr_hook_service.dart';
import '../core/services/trace_database.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    // LanguageController registered in main() before App builds
    Get.put(AuthController(), permanent: true);
    Get.put(TriageController(), permanent: true);
    Get.put(PatientController(), permanent: true);
    Get.put(CaseDetectionService(), permanent: true);
    Get.put(TraceDatabase(), permanent: true);
    Get.put(DecisionTraceService(), permanent: true);
    Get.put(MdsrHookService(), permanent: true);
    Get.put(AdminController(), permanent: true);
    Get.put(NotificationController(), permanent: true);
  }
}
