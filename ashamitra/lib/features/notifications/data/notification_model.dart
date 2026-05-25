/// One real notification fetched from the backend.
class NotificationModel {
  final String id;
  final String type;       // red_band | yellow_band | welcome | follow_up | sync
  final String title;
  final String body;
  final String link;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> j) => NotificationModel(
        id:        j['id']?.toString() ?? j['_id']?.toString() ?? '',
        type:      j['type']?.toString() ?? 'info',
        title:     j['title']?.toString() ?? '',
        body:      j['body']?.toString() ?? '',
        link:      j['link']?.toString() ?? '',
        data:      (j['data'] is Map) ? Map<String, dynamic>.from(j['data']) : const {},
        read:      j['read'] == true,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}
