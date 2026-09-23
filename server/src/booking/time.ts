/**
 * العراق على توقيت ثابت UTC+3 طوال السنة (لا توقيت صيفي منذ 2008)،
 * فالتحويل إزاحة ثابتة دون مكتبة مناطق زمنية.
 */
export const BAGHDAD_OFFSET_MINUTES = 180;

const MINUTE = 60_000;
const DAY = 24 * 60 * MINUTE;

/** تاريخ محلي بصيغة YYYY-MM-DD. */
export type LocalDate = string;

export function isLocalDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().startsWith(value);
}

/** بداية اليوم المحلي (منتصف الليل في بغداد) كوقت عالمي. */
export function startOfLocalDay(date: LocalDate): Date {
  return new Date(Date.parse(`${date}T00:00:00Z`) - BAGHDAD_OFFSET_MINUTES * MINUTE);
}

/** التاريخ المحلي لوقت عالمي. */
export function toLocalDate(instant: Date): LocalDate {
  return new Date(instant.getTime() + BAGHDAD_OFFSET_MINUTES * MINUTE).toISOString().slice(0, 10);
}

export function addDays(date: LocalDate, days: number): LocalDate {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY).toISOString().slice(0, 10);
}

/** 0 = الأحد ... 6 = السبت، كما في قاعدة البيانات. */
export function dayOfWeek(date: LocalDate): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay();
}

/** عدد الأيام التقويمية بين تاريخين محليين. */
export function daysBetween(from: LocalDate, to: LocalDate): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY);
}

/** "HH:MM" أو "HH:MM:SS" إلى دقائق من منتصف الليل. */
export function timeToMinutes(time: string): number {
  const [h = '0', m = '0'] = time.split(':');
  return Number(h) * 60 + Number(m);
}

export function addMinutes(instant: Date, minutes: number): Date {
  return new Date(instant.getTime() + minutes * MINUTE);
}

export function minutesBetween(from: Date, to: Date): number {
  return (to.getTime() - from.getTime()) / MINUTE;
}
