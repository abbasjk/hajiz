import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// ما يُحفظ على الجهاز: معرّف الجهاز، مفتاح الدخول، بيانات الزبون، وآخر نسخة من حجوزاتي.
class Session {
  Session(this._prefs);

  final SharedPreferences _prefs;

  static Future<Session> load() async => Session(await SharedPreferences.getInstance());

  /// معرّف ثابت لهذا الجهاز، يُنشأ مرة واحدة
  String get deviceId {
    var id = _prefs.getString('deviceId');
    if (id == null) {
      id = newIdempotencyKey();
      _prefs.setString('deviceId', id);
    }
    return id;
  }

  String? get token => _prefs.getString('token');

  RegisteredUser? get user {
    final raw = _prefs.getString('user');
    return raw == null ? null : RegisteredUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  bool get isRegistered => token != null;

  /// آخر وضع استُخدم: 'customer' أو 'shop'، يفتح التطبيق عليه
  String get appMode => _prefs.getString('appMode') ?? 'customer';
  Future<void> saveAppMode(String mode) => _prefs.setString('appMode', mode);

  Future<void> saveRegistration(String token, RegisteredUser user) async {
    await _prefs.setString('token', token);
    await _prefs.setString('user', jsonEncode(user.toJson()));
  }

  Future<void> clearRegistration() async {
    await _prefs.remove('token');
    await _prefs.remove('user');
    await _prefs.remove('bookingsCache');
    await _prefs.remove('appMode');
  }

  /// حجوزاتي تبقى ظاهرة من آخر تحميل، مع وقت آخر تحديث
  ({Map<String, dynamic> json, DateTime at})? get cachedBookings {
    final raw = _prefs.getString('bookingsCache');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (json: j['json'] as Map<String, dynamic>, at: DateTime.parse(j['at'] as String));
  }

  Future<void> cacheBookings(Map<String, dynamic> json) =>
      _prefs.setString('bookingsCache', jsonEncode({'json': json, 'at': DateTime.now().toIso8601String()}));
}
