import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// إشعار وصل من الخادم؛ audience تحدد الوضع الذي يُفتح فيه (زبون أو محل)
class PushEvent {
  const PushEvent({required this.type, required this.audience, this.bookingId, this.title, this.body});

  final String type;
  final String audience;
  final int? bookingId;
  final String? title;
  final String? body;

  bool get forShop => audience == 'shop';

  factory PushEvent.fromData(Map<String, dynamic> data, {String? title, String? body}) => PushEvent(
        type: data['type'] as String? ?? '',
        audience: data['audience'] as String? ?? 'customer',
        bookingId: int.tryParse('${data['bookingId'] ?? ''}'),
        title: title,
        body: body,
      );
}

/// الإذن: granted، أو denied (أوقفه المستخدم)، أو unavailable (Firebase غير مُعد بعد)
enum PushPermission { granted, denied, unavailable }

/// واجهة مستقلة عن Firebase حتى يعمل التطبيق والاختبارات بدونه
abstract class PushService {
  /// يطلب الإذن مرة (أندرويد 13 وما بعده يعرض السؤال)
  Future<PushPermission> init();
  Future<PushPermission> permission();
  Future<String?> token();
  Stream<String> get tokenRefresh;

  /// إشعار وصل والتطبيق مفتوح
  Stream<PushEvent> get foreground;

  /// ضغط المستخدم على إشعار والتطبيق في الخلفية
  Stream<PushEvent> get opened;

  /// الإشعار الذي فُتح منه التطبيق وهو مغلق
  Future<PushEvent?> initial();
}

class NoPushService implements PushService {
  const NoPushService();
  @override
  Future<PushPermission> init() async => PushPermission.unavailable;
  @override
  Future<PushPermission> permission() async => PushPermission.unavailable;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  Stream<PushEvent> get foreground => const Stream.empty();
  @override
  Stream<PushEvent> get opened => const Stream.empty();
  @override
  Future<PushEvent?> initial() async => null;
}

/// Firebase Cloud Messaging. بدون ملف google-services.json يفشل الإعداد
/// فيعمل التطبيق بإشعارات داخلية فقط.
class FirebasePushService implements PushService {
  bool _ready = false;

  static PushEvent _event(RemoteMessage m) =>
      PushEvent.fromData(m.data, title: m.notification?.title, body: m.notification?.body);

  @override
  Future<PushPermission> init() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _ready = true;
      final settings = await FirebaseMessaging.instance.requestPermission();
      return _map(settings.authorizationStatus);
    } catch (_) {
      _ready = false;
      return PushPermission.unavailable;
    }
  }

  static PushPermission _map(AuthorizationStatus s) =>
      s == AuthorizationStatus.denied ? PushPermission.denied : PushPermission.granted;

  @override
  Future<PushPermission> permission() async {
    if (!_ready) return PushPermission.unavailable;
    try {
      return _map((await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus);
    } catch (_) {
      return PushPermission.unavailable;
    }
  }

  @override
  Future<String?> token() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefresh => _ready ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();

  @override
  Stream<PushEvent> get foreground => _ready ? FirebaseMessaging.onMessage.map(_event) : const Stream.empty();

  @override
  Stream<PushEvent> get opened => _ready ? FirebaseMessaging.onMessageOpenedApp.map(_event) : const Stream.empty();

  @override
  Future<PushEvent?> initial() async {
    if (!_ready) return null;
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : _event(m);
  }
}
