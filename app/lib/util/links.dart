import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// صفحة سياسة الخصوصية على الخادم، تُفتح في المتصفح
Future<void> openPrivacyPolicy() =>
    launchUrl(Uri.parse('$apiBaseUrl/privacy'), mode: LaunchMode.externalApplication);
