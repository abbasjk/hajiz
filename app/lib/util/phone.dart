/// نفس قاعدة الخادم: رقم موبايل عراقي بصيغة 07XXXXXXXXX أو null.
String? normalizeIraqiPhone(String input) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final western = input.split('').map((c) {
    final a = arabic.indexOf(c);
    if (a >= 0) return '$a';
    final p = persian.indexOf(c);
    return p >= 0 ? '$p' : c;
  }).join();
  final digits = western.replaceAll(RegExp(r'[\s\-().]'), '');
  final m = RegExp(r'^(?:\+964|00964|964)?0?(7\d{9})$').firstMatch(digits);
  return m == null ? null : '0${m.group(1)}';
}
