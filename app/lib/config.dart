import 'package:flutter/foundation.dart';

/// عنوان الخادم؛ يُغيَّر عند البناء: --dart-define=API_URL=http://10.0.2.2:3000
const apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://hajiz-production.up.railway.app',
);

/// يُرسل مع كل طلب لفحص الإصدار (إجبار التحديث)
const appVersion = '0.3.0';

String get appPlatform {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}
