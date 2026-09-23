import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../api/api_client.dart';
import '../api/hajiz_api.dart';
import '../api/owner_api.dart';
import '../api/models.dart';
import 'session.dart';

/// الخدمات المشتركة بين الشاشات.
typedef Locator = Future<({double lat, double lng})?> Function();

class AppServices {
  AppServices({required this.client, required this.session, Locator? locate})
      : api = HajizApi(client),
        owner = OwnerApi(client),
        locate = locate ?? locateDevice {
    client.token = session.token;
  }

  /// موقع الزبون لترتيب المحلات حسب القرب؛ null إذا رُفض أو تعذّر
  final Locator locate;

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
