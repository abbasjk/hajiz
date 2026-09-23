import '../api/models.dart';
import '../l10n/app_localizations.dart';

/// العراق على UTC+3 طوال السنة؛ كل الأوقات تُعرض بتوقيت بغداد مهما كانت ساعة الهاتف.
const baghdadOffset = Duration(hours: 3);

/// الوقت بتوقيت بغداد (الحقول فقط، لا تُستخدم للحساب)
DateTime toBaghdad(DateTime instant) => instant.toUtc().add(baghdadOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// التاريخ المحلي بصيغة YYYY-MM-DD كما يطلبه الخادم
String localDateKey(DateTime instant) {
  final b = toBaghdad(instant);
  return '${b.year}-${_two(b.month)}-${_two(b.day)}';
}

/// 0 = الأحد ... 6 = السبت، كما في الخادم
int localDayOfWeek(DateTime instant) => toBaghdad(instant).weekday % 7;

String monthName(AppLocalizations l, int month) => [
      l.month1, l.month2, l.month3, l.month4, l.month5, l.month6,
      l.month7, l.month8, l.month9, l.month10, l.month11, l.month12,
    ][month - 1];

String dayName(AppLocalizations l, int dayOfWeek) =>
    [l.day0, l.day1, l.day2, l.day3, l.day4, l.day5, l.day6][dayOfWeek];

/// نظام اثنتي عشرة ساعة بأرقام غربية: 4:45 م
String formatTime(AppLocalizations l, DateTime instant) {
  final b = toBaghdad(instant);
  final h = b.hour % 12 == 0 ? 12 : b.hour % 12;
  return '$h:${_two(b.minute)} ${b.hour < 12 ? l.am : l.pm}';
}

/// "HH:MM" من الخادم إلى 12 ساعة
String formatClock(AppLocalizations l, String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${parts[1]} ${hour < 12 ? l.am : l.pm}';
}

/// السبت 26
String formatDayShort(AppLocalizations l, DateTime instant) =>
    '${dayName(l, localDayOfWeek(instant))} ${toBaghdad(instant).day}';

/// السبت 26 أيلول
String formatDayLong(AppLocalizations l, DateTime instant) =>
    '${formatDayShort(l, instant)} ${monthName(l, toBaghdad(instant).month)}';

/// السبت 26 أيلول · 4:45 م
String formatAppointment(AppLocalizations l, DateTime instant) =>
    '${formatDayLong(l, instant)} · ${formatTime(l, instant)}';

/// 10,000
String formatAmount(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String formatPrice(AppLocalizations l, Service s) => switch (s.priceType) {
      PriceType.fixed => l.priceIqd(formatAmount(s.price ?? 0)),
      PriceType.startsFrom => l.priceStartsFrom(formatAmount(s.price ?? 0)),
      PriceType.afterInspection => l.priceAfterInspection,
    };

/// المجموع؛ إذا كانت فيه خدمة "يبدأ من" أو "بعد المعاينة" يُكتب بعده +
String formatTotal(AppLocalizations l, List<Service> services) {
  final sum = services.fold<int>(0, (a, s) => a + (s.price ?? 0));
  final open = services.any((s) => s.priceType != PriceType.fixed);
  final amount = l.priceIqd(formatAmount(sum));
  return open ? l.totalPlus(amount) : amount;
}

/// مدة مقروءة: 15 دقيقة، ساعة واحدة، 4 ساعات، يوم
String formatDuration(AppLocalizations l, int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) return l.durationDay;
  if (minutes >= 60 && minutes % 60 == 0) return l.durationHours(minutes ~/ 60);
  return l.durationMinutes(minutes);
}

/// العداد التنازلي: 00:42:15
String formatCountdown(Duration d) {
  if (d.isNegative) return '00:00:00';
  return '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
}
