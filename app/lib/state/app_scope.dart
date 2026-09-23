import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../api/hajiz_api.dart';
import '../api/owner_api.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import 'push.dart';
import 'session.dart';

/// الخدمات المشتركة بين الشاشات.
/// وضع الزبون للجميع؛ وضع المحل لصاحب محل مقبول فقط، ويبدّل بينهما من الواجهة
enum AppMode { customer, shop }

typedef Locator = Future<({double lat, double lng})?> Function();

class AppServices {
  AppServices({required this.client, required this.session, Locator? locate, PushService? push})
      : api = HajizApi(client),
        owner = OwnerApi(client),
        locate = locate ?? locateDevice,
        push = push ?? const NoPushService() {
    client.token = session.token;
  }

  // ---------------- الإشعارات ----------------

  final PushService push;
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// الإذن الحالي؛ صاحب المحل يرى تنبيهاً إذا كانت الإشعارات متوقفة
  final pushPermission = ValueNotifier<PushPermission>(PushPermission.unavailable);

  /// يزيد مع كل إشعار يصل والتطبيق مفتوح، فتعيد الشاشات المفتوحة تحميل بياناتها
  final pushTick = ValueNotifier<int>(0);

  /// عدد غير المقروء لكل وضع
  final unread = {'customer': ValueNotifier<int>(0), 'shop': ValueNotifier<int>(0)};

  /// إشعار فُتح والتطبيق يحتاج أن يعرض الحجز؛ AppShell يتولاه
  final openedEvent = ValueNotifier<PushEvent?>(null);

  final _subs = <StreamSubscription<Object?>>[];

  /// يُستدعى مرة عند فتح التطبيق
  Future<void> startPush() async {
    pushPermission.value = await push.init();
    _subs
      ..add(push.tokenRefresh.listen((_) => syncPushToken()))
      ..add(push.foreground.listen(_onForeground))
      ..add(push.opened.listen((e) => openedEvent.value = e));
    final first = await push.initial();
    if (first != null) openedEvent.value = first;
    await syncPushToken();
  }

  /// يرسل مفتاح الإشعارات للخادم؛ يُعاد بعد التسجيل وعند فتح التطبيق وعند تغيّر المفتاح
  Future<void> syncPushToken() async {
    if (!session.isRegistered) return;
    try {
      final permission = await push.permission();
      pushPermission.value = permission;
      if (permission == PushPermission.unavailable) return;
      final token = await push.token();
      await api.savePushToken(token, enabled: permission == PushPermission.granted);
    } catch (_) {
      // يُعاد عند الفتح التالي
    }
  }

  /// بعد عودة المستخدم من إعدادات الهاتف
  Future<void> recheckPush() async {
    final before = pushPermission.value;
    pushPermission.value = await push.permission();
    if (pushPermission.value != before) await syncPushToken();
  }

  void _onForeground(PushEvent e) {
    pushTick.value++;
    refreshUnread(e.audience);
    final title = e.title;
    final context = messengerKey.currentContext;
    if (title == null || context == null) return;
    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Text(e.body == null ? title : '$title\n${e.body}'),
      duration: const Duration(seconds: 6),
      action: e.bookingId == null
          ? null
          : SnackBarAction(label: AppLocalizations.of(context).openAction, onPressed: () => openedEvent.value = e),
    ));
  }

  Future<void> refreshUnread(String audience) async {
    if (!session.isRegistered) return;
    try {
      unread[audience]!.value = (await api.notifications(audience)).unread;
    } catch (_) {}
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }

  /// موقع الزبون لترتيب المحلات حسب القرب؛ null إذا رُفض أو تعذّر
  final Locator locate;

  late final mode = ValueNotifier<AppMode>(AppMode.customer);

  Future<void> switchMode(AppMode m) async {
    mode.value = m;
    await session.saveAppMode(m.name);
  }

  final ApiClient client;
  final HajizApi api;
  final OwnerApi owner;
  final Session session;

  ServerConfig? _config;
  Future<ServerConfig> config({bool refresh = false}) async {
    if (_config == null || refresh) _config = await api.config();
    return _config!;
  }

  /// يسجل الرقم والاسم والجهاز عند أول حجز
  Future<void> ensureRegistered(String name, String phone) async {
    if (session.isRegistered) return;
    final r = await api.register(name, phone, session.deviceId);
    await session.saveRegistration(r.token, r.user);
    client.token = r.token;
    unawaited(syncPushToken());
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

/// يطلب إذن الموقع مرة، ولا ينتظر أكثر من 10 ثوانٍ
Future<({double lat, double lng})?> locateDevice() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
    ).timeout(const Duration(seconds: 10));
    return (lat: p.latitude, lng: p.longitude);
  } catch (_) {
    return null;
  }
}
