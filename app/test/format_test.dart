import 'package:flutter_test/flutter_test.dart';
import 'package:hajiz/api/models.dart';
import 'package:hajiz/l10n/app_localizations_ar.dart';
import 'package:hajiz/util/deadline.dart';
import 'package:hajiz/util/format.dart';
import 'package:hajiz/util/phone.dart';

void main() {
  final l = AppLocalizationsAr();
  DateTime baghdad(String s) => DateTime.parse('$s+03:00').toUtc();

  test('12-hour clock with western digits in Baghdad time', () {
    expect(formatTime(l, baghdad('2026-10-03T16:45:00')), '4:45 م');
    expect(formatTime(l, baghdad('2026-10-03T00:15:00')), '12:15 ص');
    expect(formatTime(l, baghdad('2026-10-03T12:00:00')), '12:00 م');
    expect(formatClock(l, '09:00'), '9:00 ص');
  });

  test('dates use Iraqi month names and the Baghdad calendar', () {
    // 22:30 UTC هو 01:30 فجر اليوم التالي في بغداد
    final t = DateTime.utc(2026, 9, 25, 22, 30);
    expect(localDateKey(t), '2026-09-26');
    expect(formatDayLong(l, t), 'السبت 26 أيلول');
    expect(localDayOfWeek(t), 6);
  });

  test('prices and totals', () {
    expect(formatAmount(10000), '10,000');
    expect(formatAmount(950), '950');
    const fixed = Service(id: 1, name: 'a', durationMinutes: 30, priceType: PriceType.fixed, price: 10000);
    const from = Service(id: 2, name: 'b', durationMinutes: 15, priceType: PriceType.startsFrom, price: 5000);
    expect(formatTotal(l, [fixed]), '10,000 د.ع');
    expect(formatTotal(l, [fixed, from]), '15,000 د.ع +');
  });

  test('durations read naturally', () {
    expect(formatDuration(l, 15), '15 دقيقة');
    expect(formatDuration(l, 60), 'ساعة واحدة');
    expect(formatDuration(l, 120), 'ساعتين');
    expect(formatDuration(l, 240), '4 ساعات');
    expect(formatDuration(l, 1440), 'يوم');
    expect(formatCountdown(const Duration(minutes: 42, seconds: 15)), '00:42:15');
  });

  test('phone normalization matches the server', () {
    expect(normalizeIraqiPhone('0770 123 4567'), '07701234567');
    expect(normalizeIraqiPhone('+9647701234567'), '07701234567');
    expect(normalizeIraqiPhone('٠٧٧٠١٢٣٤٥٦٧'), '07701234567');
    expect(normalizeIraqiPhone('12345'), isNull);
  });

  test('expected deadline follows the server tiers', () {
    const normal = DeadlineTable({'same_day_under_6h': 15, 'same_day': 30, 'tomorrow': 60, 'within_week': 240, 'week_or_more': 720});
    final now = baghdad('2026-10-05T08:00:00');
    expect(expectedDeadlineMinutes(normal, now, baghdad('2026-10-05T12:00:00')), 15);
    expect(expectedDeadlineMinutes(normal, now, baghdad('2026-10-06T10:00:00')), 60);
    expect(expectedDeadlineMinutes(normal, now, baghdad('2026-10-20T10:00:00')), 720);
  });
}
