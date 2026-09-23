import { AppError } from '../lib/errors.js';
import { timeToMinutes } from '../booking/time.js';

export interface PeriodInput {
  dayOfWeek: number;
  from: string; // HH:MM
  to: string; // HH:MM، إذا كان أصغر من البداية أو يساويها فالفترة تنتهي في اليوم التالي
}

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const WEEK = 7 * 24 * 60;

/**
 * يتحقق من فترات العمل: صيغة الوقت صحيحة، ولا تتداخل فترتان
 * (مع مراعاة الفترات الممتدة بعد منتصف الليل، ومنها ليلة السبت إلى الأحد).
 */
export function validatePeriods(periods: PeriodInput[]): void {
  const intervals: [number, number][] = [];
  for (const p of periods) {
    if (!Number.isInteger(p.dayOfWeek) || p.dayOfWeek < 0 || p.dayOfWeek > 6 || !TIME.test(p.from) || !TIME.test(p.to)) {
      throw new AppError(400, 'invalid_period');
    }
    const from = timeToMinutes(p.from);
    let to = timeToMinutes(p.to);
    if (to === from) throw new AppError(400, 'invalid_period');
    if (to < from) to += 24 * 60;
    const start = p.dayOfWeek * 24 * 60 + from;
    intervals.push([start, start + (to - from)]);
  }
  // على دائرة الأسبوع: نكرر كل فترة بعد أسبوع لنكشف التداخل عبر نهاية السبت
  const all = [...intervals, ...intervals.map(([a, b]) => [a + WEEK, b + WEEK] as [number, number])]
    .sort((x, y) => x[0] - y[0]);
  for (let i = 1; i < all.length; i++) {
    if (all[i]![0] < all[i - 1]![1]) throw new AppError(400, 'overlapping_periods');
  }
}
