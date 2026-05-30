import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';

class UnauthorizedException implements Exception {}

class _ApiResponse {
  final dynamic data;
  final int statusCode;
  _ApiResponse(this.data, this.statusCode);
}

class ApiService {
  static const baseUrl = 'https://ashamitra-backend.onrender.com/api';

  static String? _token;

  /// Read-only access to the current JWT for services that need to build
  /// custom requests (e.g. NotificationController). Null if not logged in.
  static String? get token => _token;

  static void setToken(String token) {
    _token = token;
    LocalStorageService.set('jwt_token', token);
  }

  static void setTokenInMemory(String token) => _token = token;

  static Future<void> loadToken() async {
    _token = LocalStorageService.get('jwt_token');
  }

  static void clearToken() {
    _token = null;
    LocalStorageService.remove('jwt_token');
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  /// Throws [UnauthorizedException] on 401 — caller forces logout.
  static void _guard(int status) {
    if (status == 401) throw UnauthorizedException();
  }

  // ── Generic instance methods (used by datasources) ─────────────────────────

  Future<_ApiResponse> get(String path) async {
    final res = await http
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _ApiResponse(jsonDecode(res.body), res.statusCode);
  }

  Future<_ApiResponse> post(String path, {Map<String, dynamic>? data}) async {
    final res = await http
        .post(Uri.parse('$baseUrl$path'),
            headers: _headers, body: jsonEncode(data ?? {}))
        .timeout(const Duration(seconds: 15));
    return _ApiResponse(jsonDecode(res.body), res.statusCode);
  }

  Future<_ApiResponse> put(String path, {Map<String, dynamic>? data}) async {
    final res = await http
        .put(Uri.parse('$baseUrl$path'),
            headers: _headers, body: jsonEncode(data ?? {}))
        .timeout(const Duration(seconds: 15));
    return _ApiResponse(jsonDecode(res.body), res.statusCode);
  }

  Future<_ApiResponse> delete(String path) async {
    final res = await http
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return _ApiResponse(jsonDecode(res.body), res.statusCode);
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/send-otp'),
      headers: _headers,
      body: jsonEncode({'phone': phone}),
    ).timeout(const Duration(seconds: 15));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/verify-otp'),
      headers: _headers,
      body: jsonEncode({'phone': phone, 'otp': otp}),
    ).timeout(const Duration(seconds: 15));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$baseUrl/auth/profile'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 30));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Patients ───────────────────────────────────────────────────────────────

  /// Throws on failure so the caller can distinguish "offline / cold-start" from
  /// "user has zero patients". A return value of [] is a real empty state, not
  /// a swallowed error. Uses a 45s timeout to survive Render free-tier cold-start.
  static Future<List<dynamic>> getPatients() async {
    final res = await http
        .get(Uri.parse('$baseUrl/patients'), headers: _headers)
        .timeout(const Duration(seconds: 45));
    _guard(res.statusCode);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['data'] as List? ?? [];
  }

  /// Saves a patient. Returns the server document (with Mongo-assigned `id`)
  /// on success so the caller can replace the local placeholder id with the
  /// real server _id. Returns null on any failure — caller treats the local
  /// row as "not yet synced" and the next syncFromServer will pick it up.
  ///
  /// Server-side dedup: if a patient with the same (ashaId, name, mobile)
  /// already exists, the server returns that existing doc — so the local
  /// row gets re-pointed at the canonical document instead of creating a
  /// stray duplicate.
  static Future<Map<String, dynamic>?> savePatient(Map<String, dynamic> patient) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/patients'),
        headers: _headers,
        body: jsonEncode(patient),
      ).timeout(const Duration(seconds: 45)); // was 15 — Render cold-start can exceed
      _guard(res.statusCode);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      final data = body['data'];
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  /// Result of an optimistic-concurrency PUT. Carries enough info for the
  /// controller to handle a 409 (refetch + merge) without a separate call.
  ///   - status: 'success' | 'conflict' | 'failure'
  ///   - data:   on success → updated doc; on conflict → server's current doc;
  ///             on failure → null
  /// (Plain map instead of a class so it serializes/transports easily.)

  /// Updates an existing patient document in place (PUT /patients/:id).
  /// [id] must be a real server _id — never a local placeholder id.
  /// [patient] should include a `version` field; on mismatch the server
  /// returns 409 and the controller can refetch + merge.
  ///
  /// Returns a map: `{status: 'success'|'conflict'|'failure', data: Map?}`.
  static Future<Map<String, dynamic>> updatePatient(String id, Map<String, dynamic> patient) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/patients/$id'),
        headers: _headers,
        body: jsonEncode(patient),
      ).timeout(const Duration(seconds: 45));
      if (res.statusCode == 401) throw UnauthorizedException();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['success'] == true) {
        return {'status': 'success', 'data': body['data']};
      }
      if (res.statusCode == 409) {
        return {'status': 'conflict', 'data': body['current']};
      }
      return {'status': 'failure', 'data': null};
    } catch (_) {
      return {'status': 'failure', 'data': null};
    }
  }

  /// Permanently deletes a patient (DELETE /patients/:id). [id] must be a
  /// real server _id — caller should skip the network round-trip for
  /// placeholder local-only ids (`p_<ts>` / `triage_<ts>`).
  /// Returns true on confirmed delete, false on any failure (offline,
  /// cold-start timeout, 404, etc).
  static Future<bool> deletePatient(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/patients/$id'),
        headers: _headers,
      ).timeout(const Duration(seconds: 45)); // Render cold-start tolerance
      _guard(res.statusCode);
      if (res.statusCode != 200 && res.statusCode != 204) return false;
      // 200 with body / 204 no-body — both count as success
      if (res.body.isEmpty) return true;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ── Reports ────────────────────────────────────────────────────────────────

  /// Returns the server-created report doc (with the real Mongo `_id` mapped
  /// to `id`) on success, null on failure. Callers should swap the local
  /// placeholder id with `result['id']` so future deletes / patches hit the
  /// correct server record — without this swap, a locally-created report
  /// stays addressable by its `report_<ts>` placeholder forever, and the
  /// soft-delete path silently no-ops (server keeps the row, next sync
  /// brings it back).
  static Future<Map<String, dynamic>?> saveReport(Map<String, dynamic> report) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/reports'),
        headers: _headers,
        body: jsonEncode(report),
      ).timeout(const Duration(seconds: 45));
      _guard(res.statusCode);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      return body['data'] as Map<String, dynamic>?;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('[saveReport] error: $e');
      return null;
    }
  }

  /// PATCH /reports/:id/attach-patient — links an existing (typically
  /// anonymous) report to a patient. Used by the worker's Reports tab so
  /// a quick urgent-triage can be retrospectively tied to the patient
  /// once they're identified or registered.
  /// Returns the updated server doc on success, null on failure.
  static Future<Map<String, dynamic>?> attachPatientToReport({
    required String reportId,
    String? patientId,
    String? patientName,
    String? patientType,
  }) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/reports/$reportId/attach-patient'),
        headers: _headers,
        body: jsonEncode({
          if (patientId   != null) 'patientId':   patientId,
          if (patientName != null) 'patientName': patientName,
          if (patientType != null) 'patientType': patientType,
        }),
      ).timeout(const Duration(seconds: 30));
      _guard(res.statusCode);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      return body['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// PATCH /reports/repoint — updates all reports whose patientId matches
  /// [oldPatientId] to use [newPatientId] instead. Called by the patient
  /// controller immediately after a local placeholder id is swapped for a
  /// server _id, so reports POSTed during the brief race window get
  /// correctly linked to the canonical patient document.
  /// Returns true on success, false on any failure (silent — best effort).
  static Future<bool> repointReports(String oldPatientId, String newPatientId) async {
    if (oldPatientId == newPatientId) return true;
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/reports/repoint'),
        headers: _headers,
        body: jsonEncode({
          'oldPatientId': oldPatientId,
          'newPatientId': newPatientId,
        }),
      ).timeout(const Duration(seconds: 30));
      _guard(res.statusCode);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /chat-with-voice — one round-trip chat + TTS for the triage flow
  /// (2b). Saves the second client→server hop that /api/chat + /api/tts
  /// otherwise requires, which on Render cold-start is the difference
  /// between text-then-voice and text-with-voice landing together.
  ///
  /// Returns the parsed body on success, null on any failure (caller
  /// should fall back to the separate /chat + /tts path).
  ///
  /// Response fields:
  ///   text       — raw LLM output
  ///   provider   — groq | gemini
  ///   cached     — true if served from server AiCache
  ///   audio      — base64 MP3 or null (synthesis-failure is non-fatal)
  ///   audioMime  — "audio/mpeg" when audio is present
  ///   audioTone  — echoes the requested tone
  ///   spokenText — the substring actually spoken (after voiceField pluck)
  static Future<Map<String, dynamic>?> chatWithVoice({
    required String prompt,
    String tone = 'normal',
    String? voiceText,
    String? voiceField,
    bool skipCache = false,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/chat-with-voice'),
        headers: _headers,
        body: jsonEncode({
          'prompt': prompt,
          'tone': tone,
          if (voiceText  != null) 'voiceText':  voiceText,
          if (voiceField != null) 'voiceField': voiceField,
          if (skipCache)          'skipCache':  true,
        }),
      ).timeout(timeout);
      _guard(res.statusCode);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  /// DELETE /reports/:id — soft-deletes the report (sets deletedAt on the
  /// server). The doc is preserved for admin audit; the worker just hides
  /// it from their view. Returns true on success.
  static Future<bool> deleteReport(String reportId) async {
    try {
      // 45-sec timeout covers Render free-tier cold-start. Without
      // UptimeRobot keep-warm the first request after idle can take
      // 30-50 sec; a 30-sec timeout used to fire spuriously and the
      // strict-delete UI would surface as "server failed" on what was
      // actually just a wake-up.
      final res = await http.delete(
        Uri.parse('$baseUrl/reports/$reportId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 45));
      _guard(res.statusCode);
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('[deleteReport] HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } on UnauthorizedException {
      rethrow; // let the controller propagate to AuthController.forceLogout
    } catch (e) {
      // ignore: avoid_print
      print('[deleteReport] error: $e');
      return false;
    }
  }

  /// PATCH /reports/:id/restore — clears deletedAt. Powers the "Undo"
  /// snackbar after a worker accidentally deletes a report.
  static Future<bool> restoreReport(String reportId) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/reports/$reportId/restore'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      _guard(res.statusCode);
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('[restoreReport] HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('[restoreReport] error: $e');
      return false;
    }
  }

  /// PATCH /admin/reports/:id/restore — admin clears deletedAt on any
  /// report (cross-worker, unlike the worker-scoped /reports/:id/restore).
  /// Powers the "Restore" button in the admin deleted-reports panel.
  static Future<bool> adminRestoreReport(String reportId) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl/admin/reports/$reportId/restore'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      _guard(res.statusCode);
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('[adminRestoreReport] HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('[adminRestoreReport] error: $e');
      return false;
    }
  }

  /// DELETE /admin/reports/:id/permanent — hard-deletes a soft-deleted
  /// report. Server rejects this with 400 if the report isn't already
  /// soft-deleted (forces the "audit first" policy).
  static Future<bool> adminPermanentlyDeleteReport(String reportId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/reports/$reportId/permanent'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      _guard(res.statusCode);
      if (res.statusCode != 200) {
        // ignore: avoid_print
        print('[adminPermanentlyDeleteReport] HTTP ${res.statusCode}: ${res.body}');
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['success'] == true;
    } on UnauthorizedException {
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('[adminPermanentlyDeleteReport] error: $e');
      return false;
    }
  }

  /// GET /admin/reports/deleted — admin audit view of every soft-deleted
  /// report (worker name populated). Sorted most-recent deletion first.
  static Future<List<dynamic>> getDeletedReports() async {
    final res = await http
        .get(Uri.parse('$baseUrl/admin/reports/deleted'), headers: _headers)
        .timeout(const Duration(seconds: 45));
    _guard(res.statusCode);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['data'] as List? ?? [];
  }

  static Future<List<dynamic>> getReports() async {
    final res = await http
        .get(Uri.parse('$baseUrl/reports'), headers: _headers)
        .timeout(const Duration(seconds: 45));
    _guard(res.statusCode);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['data'] as List? ?? [];
  }

  // ── Admin — Workers ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getWorkers() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/workers'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> addWorker(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/admin/workers'),
      headers: _headers,
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> deactivateWorker(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/admin/workers/$id/deactivate'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> activateWorker(String id) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/admin/workers/$id/activate'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getWorkerProfile(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/workers/$id/profile'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getWorkerPatients(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/workers/$id/patients'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getWorkerReports(String id) async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/workers/$id/reports'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Admin — Reports ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAdminReports({
    String? band,
    String? date,
    String? month,
    String? year,
    String? worker,
    String? district,
    String? block,
  }) async {
    final params = <String, String>{};
    if (band     != null) params['band']     = band;
    if (date     != null) params['date']     = date;
    if (month    != null) params['month']    = month;
    if (year     != null) params['year']     = year;
    if (worker   != null) params['worker']   = worker;
    if (district != null) params['district'] = district;
    if (block    != null) params['block']    = block;
    final uri = Uri.parse('$baseUrl/admin/reports')
        .replace(queryParameters: params.isEmpty ? null : params);
    final res = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 45));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getAdminStats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/stats'),
      headers: _headers,
    ).timeout(const Duration(seconds: 45));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Returns { districts: [...], blocks: [...] } — used to populate the
  /// admin reports filter dropdowns.
  static Future<Map<String, dynamic>> getAdminLocations() async {
    final res = await http.get(
      Uri.parse('$baseUrl/admin/locations'),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
    _guard(res.statusCode);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
