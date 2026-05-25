import 'package:get/get.dart';
import '../data/models/patient_model.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/risk_badge.dart';

class PatientController extends GetxController {
  final isLoading = false.obs;
  final patients  = <PatientModel>[].obs;
  final reports   = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load();
    syncFromServer(); // always fetch fresh data from server on init
  }

  void _load() {
    final raw = LocalStorageService.loadPatients();
    patients.value = raw.map(PatientModel.fromJson).toList();
    reports.value  = LocalStorageService.loadReports()
        .map((r) => _sanitizeReport(r))
        .toList();
  }

  void reloadFromStorage() => _load();

  /// Primary data load from Atlas. Falls back to local if offline.
  ///
  /// Retries each call up to 2 times on transient failure (Render free-tier
  /// cold-start can take 30+ seconds on first request after sleep). An empty
  /// server response is treated as a valid empty state, NOT a sync failure —
  /// so deleted records on the server correctly disappear locally.
  Future<void> syncFromServer() async {
    isLoading.value = true;
    try {
      // ── Patients ─────────────────────────────────────────────────────────
      final remotePatients = await _withRetry(() => ApiService.getPatients());
      final list = remotePatients
          .map((e) => PatientModel.fromJson(e as Map<String, dynamic>))
          .toList();
      patients.value = list;
      await LocalStorageService.savePatients(list.map((p) => p.toJson()).toList());

      // ── Reports ──────────────────────────────────────────────────────────
      // Push any report that never reached the server, THEN pull the
      // authoritative server list. A report whose upload failed (offline /
      // server cold-start / error) would otherwise stay local-only forever
      // and be invisible to the admin panel, which reads only from the server.
      for (final r in reports.where(_isPendingReport).toList()) {
        await _uploadReport(r);
      }
      final remote = await _withRetry(() => ApiService.getReports());
      final remoteReports = remote
          .map((e) => _sanitizeReport(_remoteToLocal(e as Map<String, dynamic>)))
          .toList();
      // Keep only reports that STILL failed to upload (genuinely offline).
      final stillPending = reports.where(_isPendingReport).toList();
      final merged = [...remoteReports, ...stillPending]
        ..sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime(0);
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime(0);
          return db.compareTo(da);
        });
      reports.value = merged;
      LocalStorageService.saveReports(merged);
    } on UnauthorizedException {
      // Token invalid — handled by AuthController via _handleUnauth elsewhere
    } catch (e) {
      // Offline / Render cold-start exhausted — keep local data, log for debug
      // ignore: avoid_print
      print('[Sync] failed after retries: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Retries an async call up to 2 times with backoff. Re-throws after
  /// exhausting attempts so the caller can distinguish a real failure from
  /// an empty result. UnauthorizedException is never retried (token is bad).
  static Future<T> _withRetry<T>(Future<T> Function() fn) async {
    Object? lastErr;
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        return await fn();
      } on UnauthorizedException {
        rethrow;
      } catch (e) {
        lastErr = e;
        if (attempt == 0) await Future.delayed(const Duration(seconds: 3));
      }
    }
    throw lastErr ?? Exception('Retry exhausted');
  }

  /// Map MongoDB report fields → local report map shape.
  Map<String, dynamic> _remoteToLocal(Map<String, dynamic> r) => {
    'id':                  r['_id']?.toString() ?? r['sessionId'] ?? '',
    'sessionId':           r['sessionId'] ?? '',
    'caseType':            r['caseType'] ?? '',
    'caseLabel':           r['caseLabel'] ?? _caseLabel(r['caseType']?.toString() ?? ''),
    'outcome':             _bandToOutcome(r['finalBand']?.toString()),
    'finalBand':           r['finalBand'] ?? 'UNKNOWN',
    'reason':              r['reason'] ?? '',
    'nextStep':            r['nextStep'] ?? '',
    'situation':           r['situation'] ?? '',
    'qaHistory':           r['qaHistory'] ?? [],
    'patientId':           r['patientId'] ?? '',
    'patientName':         r['patientName'] ?? '',
    'triggeredRules':      r['triggeredRules'] ?? [],
    'riskScore':           r['riskScore'] ?? 0,
    'riskLevel':           r['riskLevel'] ?? '',
    'dangerSigns':         r['dangerSigns'] ?? [],
    'suspectedConditions': r['suspectedConditions'] ?? [],
    'facilityType':        r['facilityType'] ?? '',
    'recheckAfterHours':   r['recheckAfterHours'] ?? 0,
    'transportAction':     '',
    'createdAt':           r['createdAt'] ?? DateTime.now().toIso8601String(),
    'synced':              true,
  };

  String _bandToOutcome(String? band) => switch (band?.toUpperCase()) {
    'RED'    => 'emergency',
    'YELLOW' => 'attention',
    _        => 'safe',
  };

  Future<void> _save() async {
    await LocalStorageService.savePatients(
      patients.map((p) => p.toJson()).toList(),
    );
  }

  /// Sanitizes a report loaded from SharedPreferences.
  /// JSON deserialization returns List<dynamic> and num — normalize all types.
  Map<String, dynamic> _sanitizeReport(Map<String, dynamic> r) => {
    ...r,
    'riskScore':        _toInt(r['riskScore']),
    'recheckAfterHours': _toInt(r['recheckAfterHours']),
    'dangerSigns':      _toStringList(r['dangerSigns']),
    'suspectedConditions': _toStringList(r['suspectedConditions']),
    'triggeredRules':   _toStringList(r['triggeredRules']),
    'qaHistory':        _toQaList(r['qaHistory']),
    'outcome':          r['outcome']?.toString() ?? 'safe',
    'finalBand':        r['finalBand']?.toString() ?? '',
    'caseLabel':        r['caseLabel']?.toString() ?? '',
    'patientName':      r['patientName']?.toString() ?? '',
    'facilityType':     r['facilityType']?.toString() ?? '',
    'reason':           r['reason']?.toString() ?? '',
    'nextStep':         r['nextStep']?.toString() ?? '',
    'createdAt':        r['createdAt']?.toString() ?? '',
  };

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static List<String> _toStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  static List<Map<String, String>> _toQaList(dynamic v) {
    if (v == null) return [];
    if (v is List) {
      return v.map((e) {
        if (e is Map) {
          return e.map((k, val) => MapEntry(k.toString(), val.toString()));
        }
        return <String, String>{};
      }).where((m) => m.isNotEmpty).toList();
    }
    return [];
  }

  PatientModel addPatient({
    required String name,
    required String type,
    required String village,
    required String mobile,
    String age = "",
    String gender = "",
    String? situation,
    String? outcome,
    String? reason,
    String? nextStep,
    List<Map<String, String>> qaHistory = const [],
  }) {
    final patient = PatientModel(
      id:        'p_${DateTime.now().millisecondsSinceEpoch}',
      name:      name,
      type:      type,
      village:   village,
      mobile:    mobile,
      age:       age,
      gender:    gender,
      lastVisit: 'এইমাত্র',
      risk:      _riskFromOutcome(outcome),
      situation: situation,
      outcome:   outcome,
      reason:    reason,
      nextStep:  nextStep,
      qaHistory: qaHistory,
    );
    patients.insert(0, patient);
    _save();
    // Sync to backend — exclude local id field
    final data = patient.toJson()..remove('id');
    ApiService.savePatient(data).catchError((_) => false);
    return patient;
  }

  /// Auto-called from TriageResultScreen — saves full DecisionOutput to reports.
  void saveReport({
    required String caseType,
    required String outcome,
    required String reason,
    required String nextStep,
    required String situation,
    required List<Map<String, String>> qaHistory,
    String? patientId,
    String? patientName,
    String finalBand                 = '',
    List<String> triggeredRules      = const [],
    int riskScore                    = 0,
    String riskLevel                 = '',
    List<String> dangerSigns         = const [],
    List<String> suspectedConditions = const [],
    String facilityType              = '',
    int recheckAfterHours            = 0,
    String transportAction           = '',
  }) {
    final report = <String, dynamic>{
      'id':                  'report_${DateTime.now().millisecondsSinceEpoch}',
      'caseType':            caseType,
      'caseLabel':           _caseLabel(caseType),
      'outcome':             outcome,
      'finalBand':           finalBand.isNotEmpty ? finalBand : outcome.toUpperCase(),
      'reason':              reason,
      'nextStep':            nextStep,
      'situation':           situation,
      'qaHistory':           qaHistory,
      'patientId':           patientId ?? '',
      'patientName':         patientName ?? '',
      'triggeredRules':      triggeredRules,
      'riskScore':           riskScore,
      'riskLevel':           riskLevel,
      'dangerSigns':         dangerSigns,
      'suspectedConditions': suspectedConditions,
      'facilityType':        facilityType,
      'recheckAfterHours':   recheckAfterHours,
      'transportAction':     transportAction,
      'createdAt':           DateTime.now().toIso8601String(),
      'synced':              false,
    };
    reports.insert(0, report);
    LocalStorageService.saveReports(reports.toList());
    _uploadReport(report);
  }

  /// Uploads one local report to the backend. On success marks it 'synced'
  /// so [syncFromServer] does not upload it again. On failure it stays
  /// pending and is retried on the next sync.
  Future<void> _uploadReport(Map<String, dynamic> report) async {
    final data = Map<String, dynamic>.from(report)
      ..remove('id')
      ..remove('synced');
    final ok = await ApiService.saveReport(data);
    if (!ok) return;
    final idx = reports.indexWhere((r) => r['id'] == report['id']);
    if (idx != -1) {
      reports[idx] = {...reports[idx], 'synced': true};
      LocalStorageService.saveReports(reports.toList());
    }
  }

  /// Called from "ফলো-আপ" button — adds to patient list.
  void saveTriageResult({
    required String caseType,
    required String outcome,
    required String reason,
    required String nextStep,
    required String situation,
    required List<Map<String, String>> qaHistory,
  }) {
    final caseLabel = _caseLabel(caseType);
    final patient = PatientModel(
      id:        'triage_${DateTime.now().millisecondsSinceEpoch}',
      name:      'রোগী — $caseLabel',
      type:      caseLabel,
      village:   '—',
      mobile:    '',
      lastVisit: _todayLabel(),
      risk:      _riskFromOutcome(outcome),
      situation: situation,
      outcome:   outcome,
      reason:    reason,
      nextStep:  nextStep,
      qaHistory: qaHistory,
    );
    patients.insert(0, patient);
    _save();
    // Sync to backend — exclude local id field
    final data = patient.toJson()..remove('id');
    ApiService.savePatient(data).catchError((_) => false);
  }

  /// Attaches a fresh triage result to an existing patient (a follow-up
  /// checkup) instead of creating a duplicate entry in the list.
  /// Returns true if a patient with [patientId] was found and updated.
  bool applyFollowUp({
    required String patientId,
    required String outcome,
    required String reason,
    required String nextStep,
    required String situation,
    required List<Map<String, String>> qaHistory,
  }) {
    final idx = patients.indexWhere((p) => p.id == patientId);
    if (idx == -1) return false;
    final updated = patients[idx].copyWith(
      lastVisit: _todayLabel(),
      risk: _riskFromOutcome(outcome),
      outcome: outcome,
      reason: reason,
      nextStep: nextStep,
      situation: situation,
      qaHistory: qaHistory,
    );
    patients.removeAt(idx);
    patients.insert(0, updated);
    _save();
    // Best-effort backend sync. Only patients already synced from the server
    // have a real Mongo _id — update those in place via PUT. Patients that
    // exist only locally (id 'p_…' / 'triage_…') are skipped so no duplicate
    // document is created; their data still reaches the server via saveReport.
    if (_isServerId(patientId)) {
      final data = updated.toJson()..remove('id');
      ApiService.updatePatient(patientId, data).catchError((_) => false);
    }
    return true;
  }

  void updatePatient(PatientModel updated) {
    final idx = patients.indexWhere((p) => p.id == updated.id);
    if (idx != -1) { patients[idx] = updated; _save(); }
  }

  void deletePatient(String id) {
    patients.removeWhere((p) => p.id == id);
    _save();
  }

  /// Maps a triage outcome to a risk band. A patient with no triage yet
  /// (manually added, no checkup) defaults to `safe` — not `moderate`. Moderate
  /// is reserved for cases the engine actually classified between safe and high.
  RiskLevel _riskFromOutcome(String? outcome) => switch (outcome) {
    'emergency' => RiskLevel.emergency,
    'attention' => RiskLevel.high,
    'safe'      => RiskLevel.safe,
    null        => RiskLevel.safe,
    ''          => RiskLevel.safe,
    _           => RiskLevel.safe,
  };

  String _caseLabel(String caseType) => switch (caseType) {
    'pregnancy'    => 'গর্ভবতী মায়ের চেকআপ',
    'postpartum'   => 'প্রসব-পরবর্তী',
    'newborn'      => 'নবজাতক',
    'infant'       => 'শিশু (১-১২ মাস)',
    'child'        => 'শিশু স্বাস্থ্য',
    'immunization' => 'টিকাকরণ',
    'emergency'    => 'জরুরি অবস্থা',
    _              => 'সাধারণ চেকআপ',
  };

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day}/${now.month}/${now.year}';
  }

  // A real MongoDB ObjectId is 24 hex chars. Locally-created patients use
  // 'p_…' / 'triage_…' placeholder ids until their first server sync.
  static final _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');
  static bool _isServerId(String id) => _objectIdPattern.hasMatch(id);

  /// A report created locally that has not been confirmed on the server yet —
  /// its id still has the local 'report_' prefix and it is not marked synced.
  static bool _isPendingReport(Map<String, dynamic> r) =>
      r['synced'] != true &&
      (r['id']?.toString() ?? '').startsWith('report_');
}




