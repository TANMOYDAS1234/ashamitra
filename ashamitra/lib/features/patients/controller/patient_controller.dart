import 'package:get/get.dart';
import '../data/models/patient_model.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/risk_badge.dart';

class PatientController extends GetxController {
  final isLoading = false.obs;
  final patients  = <PatientModel>[].obs;
  final reports   = <Map<String, dynamic>>[].obs;

  /// Patients the user deleted while offline (or after a failed server delete).
  /// Hidden from UI but retained until the next online sync can confirm the
  /// server-side DELETE. Without this list the deleted row would silently
  /// reappear after every syncFromServer.
  final _pendingDeletes = <PatientModel>[].obs;

  @override
  void onInit() {
    super.onInit();
    _load();
    syncFromServer(); // always fetch fresh data from server on init
  }

  void _load() {
    final raw = LocalStorageService.loadPatients();
    patients.value = raw.map(PatientModel.fromJson).toList();
    _pendingDeletes.value = LocalStorageService.loadPendingDeletes()
        .map(PatientModel.fromJson)
        .toList();
    reports.value  = LocalStorageService.loadReports()
        .map((r) => _sanitizeReport(r))
        .toList();
  }

  void reloadFromStorage() => _load();

  Future<void> _savePendingDeletes() async {
    await LocalStorageService.savePendingDeletes(
      _pendingDeletes.map((p) => p.toJson()).toList(),
    );
  }

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
      // Order matters: flush local pending operations to the server FIRST,
      // then fetch the authoritative server state. Otherwise an offline-
      // queued create would immediately be wiped by the remote fetch.
      await _flushPendingPatientOps();

      final remotePatients = await _withRetry(() => ApiService.getPatients());
      final remoteList = remotePatients
          .map((e) => PatientModel.fromJson(e as Map<String, dynamic>))
          .toList();

      // Build the visible list: server data minus anything still pending
      // delete (server hasn't honored our DELETE yet — typically a transient
      // failure that will resolve next sync), PLUS any still-pending local
      // creates/updates that didn't make it to the server.
      final pendingDeleteIds = _pendingDeletes.map((p) => p.id).toSet();
      final stillUnsyncedLocal = patients
          .where((p) => p.syncState != SyncState.synced)
          .toList();
      final stillUnsyncedIds = stillUnsyncedLocal.map((p) => p.id).toSet();

      final mergedPatients = <PatientModel>[
        // Server rows, excluding ones we're trying to delete AND ones we
        // have a newer-locally version of (the local pending_update has
        // edits the server hasn't accepted yet).
        ...remoteList.where((p) =>
            !pendingDeleteIds.contains(p.id) &&
            !stillUnsyncedIds.contains(p.id)),
        // Locally pending — show them so the user sees their own work.
        ...stillUnsyncedLocal,
      ];

      patients.value = mergedPatients;
      await LocalStorageService.savePatients(
          mergedPatients.map((p) => p.toJson()).toList());

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

  /// Drains the offline sync queue:
  ///   1. Deletes — patients marked pendingDelete (DELETE /patients/:id)
  ///   2. Creates — patients with syncState=pendingCreate (POST /patients)
  ///   3. Updates — patients with syncState=pendingUpdate (PUT /patients/:id)
  /// Anything that still fails stays queued for the next sync cycle. Returns
  /// silently — the outer syncFromServer handles UI state.
  Future<void> _flushPendingPatientOps() async {
    // ── 1. Deletes ──────────────────────────────────────────────────────────
    final stillDeleting = <PatientModel>[];
    for (final p in _pendingDeletes.toList()) {
      if (!_isServerId(p.id)) {
        // Was never on the server (offline create then offline delete).
        // Drop silently — nothing to delete remotely.
        continue;
      }
      final ok = await ApiService.deletePatient(p.id);
      if (!ok) stillDeleting.add(p);
    }
    if (stillDeleting.length != _pendingDeletes.length) {
      _pendingDeletes.value = stillDeleting;
      await _savePendingDeletes();
    }

    // ── 2 & 3. Creates and updates ──────────────────────────────────────────
    for (var i = 0; i < patients.length; i++) {
      final p = patients[i];
      if (p.syncState == SyncState.synced) continue;

      // Both pendingCreate and "pendingUpdate but id is still a placeholder"
      // route through POST. The server's de-dup logic will return the
      // existing doc if the (ashaId, name, mobile) tuple already exists.
      final needsPost = p.syncState == SyncState.pendingCreate ||
          (p.syncState == SyncState.pendingUpdate && !_isServerId(p.id));

      if (needsPost) {
        final data = p.toJson()..remove('id')..remove('syncState');
        final response = await ApiService.savePatient(data);
        if (response == null) continue; // retry next cycle
        final serverId = response['id']?.toString();
        if (serverId == null || serverId.isEmpty) continue;
        final serverVersion = (response['version'] as num?)?.toInt() ?? 0;
        final oldId = p.id;
        patients[i] = p.copyWith(
          id: serverId,
          syncState: SyncState.synced,
          version: serverVersion,
        );
        if (oldId != serverId) _repointReportsPatientId(oldId, serverId);
      } else if (p.syncState == SyncState.pendingUpdate) {
        final data = p.toJson()..remove('id')..remove('syncState');
        final result = await ApiService.updatePatient(p.id, data);
        if (result['status'] == 'success') {
          final serverDoc = result['data'] as Map<String, dynamic>?;
          final newVersion = (serverDoc?['version'] as num?)?.toInt() ?? p.version + 1;
          patients[i] = p.copyWith(syncState: SyncState.synced, version: newVersion);
        } else if (result['status'] == 'conflict') {
          // Another writer beat us. Take server's version + re-apply our edits
          // on top — last write merge, not last write overwrite. The user's
          // changes are preserved unless they conflict on the same fields.
          final serverDoc = result['data'] as Map<String, dynamic>?;
          if (serverDoc != null) {
            final serverPatient = PatientModel.fromJson(serverDoc);
            // Re-apply our local edits on top of the server's current state.
            patients[i] = serverPatient.copyWith(
              lastVisit: p.lastVisit,
              risk: p.risk,
              outcome: p.outcome,
              reason: p.reason,
              nextStep: p.nextStep,
              situation: p.situation,
              qaHistory: p.qaHistory,
              syncState: SyncState.pendingUpdate, // re-queue with new version
            );
          }
        }
        // 'failure' → stays pendingUpdate, retried next sync
      }
    }
  }

  /// When a patient's local placeholder id is swapped for its real Mongo _id,
  /// any reports that referenced the placeholder must be re-pointed too —
  /// otherwise admin views can't join patient ↔ report.
  ///
  /// Two paths:
  ///   1. Locally-cached reports: patched in memory + persisted to storage.
  ///   2. Reports already POSTed to the server: PATCH /reports/repoint flips
  ///      their patientId server-side too, closing the race window where a
  ///      triage was completed before savePatient returned.
  void _repointReportsPatientId(String oldId, String newId) {
    if (oldId == newId) return;

    // 1. Local cache.
    var changed = false;
    for (var i = 0; i < reports.length; i++) {
      if (reports[i]['patientId']?.toString() == oldId) {
        reports[i] = {...reports[i], 'patientId': newId};
        changed = true;
      }
    }
    if (changed) {
      reports.refresh();
      LocalStorageService.saveReports(reports.toList());
    }

    // 2. Server-side repoint — fire and forget. If it fails (offline,
    // cold-start, 5xx) the local sync logic on the next cycle will catch
    // the same placeholder string and retry via the same mechanism that
    // triggered this call. Worst case: admin sees the placeholder string
    // in patientId for one report until the next sync round; the patient
    // still appears by name. Non-blocking.
    ApiService.repointReports(oldId, newId);
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
      syncState: SyncState.pendingCreate,
    );
    patients.insert(0, patient);
    _save();
    // Try to flush this new patient to the server right away. If it succeeds,
    // the placeholder id gets swapped for the real Mongo _id and syncState
    // moves to synced. If it fails (offline, Render cold-start), the patient
    // stays in pendingCreate and the next syncFromServer cycle will retry.
    _syncOnePendingCreate(patient.id);
    return patient;
  }

  /// Tries to POST a single locally-created patient (syncState=pendingCreate)
  /// and, on success, swaps the placeholder id for the server _id + marks
  /// synced. Also re-points any reports that referenced the placeholder.
  /// Best-effort — silent on failure (queued for next syncFromServer).
  Future<void> _syncOnePendingCreate(String placeholderId) async {
    final idx = patients.indexWhere((p) => p.id == placeholderId);
    if (idx == -1) return;
    final p = patients[idx];
    if (p.syncState != SyncState.pendingCreate) return;

    final data = p.toJson()..remove('id')..remove('syncState');
    final response = await ApiService.savePatient(data);
    if (response == null) return; // queued for retry
    final serverId = response['id']?.toString();
    if (serverId == null || serverId.isEmpty) return;

    // The patient may have moved in the list since we started — re-locate by id.
    final currentIdx = patients.indexWhere((q) => q.id == placeholderId);
    if (currentIdx == -1) return; // user deleted in the meantime
    final serverVersion = (response['version'] as num?)?.toInt() ?? 0;
    patients[currentIdx] = p.copyWith(
      id: serverId,
      syncState: SyncState.synced,
      version: serverVersion,
    );
    await _save();

    if (serverId != placeholderId) {
      _repointReportsPatientId(placeholderId, serverId);
    }
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

  /// Attaches an existing (typically anonymous) report to a patient. Used
  /// by the Reports tab's 'Attach Patient' action — a worker can run an
  /// urgent anonymous triage, save it, then later identify the patient
  /// and link the report retroactively.
  ///
  /// Updates both the local cache (so the report row instantly shows the
  /// patient name in the UI) and the server-side report doc (so admin
  /// views and per-patient history also pick up the link).
  ///
  /// Returns true on confirmed server update. On network failure the
  /// local change still persists — the report stays linked locally and
  /// the next sync will probably re-pull the server's old (unlinked)
  /// state. So failure-mode is: server stays out of sync until a future
  /// retry mechanism is added. Documented honestly here.
  Future<bool> attachPatientToReport({
    required String reportId,
    required String patientId,
    required String patientName,
    String? patientType,
  }) async {
    // 1. Update local cache immediately for snappy UI.
    final idx = reports.indexWhere((r) => r['id'] == reportId);
    if (idx != -1) {
      reports[idx] = {
        ...reports[idx],
        'patientId':   patientId,
        'patientName': patientName,
        if (patientType != null) 'caseType': patientType,
      };
      reports.refresh();
      await LocalStorageService.saveReports(reports.toList());
    }

    // 2. Patch the server doc.
    final updated = await ApiService.attachPatientToReport(
      reportId:    reportId,
      patientId:   patientId,
      patientName: patientName,
      patientType: patientType,
    );
    return updated != null;
  }

  /// Soft-deletes a report. Optimistic: removes from the local list
  /// immediately, then asks the server to set deletedAt. If the server
  /// call fails the local copy is restored so the worker isn't lied to.
  /// Returns the removed report map (for undo) or null on failure.
  ///
  /// Locally-pending reports (id starts with `report_`) are deleted
  /// locally only — the server never saw them, so calling DELETE with
  /// that placeholder id used to fail with Mongoose CastError (500),
  /// triggering rollback that made the card reappear and look broken.
  Future<Map<String, dynamic>?> deleteReport(String reportId) async {
    final idx = reports.indexWhere((r) => r['id'] == reportId);
    if (idx == -1) return null;
    final snapshot = Map<String, dynamic>.from(reports[idx]);
    reports.removeAt(idx);
    reports.refresh();
    await LocalStorageService.saveReports(reports.toList());

    // Local-only path: ANY id that isn't a 24-char hex Mongo ObjectId is
    // a local placeholder (report_<ts>, sessionId-style, etc.) and was
    // never actually written to the server. Calling DELETE on those used
    // to fail with Mongoose CastError (500) → rollback → card reappeared.
    final isMongoId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(reportId);
    if (!isMongoId || snapshot['synced'] == false) {
      return snapshot;
    }

    bool ok;
    try {
      ok = await ApiService.deleteReport(reportId);
    } on UnauthorizedException {
      // Token expired — restore locally so the worker sees the report
      // again, then let the auth flow drive them to re-login.
      reports.insert(idx.clamp(0, reports.length), snapshot);
      reports.refresh();
      await LocalStorageService.saveReports(reports.toList());
      rethrow;
    }
    if (!ok) {
      // Roll back — restore at the original index so the UI matches reality.
      reports.insert(idx.clamp(0, reports.length), snapshot);
      reports.refresh();
      await LocalStorageService.saveReports(reports.toList());
      return null;
    }
    return snapshot;
  }

  /// Restores a soft-deleted report. Inserts it back at the top of the
  /// list (sorted-by-recency stays consistent) and clears deletedAt on
  /// the server. Used by the "Undo" snackbar.
  ///
  /// For locally-pending reports the server PATCH is skipped — the
  /// server never knew about them, so just putting the snapshot back
  /// in the local list is the whole restore.
  Future<bool> restoreReport(Map<String, dynamic> snapshot) async {
    final reportId = snapshot['id']?.toString();
    if (reportId == null || reportId.isEmpty) return false;

    // Avoid duplicate insertion if something else (e.g. a sync) already
    // brought it back.
    final exists = reports.any((r) => r['id'] == reportId);
    if (!exists) {
      reports.insert(0, snapshot);
      reports.refresh();
      await LocalStorageService.saveReports(reports.toList());
    }

    final isMongoId = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(reportId);
    if (!isMongoId || snapshot['synced'] == false) {
      return true;
    }

    final ok = await ApiService.restoreReport(reportId);
    if (!ok && !exists) {
      // Server refused — remove the local copy we just added so we don't
      // leave the worker with a phantom report.
      reports.removeWhere((r) => r['id'] == reportId);
      reports.refresh();
      await LocalStorageService.saveReports(reports.toList());
    }
    return ok;
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
      syncState: SyncState.pendingCreate,
    );
    patients.insert(0, patient);
    _save();
    _syncOnePendingCreate(patient.id);
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
    // Mark pendingUpdate optimistically — if the PUT succeeds, we promote to
    // synced; if not, it stays pending and the next syncFromServer retries.
    // Patients with placeholder ids (still in pendingCreate from offline)
    // collapse the pending_update back to pending_create: the next sync will
    // POST the latest state, not the original snapshot.
    final existing = patients[idx];
    final shouldUpsert = !_isServerId(patientId) ||
        existing.syncState == SyncState.pendingCreate;
    final updated = existing.copyWith(
      lastVisit: _todayLabel(),
      risk: _riskFromOutcome(outcome),
      outcome: outcome,
      reason: reason,
      nextStep: nextStep,
      situation: situation,
      qaHistory: qaHistory,
      syncState: shouldUpsert
          ? SyncState.pendingCreate
          : SyncState.pendingUpdate,
    );
    patients.removeAt(idx);
    patients.insert(0, updated);
    _save();

    // Try to flush now — non-blocking. If we have a real server _id, PUT.
    // Otherwise route through POST (the server de-dups by name+mobile, so
    // re-POSTing the same patient with new fields effectively updates).
    if (shouldUpsert) {
      _syncOnePendingCreate(updated.id);
    } else {
      // Optimistic concurrency-aware update. On 409 we stay pendingUpdate
      // and the next syncFromServer cycle will refetch the server's current
      // state and re-apply our edits on top — non-destructive merge.
      ApiService.updatePatient(
        updated.id,
        updated.toJson()..remove('id')..remove('syncState'),
      ).then((result) {
        if (result['status'] != 'success') return; // failure/conflict → stays pending
        final i = patients.indexWhere((p) => p.id == updated.id);
        if (i == -1) return;
        final serverDoc = result['data'] as Map<String, dynamic>?;
        final newVersion = (serverDoc?['version'] as num?)?.toInt() ?? updated.version + 1;
        patients[i] = patients[i].copyWith(
          syncState: SyncState.synced,
          version: newVersion,
        );
        _save();
      });
    }
    return true;
  }

  /// Worker-initiated edit of patient demographic details (name, type, village,
  /// mobile, age, gender). Goes through the same sync queue as everything else:
  ///   - server-id patient (already on backend) → marked pendingUpdate, PUT
  ///     fires immediately with optimistic-concurrency version, on success
  ///     transitions to synced
  ///   - placeholder-id patient (still pendingCreate locally) → stays
  ///     pendingCreate but with the new field values; next flush POSTs the
  ///     latest snapshot
  ///   - 409 (another writer beat us) → next syncFromServer refetches and
  ///     re-applies our edits on top — non-destructive merge
  ///   - 409 (duplicate name+mobile collision with another patient) → returns
  ///     'duplicate' result for the UI to show "patient already exists" toast
  ///
  /// Returns 'success' | 'duplicate' | 'failure' so the calling screen can
  /// give the right feedback.
  Future<String> updatePatient(PatientModel updated) async {
    final idx = patients.indexWhere((p) => p.id == updated.id);
    if (idx == -1) return 'failure';

    final existing = patients[idx];
    final shouldUpsert = !_isServerId(updated.id) ||
        existing.syncState == SyncState.pendingCreate;

    final next = updated.copyWith(
      syncState: shouldUpsert
          ? SyncState.pendingCreate
          : SyncState.pendingUpdate,
      version: updated.version == 0 ? existing.version : updated.version,
    );

    patients[idx] = next;
    await _save();

    // Local-only patient — try to push via the create path (which the server
    // will de-dup or accept). No conflict semantics needed for never-synced rows.
    if (shouldUpsert) {
      _syncOnePendingCreate(next.id);
      return 'success';
    }

    // Server-side update with optimistic concurrency.
    final data = next.toJson()..remove('id')..remove('syncState');
    final result = await ApiService.updatePatient(next.id, data);
    if (result['status'] == 'success') {
      final serverDoc = result['data'] as Map<String, dynamic>?;
      final newVersion = (serverDoc?['version'] as num?)?.toInt() ?? next.version + 1;
      patients[idx] = next.copyWith(syncState: SyncState.synced, version: newVersion);
      await _save();
      return 'success';
    }
    if (result['status'] == 'conflict') {
      final data = result['data'];
      // Two flavors of 409: version mismatch (data is server's current doc) OR
      // unique-index collision (no 'current' doc returned, server returned a
      // friendly DUPLICATE_NAME_MOBILE code). Distinguish by whether data
      // contains an 'id' field that matches our patient.
      if (data is Map<String, dynamic> && data['id']?.toString() == next.id) {
        // Version conflict — re-apply our edits on top of server's current state
        // and stay pendingUpdate so the next sync retries with the right version.
        final serverPatient = PatientModel.fromJson(data);
        patients[idx] = serverPatient.copyWith(
          name: next.name,
          type: next.type,
          village: next.village,
          mobile: next.mobile,
          age: next.age,
          gender: next.gender,
          syncState: SyncState.pendingUpdate,
        );
        await _save();
        return 'success'; // user's intent honored, will sync next round
      }
      // Duplicate name+mobile collision — revert local change and tell the UI.
      patients[idx] = existing;
      await _save();
      return 'duplicate';
    }
    // 'failure' → stays pendingUpdate, next syncFromServer retries.
    return 'success'; // returned success because local change persisted + queued
  }

  /// Removes the patient from the visible list immediately (optimistic).
  /// - Local-only (never synced): dropped completely.
  /// - Pending create that never reached server: dropped completely (no
  ///   server doc to worry about, and the pending_create won't be flushed
  ///   since the patient is no longer in the list).
  /// - Server-side patient: queued for DELETE on the next online cycle.
  ///   If the DELETE call here succeeds immediately, the patient is dropped
  ///   from the pending-delete queue right away. If it fails (offline,
  ///   cold-start timeout, 5xx), the patient stays in the pending-delete
  ///   queue — hidden from UI, retried by every syncFromServer — until the
  ///   server confirms. This prevents the "I deleted it but it came back"
  ///   bug that the old fire-and-forget code had.
  void deletePatient(String id) {
    final idx = patients.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    final removed = patients[idx];
    patients.removeAt(idx);
    _save();

    // Patient that never reached the server (local-only id, or still
    // pending_create that never flushed). Nothing to delete remotely.
    if (!_isServerId(id) || removed.syncState == SyncState.pendingCreate) {
      return;
    }

    // Queue + try immediately. Always queue first so that even if the app
    // is killed mid-flight, the next launch's sync still removes the row.
    _pendingDeletes.add(removed.copyWith(syncState: SyncState.pendingDelete));
    _savePendingDeletes();

    ApiService.deletePatient(id).then((ok) {
      if (!ok) return; // stays queued, retried next sync
      _pendingDeletes.removeWhere((p) => p.id == id);
      _savePendingDeletes();
    });
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




