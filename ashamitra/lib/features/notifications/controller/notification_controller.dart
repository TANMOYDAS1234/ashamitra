import 'dart:async';
import 'dart:convert';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/api_service.dart';
import '../data/notification_model.dart';

/// Single source of truth for the notification list + unread count.
///
/// Loads on first access, refreshes when the sheet is opened, and polls
/// every 90 seconds while the app is foregrounded.
class NotificationController extends GetxController {
  final items       = <NotificationModel>[].obs;
  final unreadCount = 0.obs;
  final isLoading   = false.obs;

  Timer? _pollTimer;

  @override
  void onInit() {
    super.onInit();
    fetchLatest();
    _pollTimer = Timer.periodic(const Duration(seconds: 90), (_) => fetchLatest(silent: true));
  }

  @override
  void onClose() {
    _pollTimer?.cancel();
    super.onClose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
      };

  Future<void> fetchLatest({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    try {
      final res = await http
          .get(Uri.parse('${ApiService.baseUrl}/notifications?limit=50'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 401) {
        // Auth handled elsewhere
        return;
      }
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] != true) return;
      final list = ((body['data'] as List?) ?? const [])
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      items.value      = list;
      unreadCount.value = body['unreadCount'] is num
          ? (body['unreadCount'] as num).toInt()
          : list.where((n) => !n.read).length;
    } catch (_) {
      // Offline / cold-start — keep existing list
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<void> markRead(String id) async {
    final idx = items.indexWhere((n) => n.id == id);
    if (idx == -1 || items[idx].read) return;
    // Optimistic update
    final n = items[idx];
    items[idx] = NotificationModel(
      id: n.id, type: n.type, title: n.title, body: n.body,
      link: n.link, data: n.data, read: true, createdAt: n.createdAt,
    );
    unreadCount.value = (unreadCount.value - 1).clamp(0, 9999);
    try {
      await http
          .patch(Uri.parse('${ApiService.baseUrl}/notifications/$id/read'), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    if (items.every((n) => n.read)) return;
    items.value = items
        .map((n) => NotificationModel(
              id: n.id, type: n.type, title: n.title, body: n.body,
              link: n.link, data: n.data, read: true, createdAt: n.createdAt,
            ))
        .toList();
    unreadCount.value = 0;
    try {
      await http
          .patch(Uri.parse('${ApiService.baseUrl}/notifications/read-all'), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  Future<void> dismiss(String id) async {
    items.removeWhere((n) => n.id == id);
    try {
      await http
          .delete(Uri.parse('${ApiService.baseUrl}/notifications/$id'), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
}
