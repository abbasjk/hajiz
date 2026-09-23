import type pg from 'pg';
import type { Pool } from '../db/pool.js';
import { AppError } from '../lib/errors.js';
import { isSlotAvailable, loadServices, loadShop, type ShopForBooking } from './availability.js';
import { responseDeadline } from './deadlines.js';
import { loadSettings } from './settings.js';
import { addMinutes, minutesBetween } from './time.js';
import { isOverlapViolation, withTransaction } from './tx.js';

type Tx = pg.PoolClient;
type Actor = 'customer' | 'shop' | 'system' | 'admin';

export type BookingStatus =
  | 'pending_shop'
  | 'pending_customer'
  | 'confirmed'
  | 'rejected'
  | 'cancelled_by_customer'
  | 'cancelled_by_shop'
  | 'expired'
  | 'completed'
  | 'no_show';

export interface BookingSummary {
  id: number;
  status: BookingStatus;
  startsAt: Date;
  endsAt: Date;
  responseDeadline: Date | null;
  isInstant: boolean;
}

interface LockedBooking extends BookingSummary {
  customerId: number;
  customerPhone: string;
  shopId: number;
  shopOwnerId: number;
  freeCancelHours: number;
}

const SUMMARY_COLUMNS = `id, status, starts_at AS "startsAt", ends_at AS "endsAt",
  response_deadline AS "responseDeadline", is_instant AS "isInstant"`;

async function recordHistory(tx: Tx, bookingId: number, from: BookingStatus | null, to: BookingStatus, actor: Actor) {
  await tx.query(
    `INSERT INTO booking_status_history (booking_id, from_status, to_status, actor) VALUES ($1, $2, $3, $4)`,
    [bookingId, from, to, actor],
  );
}

async function recordCommitmentEvent(tx: Tx, b: LockedBooking, type: 'late_cancel' | 'no_show', now: Date) {
  await tx.query(
    `INSERT INTO commitment_events (phone, type, shop_id, booking_id, occurred_at) VALUES ($1, $2, $3, $4, $5)`,
    [b.customerPhone, type, b.shopId, b.id, now],
  );
}

/**
 * يقفل الحجز للتعديل ويتحقق أن الطرف صاحب الحق فيه.
 * الحجز الذي لا يخص الطرف يُعامل كغير موجود.
 */
async function lockBooking(tx: Tx, bookingId: number, actor: { customerId: number } | { ownerId: number }) {
  const { rows } = await tx.query(
    `SELECT b.id, b.status, b.starts_at AS "startsAt", b.ends_at AS "endsAt",
            b.response_deadline AS "responseDeadline", b.is_instant AS "isInstant",
            b.customer_id AS "customerId", u.phone AS "customerPhone", b.shop_id AS "shopId",
            s.owner_id AS "shopOwnerId", s.free_cancel_hours AS "freeCancelHours"
     FROM bookings b
     JOIN users u ON u.id = b.customer_id
     JOIN shops s ON s.id = b.shop_id
     WHERE b.id = $1
     FOR UPDATE OF b`,
    [bookingId],
  );
  const b = rows[0] as LockedBooking | undefined;
  const allowed = b && ('customerId' in actor ? b.customerId === actor.customerId : b.shopOwnerId === actor.ownerId);
  if (!b || !allowed) throw new AppError(404, 'booking_not_found');
  return b;
}

function requireStatus(b: LockedBooking, ...allowed: BookingStatus[]) {
  if (!allowed.includes(b.status)) throw new AppError(409, 'invalid_transition', { status: b.status });
}

/** طلب انتهت مهلته ولم تلتقطه المهمة التلقائية بعد يُعامل كمنتهٍ. */
function requireNotExpired(b: LockedBooking, now: Date) {
  if (b.responseDeadline && b.responseDeadline.getTime() <= now.getTime()) {
    throw new AppError(409, 'booking_expired');
  }
}

function requireReason(reason: string | undefined): string {
  const r = reason?.trim();
  if (!r) throw new AppError(400, 'reason_required');
  return r;
}

async function updateStatus(
  tx: Tx,
  b: LockedBooking,
  to: BookingStatus,
  actor: Actor,
  now: Date,
  fields: Record<string, unknown> = {},
): Promise<BookingSummary> {
  const entries = Object.entries(fields);
  const sets = entries.map(([col], i) => `${col} = $${i + 4}`);
  const { rows } = await tx.query(
    `UPDATE bookings SET status = $2, updated_at = $3${sets.length ? ', ' + sets.join(', ') : ''}
     WHERE id = $1 RETURNING ${SUMMARY_COLUMNS}`,
    [b.id, to, now, ...entries.map(([, v]) => v)],
  );
  await recordHistory(tx, b.id, b.status, to, actor);
  return rows[0];
}

// ============================================================
// طلب الحجز
// ============================================================

export interface CreateBookingInput {
  customerId: number;
  deviceId: number;
  shopId: number;
  serviceIds: number[];
  startsAt: Date;
  note?: string;
  now: Date;
}

/** الجهاز موثوق إذا كان أول جهاز سُجّل به الرقم، أو أكد صاحب محل الزبون بالاتصال. */
async function isTrustedDevice(tx: Tx, customerId: number, deviceId: number): Promise<boolean> {
  const { rows } = await tx.query<{ trusted: boolean }>(
    `SELECT (d.verified_by_call_at IS NOT NULL
             OR d.id = (SELECT min(id) FROM devices WHERE user_id = $1)) AS trusted
     FROM devices d WHERE d.id = $2 AND d.user_id = $1`,
    [customerId, deviceId],
  );
  if (!rows[0]) throw new AppError(403, 'not_allowed');
  return rows[0].trusted;
}

/** عدم الحضور المتكرر خلال فترة العقوبة يُفقد الزبون الحجز الفوري؛ السجل يُمحى بمرور الوقت. */
async function isPenalized(tx: Tx, phone: string, now: Date, penalty: { count: number; window_days: number }) {
  const { rows } = await tx.query<{ n: number }>(
    `SELECT count(*)::int AS n FROM commitment_events
     WHERE phone = $1 AND type = 'no_show' AND occurred_at > $2::timestamptz - make_interval(days => $3)`,
    [phone, now, penalty.window_days],
  );
  return (rows[0]?.n ?? 0) >= penalty.count;
}

export async function createBooking(pool: Pool, input: CreateBookingInput): Promise<BookingSummary> {
  const { customerId, deviceId, shopId, serviceIds, startsAt, now } = input;
  return withTransaction(pool, async (tx) => {
    // قفل الزبون يجعل فحص حد الطلبات المعلقة آمناً عند طلبين متزامنين
    const customer = await tx.query<{ phone: string; deleted_at: Date | null; banned_at: Date | null }>(
      'SELECT phone, deleted_at, banned_at FROM users WHERE id = $1 FOR UPDATE',
      [customerId],
    );
    const user = customer.rows[0];
    if (!user || user.deleted_at || user.banned_at) throw new AppError(403, 'not_allowed');

    const shop: ShopForBooking = await loadShop(tx, shopId);
    if (shop.ownerId === customerId) throw new AppError(400, 'own_shop');
    const services = await loadServices(tx, shopId, serviceIds);
    const durationMinutes = services.reduce((sum, s) => sum + s.durationMinutes, 0);
    const settings = await loadSettings(tx);

    const available = await isSlotAvailable(tx, { shop, durationMinutes, start: startsAt, now, settings });
    if (!available) throw new AppError(409, 'slot_unavailable');

    const pending = await tx.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM bookings
       WHERE customer_id = $1 AND status IN ('pending_shop', 'pending_customer')`,
      [customerId],
    );
    if ((pending.rows[0]?.n ?? 0) >= settings.maxPendingPerCustomer) {
      throw new AppError(409, 'too_many_pending', { max: settings.maxPendingPerCustomer });
    }

    // الحجز الفوري يتحول إلى حجز بموافقة للجهاز الجديد أو الزبون المعاقب
    const trusted = await isTrustedDevice(tx, customerId, deviceId);
    const instant = shop.instantBooking && trusted
      && !(await isPenalized(tx, user.phone, now, settings.noShowPenalty));

    const endsAt = addMinutes(startsAt, durationMinutes);
    const status: BookingStatus = instant ? 'confirmed' : 'pending_shop';
    const deadline = instant ? null : responseDeadline(now, startsAt, settings.shopDeadlineModes[shop.deadlineMode]);

    let booking: BookingSummary;
    try {
      const { rows } = await tx.query(
        `INSERT INTO bookings (customer_id, shop_id, schedule_id, device_id, starts_at, ends_at, status,
                               customer_note, is_instant, response_deadline, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)
         RETURNING ${SUMMARY_COLUMNS}`,
        [customerId, shopId, shop.scheduleId, deviceId, startsAt, endsAt, status,
          input.note?.trim() || null, instant, deadline, now],
      );
      booking = rows[0];
    } catch (err) {
      if (isOverlapViolation(err)) throw new AppError(409, 'slot_unavailable');
      throw err;
    }

    for (const s of services) {
      await tx.query(
        `INSERT INTO booking_services (booking_id, service_id, service_name, duration_minutes, price_type, price)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [booking.id, s.id, s.name, s.durationMinutes, s.priceType, s.price],
      );
    }
    await recordHistory(tx, booking.id, null, status, 'customer');
    return booking;
  });
}

// ============================================================
// رد صاحب المحل
// ============================================================

interface ShopAction {
  bookingId: number;
  ownerId: number;
  now: Date;
}

export async function acceptBooking(pool: Pool, { bookingId, ownerId, now }: ShopAction) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'pending_shop');
    requireNotExpired(b, now);
    return updateStatus(tx, b, 'confirmed', 'shop', now, { response_deadline: null });
  });
}

/** رفض مباشر دون اقتراح بديل، مع اختيار سبب. */
export async function rejectBooking(pool: Pool, { bookingId, ownerId, now, reason }: ShopAction & { reason: string }) {
  const r = requireReason(reason);
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'pending_shop');
    requireNotExpired(b, now);
    return updateStatus(tx, b, 'rejected', 'shop', now, {
      response_deadline: null,
      cancel_reason: r,
      cancelled_by: 'shop',
    });
  });
}

/**
 * صاحب المحل يقترح وقتين أو ثلاثة بديلة مع رسالة اختيارية.
 * الأوقات المقترحة لا تُقفل، والوقت الأصلي يبقى محجوزاً حتى يرد الزبون.
 */
export async function proposeTimes(
  pool: Pool,
  { bookingId, ownerId, now, times, message }: ShopAction & { times: Date[]; message?: string },
) {
  const distinct = new Set(times.map((t) => t.getTime()));
  if (times.length < 2 || times.length > 3 || distinct.size !== times.length) {
    throw new AppError(400, 'invalid_proposal');
  }
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'pending_shop');
    requireNotExpired(b, now);
    if (distinct.has(b.startsAt.getTime())) throw new AppError(400, 'invalid_proposal');

    const shop = await loadShop(tx, b.shopId);
    const settings = await loadSettings(tx);
    const durationMinutes = minutesBetween(b.startsAt, b.endsAt);
    for (const start of times) {
      const ok = await isSlotAvailable(tx, { shop, durationMinutes, start, now, settings, excludeBookingId: b.id });
      if (!ok) throw new AppError(409, 'slot_unavailable', { startsAt: start.toISOString() });
    }

    const earliest = new Date(Math.min(...times.map((t) => t.getTime())));
    const cap = new Date(Math.min(earliest.getTime(), b.startsAt.getTime()));
    const deadline = responseDeadline(now, earliest, settings.customerDeadline, cap);

    for (const start of [...times].sort((x, y) => x.getTime() - y.getTime())) {
      await tx.query(`INSERT INTO proposed_times (booking_id, starts_at, ends_at) VALUES ($1, $2, $3)`, [
        b.id, start, addMinutes(start, durationMinutes),
      ]);
    }
    return updateStatus(tx, b, 'pending_customer', 'shop', now, {
      response_deadline: deadline,
      modification_message: message?.trim() || null,
    });
  });
}

/** إلغاء حجز مؤكد من صاحب المحل، مع سبب من قائمة قصيرة. */
export async function cancelByShop(pool: Pool, { bookingId, ownerId, now, reason }: ShopAction & { reason: string }) {
  const r = requireReason(reason);
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'confirmed');
    if (now.getTime() >= b.startsAt.getTime()) throw new AppError(409, 'invalid_transition', { status: b.status });
    return updateStatus(tx, b, 'cancelled_by_shop', 'shop', now, { cancel_reason: r, cancelled_by: 'shop' });
  });
}

/** لا يُسجل الغياب إلا بعد مرور وقت الموعد. */
export async function markNoShow(pool: Pool, { bookingId, ownerId, now }: ShopAction) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'confirmed');
    if (now.getTime() < b.startsAt.getTime()) throw new AppError(409, 'too_early');
    const result = await updateStatus(tx, b, 'no_show', 'shop', now);
    await recordCommitmentEvent(tx, b, 'no_show', now);
    return result;
  });
}

export async function markCompleted(pool: Pool, { bookingId, ownerId, now }: ShopAction) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { ownerId });
    requireStatus(b, 'confirmed');
    if (now.getTime() < b.startsAt.getTime()) throw new AppError(409, 'too_early');
    return updateStatus(tx, b, 'completed', 'shop', now);
  });
}

// ============================================================
// رد الزبون وإلغاؤه
// ============================================================

interface CustomerAction {
  bookingId: number;
  customerId: number;
  now: Date;
}

/** من يسبق يأخذ: إذا أُخذ الوقت المقترح يبقى الطلب بانتظار الزبون ليختار غيره. */
export async function chooseProposedTime(
  pool: Pool,
  { bookingId, customerId, now, proposedTimeId }: CustomerAction & { proposedTimeId: number },
) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { customerId });
    requireStatus(b, 'pending_customer');
    requireNotExpired(b, now);
    const { rows } = await tx.query<{ starts_at: Date; ends_at: Date }>(
      'SELECT starts_at, ends_at FROM proposed_times WHERE id = $1 AND booking_id = $2',
      [proposedTimeId, b.id],
    );
    const proposed = rows[0];
    if (!proposed) throw new AppError(404, 'proposed_time_not_found');

    const shop = await loadShop(tx, b.shopId);
    const settings = await loadSettings(tx);
    const ok = await isSlotAvailable(tx, {
      shop,
      durationMinutes: minutesBetween(proposed.starts_at, proposed.ends_at),
      start: proposed.starts_at,
      now,
      settings,
      excludeBookingId: b.id,
    });
    if (!ok) throw new AppError(409, 'time_no_longer_available');
    try {
      return await updateStatus(tx, b, 'confirmed', 'customer', now, {
        starts_at: proposed.starts_at,
        ends_at: proposed.ends_at,
        response_deadline: null,
      });
    } catch (err) {
      if (isOverlapViolation(err)) throw new AppError(409, 'time_no_longer_available');
      throw err;
    }
  });
}

/** رفض الأوقات المقترحة يلغي الحجز، ولا يُسجل على الزبون. */
export async function declineProposal(pool: Pool, { bookingId, customerId, now }: CustomerAction) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { customerId });
    requireStatus(b, 'pending_customer');
    return updateStatus(tx, b, 'cancelled_by_customer', 'customer', now, {
      response_deadline: null,
      cancelled_by: 'customer',
      cancelled_late: false,
    });
  });
}

/**
 * الإلغاء مسموح للزبون دائماً قبل الموعد. إلغاء حجز مؤكد قبل أقل من حد الإلغاء المجاني
 * يُسجل في سجل الالتزام.
 */
export async function cancelByCustomer(pool: Pool, { bookingId, customerId, now }: CustomerAction) {
  return withTransaction(pool, async (tx) => {
    const b = await lockBooking(tx, bookingId, { customerId });
    requireStatus(b, 'pending_shop', 'pending_customer', 'confirmed');
    if (now.getTime() >= b.startsAt.getTime()) throw new AppError(409, 'invalid_transition', { status: b.status });
    const late = b.status === 'confirmed' && minutesBetween(now, b.startsAt) < b.freeCancelHours * 60;
    const result = await updateStatus(tx, b, 'cancelled_by_customer', 'customer', now, {
      response_deadline: null,
      cancelled_by: 'customer',
      cancelled_late: late,
    });
    if (late) await recordCommitmentEvent(tx, b, 'late_cancel', now);
    return result;
  });
}
