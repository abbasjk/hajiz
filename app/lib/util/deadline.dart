import '../api/models.dart';
import 'format.dart';

/// نفس قاعدة الخادم: المهلة تتقلص كلما اقترب الموعد، والأيام بتقويم بغداد.
/// تُستخدم فقط لعرض "المحل يرد خلال…" قبل الإرسال؛ الخادم هو من يحدد المهلة الفعلية.
String deadlineTier(DateTime now, DateTime startsAt) {
  final today = DateTime.parse(localDateKey(now));
  final day = DateTime.parse(localDateKey(startsAt));
  final days = day.difference(today).inDays;
  if (days <= 0) return startsAt.difference(now).inMinutes < 360 ? 'same_day_under_6h' : 'same_day';
  if (days == 1) return 'tomorrow';
  if (days < 7) return 'within_week';
  return 'week_or_more';
}

int expectedDeadlineMinutes(DeadlineTable table, DateTime now, DateTime startsAt) {
  final minutes = table.minutes[deadlineTier(now, startsAt)] ?? 60;
  final untilStart = startsAt.difference(now).inMinutes;
  return minutes < untilStart ? minutes : untilStart;
}
