import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../core/services/api_service.dart';
import '../../../app/routes.dart';
import '../../../core/services/local_storage_service.dart';
import '../../auth/data/models/user_model.dart';

class AdminController extends GetxController {
  final isLoading       = false.obs;
  final ashaWorkers     = <UserModel>[].obs;
  final reports         = <Map<String, dynamic>>[].obs;
  final filteredReports = <Map<String, dynamic>>[].obs;
  final errorMsg        = ''.obs;

  final totalWorkers  = 0.obs;
  final totalPatients = 0.obs;
  final totalReports  = 0.obs;
  final redReports    = 0.obs;
  final yellowReports = 0.obs;
  final greenReports  = 0.obs;

  final filterMode = 'all'.obs;
  final filterDate = Rxn<DateTime>();

  // Location filter dimensions — populated from /api/admin/locations.
  final districts          = <String>[].obs;
  final blocks             = <String>[].obs;
  final selectedWorkerId   = Rxn<String>();   // null = all workers
  final selectedDistrict   = Rxn<String>();   // null = all districts
  final selectedBlock      = Rxn<String>();   // null = all blocks

  @override
  void onInit() {
    super.onInit();
    loadStats();
    loadAshaWorkers();
    loadReports();
    loadLocations();
  }

  void _handleUnauth() {
    ApiService.clearToken();
    LocalStorageService.clearUser();
    Get.offAllNamed(AppRoutes.login);
  }

  // ── Stats ──────────────────────────────────────────────────────

  Future<void> loadStats() async {
    try {
      final res = await ApiService.getAdminStats();
      if (res['success'] == true) {
        final d = res['data'] as Map<String, dynamic>;
        totalWorkers.value  = (d['totalWorkers']  as num?)?.toInt() ?? 0;
        totalPatients.value = (d['totalPatients'] as num?)?.toInt() ?? 0;
        totalReports.value  = (d['totalReports']  as num?)?.toInt() ?? 0;
        redReports.value    = (d['redReports']    as num?)?.toInt() ?? 0;
        yellowReports.value = (d['yellowReports'] as num?)?.toInt() ?? 0;
        greenReports.value  = (d['greenReports']  as num?)?.toInt() ?? 0;
      }
    } on UnauthorizedException {
      _handleUnauth();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getWorkerPatients(String workerId) async {
    try {
      final res = await ApiService.getWorkerPatients(workerId);
      if (res['success'] == true)
        return (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on UnauthorizedException { _handleUnauth(); } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getWorkerReports(String workerId) async {
    try {
      final res = await ApiService.getWorkerReports(workerId);
      if (res['success'] == true)
        return (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on UnauthorizedException { _handleUnauth(); } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> getWorkerProfile(String workerId) async {
    try {
      final res = await ApiService.getWorkerProfile(workerId);
      if (res['success'] == true) return res['data'] as Map<String, dynamic>;
    } on UnauthorizedException { _handleUnauth(); } catch (_) {}
    return null;
  }

  // ── ASHA Workers ───────────────────────────────────────────────

  Future<void> loadAshaWorkers() async {
    isLoading.value = true;
    try {
      final res = await ApiService.getWorkers();
      if (res['success'] == true) {
        ashaWorkers.value = (res['data'] as List)
            .map((d) => UserModel.fromJson(d as Map<String, dynamic>))
            .toList();
      } else {
        errorMsg.value = res['message']?.toString() ?? 'ASHA তালিকা লোড ব্যর্থ।';
      }
    } on UnauthorizedException {
      _handleUnauth();
    } catch (_) {
      errorMsg.value = 'সংযোগ ব্যর্থ।';
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> addAshaWorker({
    required String phone,
    required String name,
    required String block,
    required String district,
  }) async {
    try {
      final res = await ApiService.addWorker({
        'phone': phone, 'name': name,
        'block': block, 'district': district,
      });
      if (res['success'] == true) {
        await loadAshaWorkers();
        await loadStats();
        return true;
      }
      errorMsg.value = res['message']?.toString() ?? 'ASHA যোগ করা ব্যর্থ।';
      return false;
    } on UnauthorizedException {
      _handleUnauth();
      return false;
    } catch (_) {
      errorMsg.value = 'সংযোগ ব্যর্থ।';
      return false;
    }
  }

  Future<bool> removeAshaWorker(String id) async {
    try {
      final res = await ApiService.deactivateWorker(id);
      if (res['success'] == true) {
        await loadAshaWorkers();
        await loadStats();
        return true;
      }
      errorMsg.value = res['message']?.toString() ?? 'ASHA সরানো ব্যর্থ।';
      return false;
    } on UnauthorizedException {
      _handleUnauth();
      return false;
    } catch (_) {
      errorMsg.value = 'সংযোগ ব্যর্থ।';
      return false;
    }
  }

  Future<bool> reactivateAshaWorker(String id) async {
    try {
      final res = await ApiService.activateWorker(id);
      if (res['success'] == true) {
        await loadAshaWorkers();
        await loadStats();
        return true;
      }
      errorMsg.value = res['message']?.toString() ?? 'পুনরায় সক্রিয় করা ব্যর্থ।';
      return false;
    } on UnauthorizedException {
      _handleUnauth();
      return false;
    } catch (_) {
      errorMsg.value = 'সংযোগ ব্যর্থ।';
      return false;
    }
  }

  // ── Reports ────────────────────────────────────────────────────

  Future<void> loadReports({String? band, DateTime? date, String? month, String? year}) async {
    isLoading.value = true;
    try {
      final res = await ApiService.getAdminReports(
        band:     band,
        date:     date != null ? DateFormat('yyyy-MM-dd').format(date) : null,
        month:    month,
        year:     year,
        worker:   selectedWorkerId.value,
        district: selectedDistrict.value,
        block:    selectedBlock.value,
      );
      if (res['success'] == true) {
        final list = (res['data'] as List)
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
        reports.value         = list;
        filteredReports.value = list;
      } else {
        errorMsg.value = res['message']?.toString() ?? 'রিপোর্ট লোড ব্যর্থ।';
      }
    } on UnauthorizedException {
      _handleUnauth();
    } catch (_) {
      errorMsg.value = 'সংযোগ ব্যর্থ।';
    } finally {
      isLoading.value = false;
    }
  }

  /// Loads district + block distinct lists for the filter dropdowns.
  Future<void> loadLocations() async {
    try {
      final res = await ApiService.getAdminLocations();
      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>;
        districts.value = ((data['districts'] as List?) ?? []).map((e) => e.toString()).toList();
        blocks.value    = ((data['blocks']    as List?) ?? []).map((e) => e.toString()).toList();
      }
    } on UnauthorizedException {
      _handleUnauth();
    } catch (_) {}
  }

  /// Re-runs the report query with the currently selected band/date AND
  /// the worker/district/block selections. Called by the new filter UI.
  Future<void> applyLocationFilters() async {
    // Re-fire the current band/date filter — keeps both filter axes in sync.
    final mode = filterMode.value;
    final date = filterDate.value;
    switch (mode) {
      case 'red':    return loadReports(band: 'RED');
      case 'yellow': return loadReports(band: 'YELLOW');
      case 'green':  return loadReports(band: 'GREEN');
      case 'day':    if (date != null) return loadReports(date: date); break;
      case 'month':  if (date != null) return loadReports(month: DateFormat('yyyy-MM').format(date)); break;
      case 'year':   if (date != null) return loadReports(year: date.year.toString()); break;
    }
    return loadReports();
  }

  void clearLocationFilters() {
    selectedWorkerId.value = null;
    selectedDistrict.value = null;
    selectedBlock.value    = null;
    applyLocationFilters();
  }

  void setFilter(String mode, {DateTime? date}) {
    filterMode.value = mode;
    filterDate.value = date;
    switch (mode) {
      case 'all':
        loadReports();
      case 'red':
        loadReports(band: 'RED');
      case 'yellow':
        loadReports(band: 'YELLOW');
      case 'green':
        loadReports(band: 'GREEN');
      case 'day':
        if (date != null) loadReports(date: date);
      case 'month':
        if (date != null)
          loadReports(month: DateFormat('yyyy-MM').format(date));
      case 'year':
        if (date != null)
          loadReports(year: date.year.toString());
    }
  }
}
