import type { Queryable } from '../booking/db.js';
import { addDays, BAGHDAD_OFFSET_MINUTES, startOfLocalDay, toLocalDate } from '../booking/time.js';
import type { Notifier } from './notifier.js';

/** أقصر مهلة يستحق فيها تذكير منتصف المهلة (أقل من ذلك يكفي التذكير الأخير) */
const MIN_WINDOW_FOR_HALF = 20;
/** تذكير الزبون قبل موعده */
const APPOINTMENT_REMINDER_MINUTES = 60;
/** ملخص الصباح لا يُرسل متأخراً (مثلاً إذا أُعيد تشغيل الخادم ظهراً) */
const MORNING_SUMMARY_LATEST_HOUR = 12;

async function numberSetting(db: Queryable, key: string, fallback: number): Promise<number> {
  const { rows } = await db.query('SELECT value FROM settings WHERE key = $1', [key]);
  const v = Number(rows[0]?.value);
  return Number.isFinite(v) ? v : fallback;
}

const minutesLeft = (deadline: Date, now: Date) => Math.max(1, Math.ceil((deadline.getTime() - now.getTime()) / 60_000));

/**
 * تذكيرات المهلة: عند منتصفها، ثم قبل انتهائها بدقائق. المهلة تبدأ من آخر تغيير للحالة.
 * المفتاح يتضمن وقت انتهاء المهلة، فاقتراح جديد يبدأ تذكيرات جديدة، وكل تذكير يُرسل مرة واحدة.
 */
export async function deadlineReminders(db: Queryable, notifier: Notifier, now: Date) {
  const finalMinutes = await numberSetting(db, 'final_deadline_reminder_minutes', 5);
  const { rows } = await db.query(
    `SELECT b.id, b.status, b.updated_at, b.response_deadline, b.customer_id, u.name AS customer_name,
            s.owner_id, s.name AS shop_name
     FROM bookings b JOIN users u ON u.id = b.customer_id JOIN shops s ON s.id = b.shop_id
     WHERE b.status IN ('pending_shop', 'pending_customer') AND b.response_deadline > $1
       AND b.response_deadline <= $1 + interval '1 day'
       AND b.updated_at + (b.response_deadline - b.updated_at) / 2 <= $1`,
    [now],
  );
  let sent = 0;
  for (const b of rows) {
    const deadline: Date = b.response_deadline;
    const windowMinutes = (deadline.getTime() - b.updated_at.getTime()) / 60_000;
    const left = (deadline.getTime() - now.getTime()) / 60_000;
    let stage: 'half' | 'final' | null = null;
    if (left <= finalMinutes && windowMinutes > finalMinutes * 2) stage = 'final';
    else if (left > finalMinutes && windowMinutes >= MIN_WINDOW_FOR_HALF) stage = 'half';
    if (!stage) continue;

    const forShop = b.status === 'pending_shop';
    const type = forShop ? (stage === 'half' ? 'deadline_half' : 'deadline_final') : stage === 'half' ? 'proposal_half' : 'proposal_final';
    const ok = await notifier.notify({
      userId: forShop ? b.owner_id : b.customer_id,
      type,
      bookingId: Number(b.id),
      params: { customer: b.customer_name, shop: b.shop_name, minutes: minutesLeft(deadline, now) },
      dedupeKey: `${type}:${b.id}:${deadline.getTime()}`,
    });
    if (ok) sent++;
  }
  return sent;
}

/** تذكير الزبون قبل موعده بساعة، إلا إذا أُكد الحجز خلال هذه الساعة (وصله إشعار القبول للتو). */
export async function appointmentReminders(db: Queryable, notifier: Notifier, now: Date) {
  const { rows } = await db.query(
    `SELECT b.id, b.starts_at, b.customer_id, s.name AS shop_name
     FROM bookings b JOIN shops s ON s.id = b.shop_id
     WHERE b.status = 'confirmed' AND b.starts_at > $1 AND b.starts_at <= $1 + make_interval(mins => $2)
       AND b.updated_at < b.starts_at - make_interval(mins => $2)`,
    [now, APPOINTMENT_REMINDER_MINUTES],
  );
  let sent = 0;
  for (const b of rows) {
    const ok = await notifier.notify({
      userId: b.customer_id,
      type: 'appointment_reminder',
      bookingId: Number(b.id),
      params: { shop: b.shop_name, startsAt: b.starts_at.toISOString() },
      dedupeKey: `appt:${b.id}:${b.starts_at.getTime()}`,
    });
    if (ok) sent++;
  }
  return sent;
}

/** ملخص الصباح لصاحب المحل: عدد حجوزات اليوم المؤكدة، إذا كان عنده حجز واحد على الأقل. */
export async function morningSummaries(db: Queryable, notifier: Notifier, now: Date) {
  const hour = await numberSetting(db, 'morning_summary_hour', 8);
  const localHour = new Date(now.getTime() + BAGHDAD_OFFSET_MINUTES * 60_000).getUTCHours();
  if (localHour < hour || localHour >= MORNING_SUMMARY_LATEST_HOUR) return 0;
  const today = toLocalDate(now);
  const { rows } = await db.query(
    `SELECT s.owner_id, count(*)::int AS count
     FROM bookings b JOIN shops s ON s.id = b.shop_id
     WHERE s.status = 'approved' AND b.status = 'confirmed' AND b.starts_at >= $1 AND b.starts_at < $2
       AND NOT EXISTS (SELECT 1 FROM notifications n WHERE n.user_id = s.owner_id AND n.dedupe_key = $3)
     GROUP BY s.owner_id`,
    [startOfLocalDay(today), startOfLocalDay(addDays(today, 1)), `morning:${today}`],
  );
  let sent = 0;
  for (const r of rows) {
    const ok = await notifier.notify({
      userId: r.owner_id,
      type: 'morning_summary',
      params: { count: r.count },
      dedupeKey: `morning:${today}`,
    });
    if (ok) sent++;
  }
  return sent;
}
