import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

/// خطأ من الخادم برمز ثابت؛ الواجهة تترجم الرمز من ملف الترجمة.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, [this.details = const {}]);
  final int statusCode;
  final String code;
  final Map<String, dynamic> details;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

/// تعذّر الوصول للخادم (لا إنترنت أو انقطاع).
class NetworkException implements Exception {}

/// مفتاح فريد يمنع الإرسال المكرر عند الضغط مرتين أو إعادة المحاولة.
String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = apiBaseUrl}) : _http = client ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  String? token;

  /// true عند فشل آخر طلب بسبب الاتصال: يظهر شريط "لا يوجد اتصال"
  final offline = ValueNotifier<bool>(false);

  /// true عندما يطلب الخادم تحديث التطبيق (426)
  final updateRequired = ValueNotifier<bool>(false);

  /// فرق ساعة الهاتف عن الخادم؛ العداد والمهل تُحسب بتوقيت الخادم
  Duration serverOffset = Duration.zero;
  DateTime get serverNow => DateTime.now().add(serverOffset);

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, {Object? body, String? idempotencyKey}) =>
      _send('POST', path, body: body, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  /// الصور تُخدم من الخادم بمسار نسبي مثل /photos/12
  String absoluteUrl(String url) => url.startsWith('/') ? '$baseUrl$url' : url;

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    final uri = Uri.parse('$baseUrl/v1$path').replace(queryParameters: query);
    final headers = <String, String>{
      'x-app-platform': appPlatform,
      'x-app-version': appVersion,
      if (body != null) 'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      'idempotency-key': ?idempotencyKey,
    };
    http.Response res;
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      res = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    } catch (_) {
      offline.value = true;
      throw NetworkException();
    }
    offline.value = false;
    final json = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      final error = (json['error'] as Map?)?.cast<String, dynamic>() ?? {};
      if (res.statusCode == 426) updateRequired.value = true;
      throw ApiException(res.statusCode, error['code'] as String? ?? 'unknown', error);
    }
    final serverTime = json['serverTime'];
    if (serverTime is String) {
      serverOffset = DateTime.parse(serverTime).difference(DateTime.now());
    }
    return json;
  }
}
