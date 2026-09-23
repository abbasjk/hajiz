import type { FastifyBaseLogger } from 'fastify';
import type { Pool } from '../db/pool.js';
import { bookingEvent } from '../notify/events.js';
import type { Notifier } from '../notify/notifier.js';
import { appointmentReminders, deadlineReminders, morningSummaries } from '../notify/reminders.js';
import { loadSettings } from './settings.js';

/**
 * كل طلب له وقت محدد للرد؛ إذا انتهى يُلغى ويعود الموعد متاحاً.
 * SKIP LOCKED يسمح بتشغيل المهمة من عدة نسخ من الخادم دون تكرار.
 * تعيد أرقام الحجوزات المنتهية لإبلاغ الزبون.
 */
export async function expireOverdue(pool: Pool, now: Date): Promise<number[]> {
  const { rows } = await pool.query<{ booking_id: number }>(
    `WITH due AS (
       SELECT id, status FROM bookings
       WHERE status IN ('pending_shop', 'pending_customer') AND response_deadline <= $1
       FOR UPDATE SKIP LOCKED
     ), expired AS (
       UPDATE bookings b SET status = 'expired', cancelled_by = 'system', updated_at = $1
       FROM due WHERE b.id = due.id
       RETURNING b.id, due.status AS from_status
     )
     INSERT INTO booking_status_history (booking_id, from_status, to_status, actor)
     SELECT id, from_status, 'expired', 'system' FROM expired
     RETURNING booking_id`,
    [now],
  );
  return rows.map((r) => r.booking_id);
}

/** الحجز يُعتبر مكتملاً بعد مدة من انتهاء الموعد إذا لم يسجل صاحب المحل شيئاً. */
export async function autoComplete(pool: Pool, now: Date): Promise<number[]> {
  const { autoCompleteAfterMinutes } = await loadSettings(pool);
  const { rows } = await pool.query<{ booking_id: number }>(
    `WITH due AS (
       SELECT id FROM bookings
       WHERE status = 'confirmed' AND ends_at + make_interval(mins => $2) <= $1
       FOR UPDATE SKIP LOCKED
     ), done AS (
       UPDATE bookings b SET status = 'completed', updated_at = $1
       FROM due WHERE b.id = due.id
       RETURNING b.id
     )
     INSERT INTO booking_status_history (booking_id, from_status, to_status, actor)
     SELECT id, 'confirmed', 'completed', 'system' FROM done
     RETURNING booking_id`,
    [now, autoCompleteAfterMinutes],
  );
  return rows.map((r) => r.booking_id);
}

export async function runMinuteJobs(pool: Pool, now = new Date(), notifier?: Notifier) {
  const expired = await expireOverdue(pool, now);
  const completed = await autoComplete(pool, now);
  let reminders = 0;
  if (notifier) {
    for (const id of expired) await bookingEvent(notifier, pool, id, 'expired', now);
    reminders += await deadlineReminders(pool, notifier, now);
    reminders += await appointmentReminders(pool, notifier, now);
    reminders += await morningSummaries(pool, notifier, now);
  }
  return { expired, completed, reminders };
}

/** يشغّل المهام كل دقيقة؛ يعيد دالة لإيقافها عند إغلاق الخادم. */
export function startScheduler(pool: Pool, log: FastifyBaseLogger, notifier?: Notifier, intervalMs = 60_000): () => void {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      const { expired, completed, reminders } = await runMinuteJobs(pool, new Date(), notifier);
      if (expired.length || completed.length || reminders) log.info({ expired, completed, reminders }, 'booking jobs');
    } catch (err) {
      log.error(err, 'booking jobs failed');
    } finally {
      running = false;
    }
  };
  const timer = setInterval(tick, intervalMs);
  void tick();
  return () => clearInterval(timer);
}
