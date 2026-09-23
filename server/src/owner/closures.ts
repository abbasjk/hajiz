import type { Pool } from '../db/pool.js';
import { ACTIVE_STATUSES, loadShop, slotsForDate } from '../booking/availability.js';
import { responseDeadline } from '../booking/deadlines.js';
import { loadSettings } from '../booking/settings.js';
import { addDays, addMinutes, minutesBetween, toLocalDate } from '../booking/time.js';
import { withTransaction } from '../booking/tx.js';
import { AppError } from '../lib/errors.js';
import { requireShop } from './shop.js';

const SEARCH_DAYS = 7;
const MAX_ALTERNATIVES = 3;
/** أقل مهلة تُعطى للزبون ليختار بديلاً؛ إذا لم تتسع يُلغى الحجز مباشرة */
const MIN_CUSTOMER_MINUTES = 5;

export const CLOSURE_REASON = 'emergency_closure';

/**
 * الإغلاق الطارئ: يغلق يوماً أو ساعات، وكل حجز نشط داخل الإغلاق يُعرض على صاحبه
 * بأقرب ثلاثة أوقات بديلة (بانتظار رد الزبون). إذا لم يوجد بديل خلال أسبوع
 * أو كان الموعد قريباً جداً يُلغى الحجز من المحل.
 */
export async function createClosure(
  pool: Pool,
  ownerId: number,
  input: { startsAt: Date; endsAt: Date; reason?: string; now: Date },
) {
  const { startsAt, endsAt, now } = input;
  if (!(endsAt > startsAt) || endsAt <= now || minutesBetween(startsAt, endsAt) > 60 * 24 * 60) {
    throw new AppError(400, 'invalid_closure');
  }
  return withTransaction(pool, async (tx) => {
    const owned = await requireShop(tx, ownerId, { lock: true });
    if (owned.status !== 'approved') throw new AppError(409, 'shop_not_approved');
    const { rows: [closure] } = await tx.query(
      'INSERT INTO closures (schedule_id, starts_at, ends_at, reason) VALUES ($1, $2, $3, $4) RETURNING id',
      [owned.scheduleId, startsAt, endsAt, input.reason?.trim() || null],
    );

    const { rows: affected } = await tx.query<{ id: number; status: string; starts_at: Date; ends_at: Date }>(
      `SELECT id, status, starts_at, ends_at FROM bookings
       WHERE schedule_id = $1 AND status = ANY($2::booking_status[]) AND starts_at < $4 AND ends_at > $3
       ORDER BY starts_at FOR UPDATE`,
      [owned.scheduleId, ACTIVE_STATUSES, startsAt, endsAt],
    );

    const shop = await loadShop(tx, owned.id);
    const settings = await loadSettings(tx);
    const moved: number[] = [];
    const cancelled: number[] = [];

    for (const b of affected) {
      const duration = minutesBetween(b.starts_at, b.ends_at);
      const alternatives: Date[] = [];
      const first = toLocalDate(now);
      for (let i = 0; i < SEARCH_DAYS && alternatives.length < MAX_ALTERNATIVES; i++) {
        const slots = await slotsForDate(tx, {
          shop, durationMinutes: duration, date: addDays(first, i), now, settings, excludeBookingId: b.id,
        });
        // الحجز نفسه يشغل وقته داخل الإغلاق، والإغلاق مسجّل قبل البحث فلا تظهر أوقاته
        alternatives.push(...slots.slice(0, MAX_ALTERNATIVES - alternatives.length));
      }
      const earliest = alternatives[0];
      const cap = earliest && new Date(Math.min(earliest.getTime(), b.starts_at.getTime()));
      const canMove = earliest && cap && minutesBetween(now, cap) >= MIN_CUSTOMER_MINUTES;

      if (canMove) {
        await tx.query('DELETE FROM proposed_times WHERE booking_id = $1', [b.id]);
        for (const t of alternatives) {
          await tx.query('INSERT INTO proposed_times (booking_id, starts_at, ends_at) VALUES ($1, $2, $3)', [
            b.id, t, addMinutes(t, duration),
          ]);
        }
        await tx.query(
          `UPDATE bookings SET status = 'pending_customer', response_deadline = $2, cancel_reason = $3,
                               modification_message = NULL, updated_at = $4 WHERE id = $1`,
          [b.id, responseDeadline(now, earliest, settings.customerDeadline, cap), CLOSURE_REASON, now],
        );
        await tx.query(
          `INSERT INTO booking_status_history (booking_id, from_status, to_status, actor) VALUES ($1, $2, 'pending_customer', 'shop')`,
          [b.id, b.status],
        );
        moved.push(b.id);
      } else {
        await tx.query(
          `UPDATE bookings SET status = 'cancelled_by_shop', cancelled_by = 'shop', cancel_reason = $2,
                               response_deadline = NULL, updated_at = $3 WHERE id = $1`,
          [b.id, CLOSURE_REASON, now],
        );
        await tx.query(
          `INSERT INTO booking_status_history (booking_id, from_status, to_status, actor) VALUES ($1, $2, 'cancelled_by_shop', 'shop')`,
          [b.id, b.status],
        );
        cancelled.push(b.id);
      }
    }
    return { closureId: closure.id as number, moved, cancelled };
  });
}

/** حذف إغلاق لم ينتهِ بعد؛ الحجوزات التي نُقلت أو أُلغيت لا تعود. */
export async function deleteClosure(pool: Pool, ownerId: number, closureId: number) {
  const shop = await requireShop(pool, ownerId);
  const { rowCount } = await pool.query('DELETE FROM closures WHERE id = $1 AND schedule_id = $2 AND ends_at > now()', [
    closureId, shop.scheduleId,
  ]);
  if (!rowCount) throw new AppError(404, 'closure_not_found');
}
