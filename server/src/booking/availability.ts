import { AppError } from '../lib/errors.js';
import type { Queryable } from './db.js';
import { loadSettings, type EngineSettings } from './settings.js';
import {
  addDays,
  addMinutes,
  dayOfWeek,
  startOfLocalDay,
  timeToMinutes,
  toLocalDate,
  type LocalDate,
} from './time.js';

export interface Interval {
  start: Date;
  end: Date;
}

/** الحجوزات التي تشغل الوقت: المعلق هو القفل المؤقت. */
export const ACTIVE_STATUSES = ['pending_shop', 'pending_customer', 'confirmed'] as const;

export interface ShopForBooking {
  id: number;
  ownerId: number;
  scheduleId: number;
  deadlineMode: 'fast' | 'normal' | 'flexible';
  freeCancelHours: number;
  minLeadMinutes: number;
  instantBooking: boolean;
  bufferMinutes: number;
}

export interface ServiceLine {
  id: number;
  name: string;
  durationMinutes: number;
  priceType: 'fixed' | 'starts_from' | 'after_inspection';
  price: number | null;
}

/** المحل المقبول مع جدوله؛ غير المقبول لا يستقبل حجوزات. */
export async function loadShop(db: Queryable, shopId: number, { lock = false } = {}): Promise<ShopForBooking> {
  const { rows } = await db.query(
    `SELECT s.id, s.owner_id, s.deadline_mode, s.free_cancel_hours, s.min_lead_minutes,
            s.instant_booking, s.buffer_minutes,
            (SELECT id FROM schedules WHERE shop_id = s.id ORDER BY id LIMIT 1) AS schedule_id
     FROM shops s WHERE s.id = $1 AND s.status = 'approved'${lock ? ' FOR UPDATE' : ''}`,
    [shopId],
  );
  const r = rows[0];
  if (!r || r.schedule_id === null) throw new AppError(404, 'shop_not_found');
  return {
    id: r.id,
    ownerId: r.owner_id,
    scheduleId: r.schedule_id,
    deadlineMode: r.deadline_mode,
    freeCancelHours: r.free_cancel_hours,
    minLeadMinutes: r.min_lead_minutes,
    instantBooking: r.instant_booking,
    bufferMinutes: r.buffer_minutes,
  };
}

/** خدمات مفعّلة من المحل نفسه؛ عدة خدمات في حجز واحد تُجمع مدتها. */
export async function loadServices(db: Queryable, shopId: number, serviceIds: number[]): Promise<ServiceLine[]> {
  if (serviceIds.length === 0 || new Set(serviceIds).size !== serviceIds.length) {
    throw new AppError(400, 'invalid_services');
  }
  const { rows } = await db.query(
    `SELECT id, name, duration_minutes, price_type, price FROM services
     WHERE shop_id = $1 AND active AND id = ANY($2::bigint[])`,
    [shopId, serviceIds],
  );
  if (rows.length !== serviceIds.length) throw new AppError(400, 'invalid_services');
  const byId = new Map(rows.map((r) => [Number(r.id), r]));
  return serviceIds.map((id) => {
    const r = byId.get(id)!;
    return {
      id,
      name: r.name,
      durationMinutes: r.duration_minutes,
      priceType: r.price_type,
      price: r.price,
    };
  });
}

/**
 * فترات العمل ليوم محلي: الجدول المؤقت إن غطّى التاريخ، وإلا الأسبوعي.
 * الفترة تنتمي لليوم الذي تبدأ فيه؛ إذا انتهت بعد منتصف الليل تمتد لليوم التالي.
 */
export async function workingPeriods(db: Queryable, scheduleId: number, date: LocalDate): Promise<Interval[]> {
  const dow = dayOfWeek(date);
  const temp = await db.query<{ id: number }>(
    `SELECT id FROM temporary_schedules
     WHERE schedule_id = $1 AND $2::date BETWEEN from_date AND to_date
     ORDER BY id DESC LIMIT 1`,
    [scheduleId, date],
  );
  const { rows } = temp.rows[0]
    ? await db.query<{ start_time: string; end_time: string }>(
        `SELECT start_time, end_time FROM temporary_schedule_periods
         WHERE temporary_schedule_id = $1 AND day_of_week = $2 ORDER BY start_time`,
        [temp.rows[0].id, dow],
      )
    : await db.query<{ start_time: string; end_time: string }>(
        `SELECT start_time, end_time FROM weekly_periods
         WHERE schedule_id = $1 AND day_of_week = $2 ORDER BY start_time`,
        [scheduleId, dow],
      );
  const midnight = startOfLocalDay(date);
  return rows.map((r) => {
    const from = timeToMinutes(r.start_time);
    let to = timeToMinutes(r.end_time);
    if (to <= from) to += 24 * 60;
    return { start: addMinutes(midnight, from), end: addMinutes(midnight, to) };
  });
}

/**
 * الأوقات المشغولة: الحجوزات النشطة موسّعة بالوقت الفاصل من الجهتين، والإغلاقات الطارئة.
 */
export async function busyIntervals(
  db: Queryable,
  scheduleId: number,
  range: Interval,
  bufferMinutes: number,
  excludeBookingId?: number,
): Promise<Interval[]> {
  const from = addMinutes(range.start, -bufferMinutes);
  const to = addMinutes(range.end, bufferMinutes);
  const [bookings, closures] = await Promise.all([
    db.query<{ starts_at: Date; ends_at: Date }>(
      `SELECT starts_at, ends_at FROM bookings
       WHERE schedule_id = $1 AND status = ANY($2::booking_status[])
         AND starts_at < $4 AND ends_at > $3 AND id <> $5`,
      [scheduleId, ACTIVE_STATUSES, from, to, excludeBookingId ?? 0],
    ),
    db.query<{ starts_at: Date; ends_at: Date }>(
      `SELECT starts_at, ends_at FROM closures
       WHERE schedule_id = $1 AND starts_at < $3 AND ends_at > $2`,
      [scheduleId, range.start, range.end],
    ),
  ]);
  return [
    ...bookings.rows.map((b) => ({
      start: addMinutes(b.starts_at, -bufferMinutes),
      end: addMinutes(b.ends_at, bufferMinutes),
    })),
    ...closures.rows.map((c) => ({ start: c.starts_at, end: c.ends_at })),
  ];
}

/**
 * يقسّم الفترات إلى بدايات كل ربع ساعة (أو خطوة الإعدادات) تتسع لمدة الخدمات
 * ولا تتداخل مع وقت مشغول ولا تسبق أقل وقت قبل الحجز.
 */
export function computeSlots(
  periods: Interval[],
  busy: Interval[],
  durationMinutes: number,
  stepMinutes: number,
  earliest: Date,
): Date[] {
  const stepMs = stepMinutes * 60_000;
  const slots: Date[] = [];
  for (const period of periods) {
    // المحاذاة على الساعة: إزاحة بغداد (3 ساعات) من مضاعفات الخطوة
    let t = Math.ceil(period.start.getTime() / stepMs) * stepMs;
    for (; t + durationMinutes * 60_000 <= period.end.getTime(); t += stepMs) {
      if (t < earliest.getTime()) continue;
      const end = t + durationMinutes * 60_000;
      if (busy.some((b) => b.start.getTime() < end && b.end.getTime() > t)) continue;
      slots.push(new Date(t));
    }
  }
  return slots.sort((a, b) => a.getTime() - b.getTime());
}

export interface SlotQuery {
  shop: ShopForBooking;
  durationMinutes: number;
  date: LocalDate;
  now: Date;
  settings: EngineSettings;
  /** عند التحقق من وقت لحجز قائم، لا يُحسب الحجز نفسه مشغولاً */
  excludeBookingId?: number;
}

export async function slotsForDate(db: Queryable, q: SlotQuery): Promise<Date[]> {
  const periods = await workingPeriods(db, q.shop.scheduleId, q.date);
  if (periods.length === 0) return [];
  const range = {
    start: new Date(Math.min(...periods.map((p) => p.start.getTime()))),
    end: new Date(Math.max(...periods.map((p) => p.end.getTime()))),
  };
  const busy = await busyIntervals(db, q.shop.scheduleId, range, q.shop.bufferMinutes, q.excludeBookingId);
  // صاحب المحل يستطيع زيادة أقل وقت قبل الحجز فقط، لا إنقاصه
  const lead = Math.max(q.settings.minLeadMinutes, q.shop.minLeadMinutes);
  return computeSlots(periods, busy, q.durationMinutes, q.settings.slotStepMinutes, addMinutes(q.now, lead));
}

/** هل البداية المطلوبة من الأوقات المتاحة؟ تُفحص فترات اليوم نفسه واليوم السابق (العمل بعد منتصف الليل). */
export async function isSlotAvailable(db: Queryable, q: Omit<SlotQuery, 'date'> & { start: Date }): Promise<boolean> {
  const date = toLocalDate(q.start);
  for (const d of [date, addDays(date, -1)]) {
    const slots = await slotsForDate(db, { ...q, date: d });
    if (slots.some((s) => s.getTime() === q.start.getTime())) return true;
  }
  return false;
}

export async function availableSlots(
  db: Queryable,
  { shopId, serviceIds, date, now }: { shopId: number; serviceIds: number[]; date: LocalDate; now: Date },
): Promise<{ durationMinutes: number; slots: Date[] }> {
  const shop = await loadShop(db, shopId);
  const services = await loadServices(db, shopId, serviceIds);
  const durationMinutes = services.reduce((sum, s) => sum + s.durationMinutes, 0);
  const settings = await loadSettings(db);
  const slots = await slotsForDate(db, { shop, durationMinutes, date, now, settings });
  return { durationMinutes, slots };
}
