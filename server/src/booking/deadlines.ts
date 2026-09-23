import type { DeadlineTable } from './settings.js';
import { addMinutes, daysBetween, minutesBetween, toLocalDate } from './time.js';

/** المهلة تتقلص كلما اقترب الموعد؛ الأيام تُحسب بالتقويم المحلي في بغداد. */
export function deadlineTier(now: Date, startsAt: Date): keyof DeadlineTable {
  const days = daysBetween(toLocalDate(now), toLocalDate(startsAt));
  if (days <= 0) return minutesBetween(now, startsAt) < 6 * 60 ? 'same_day_under_6h' : 'same_day';
  if (days === 1) return 'tomorrow';
  if (days < 7) return 'within_week';
  return 'week_or_more';
}

/** نهاية مهلة الرد، ولا تتجاوز وقت الموعد نفسه. */
export function responseDeadline(now: Date, startsAt: Date, table: DeadlineTable, cap: Date = startsAt): Date {
  const deadline = addMinutes(now, table[deadlineTier(now, startsAt)]);
  return deadline.getTime() < cap.getTime() ? deadline : cap;
}
