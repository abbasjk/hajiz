import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// صفحة سياسة الخصوصية على الخادم، تُفتح في المتصفح
Future<void> openPrivacyPolicy() =>
    launchUrl(Uri.parse('$apiBaseUrl/privacy'), mode: LaunchMode.externalApplication);

/// "افتح في الخرائط": ينتقل لتطبيق الخرائط في الهاتف
Future<void> openInMaps(double lat, double lng, String label) async {
  final Uri uri;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    uri = Uri.https('maps.apple.com', '/', {'q': label, 'll': '$lat,$lng'});
  } else {
    uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// واتساب يحتاج الرقم الدولي: 07701234567 → 9647701234567
Future<void> openWhatsApp(String phone) =>
    launchUrl(Uri.https('wa.me', '/964${phone.replaceFirst(RegExp('^0'), '')}'), mode: LaunchMode.externalApplication);
