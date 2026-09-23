import type { Queryable } from '../booking/db.js';
import { addDays, startOfLocalDay, toLocalDate, type LocalDate } from '../booking/time.js';
import { AppError } from '../lib/errors.js';
import type { OwnedShop } from './shop.js';

/**
 * ما يراه صاحب المحل من الحجز. رقم الزبون يظهر فقط ما دام بينهما حجز قائم
 * (بانتظار رد أو مؤكد)، ويُخفى بعد انتهاء الحجز أو إلغائه.
 */
const COLUMNS = `b.id, b.status, b.starts_at AS "startsAt", b.ends_at AS "endsAt",
  b.response_deadline AS "responseDeadline", b.is_instant AS "isInstant", b.customer_note AS note,
  b.modification_message AS "modificationMessage", b.cancel_reason AS "cancelReason",
  b.cancelled_by AS "cancelledBy", b.cancelled_late AS "cancelledLate", b.created_at AS "createdAt",
  json_build_object(
    'id', u.id, 'name', u.name,
    'phone', CASE WHEN b.status IN ('pending_shop', 'pending_customer', 'confirmed') THEN u.phone END,
    -- "رقم مستخدم من جهاز جديد": الجهاز ليس أول جهاز للرقم ولم يُؤكَّد بالاتصال
    'newDevice', d.id IS NOT NULL AND d.verified_by_call_at IS NULL
                 AND d.id <> (SELECT min(id) FROM devices WHERE user_id = u.id)
  ) AS customer,
  (SELECT coalesce(json_agg(json_build_object('name', bs.service_name, 'durationMinutes', bs.duration_minutes,
                                              'priceType', bs.price_type, 'price', bs.price) ORDER BY bs.id), '[]')
   FROM booking_services bs WHERE bs.booking_id = b.id) AS services`;

const FROM = `FROM bookings b JOIN users u ON u.id = b.customer_id LEFT JOIN devices d ON d.id = b.device_id`;

/** لوحة المحل: طلبات تنتظر الرد (الأقرب انتهاءً أولاً) وحجوزات اليوم. */
export async function ownerDashboard(db: Queryable, shop: OwnedShop, now: Date) {
  const today = toLocalDate(now);
  const [pending, day] = await Promise.all([
    db.query(
      `SELECT ${COLUMNS} ${FROM}
       WHERE b.shop_id = $1 AND b.status = 'pending_shop' AND b.response_deadline > $2
       ORDER BY b.response_deadline`,
      [shop.id, now],
    ),
    ownerDay(db, shop, today),
  ]);
  return { pending: pending.rows, today: day, date: today };
}

/** التقويم: حجوزات يوم محلي واحد، دون الملغاة والمرفوضة والمنتهية المهلة. */
export async function ownerDay(db: Queryable, shop: OwnedShop, date: LocalDate) {
  const { rows } = await db.query(
    `SELECT ${COLUMNS} ${FROM}
     WHERE b.shop_id = $1 AND b.starts_at >= $2 AND b.starts_at < $3
       AND b.status IN ('confirmed', 'pending_customer', 'completed', 'no_show')
     ORDER BY b.starts_at`,
    [shop.id, startOfLocalDay(date), startOfLocalDay(addDays(date, 1))],
  );
  return rows;
}

/** تفاصيل الطلب مع سجل التزام الزبون: حضر، ألغى متأخراً، لم يحضر. */
export async function ownerBooking(db: Queryable, shop: OwnedShop, bookingId: number) {
  const { rows } = await db.query(
    `SELECT ${COLUMNS}, u.phone AS raw_phone ${FROM} WHERE b.shop_id = $1 AND b.id = $2`,
    [shop.id, bookingId],
  );
  const row = rows[0];
  if (!row) throw new AppError(404, 'booking_not_found');
  const { raw_phone: phone, ...booking } = row;
  const [stats, proposed] = await Promise.all([
    db.query(
      `SELECT
         (SELECT count(*)::int FROM bookings WHERE customer_id = $1 AND status = 'completed') AS attended,
         (SELECT count(*)::int FROM commitment_events WHERE phone = $2 AND type = 'late_cancel') AS "lateCancels",
         (SELECT count(*)::int FROM commitment_events WHERE phone = $2 AND type = 'no_show') AS "noShows"`,
      [booking.customer.id, phone],
    ),
    db.query(
      'SELECT id, starts_at AS "startsAt", ends_at AS "endsAt" FROM proposed_times WHERE booking_id = $1 ORDER BY starts_at',
      [booking.id],
    ),
  ]);
  return {
    ...booking,
    customer: { ...booking.customer, stats: stats.rows[0] },
    proposedTimes: booking.status === 'pending_customer' ? proposed.rows : [],
  };
}

/** زر "تم التأكد بالاتصال": يصبح جهاز الزبون موثوقاً فتُقبل حجوزاته الفورية لاحقاً. */
export async function verifyCustomerDevice(db: Queryable, shop: OwnedShop, bookingId: number) {
  const { rowCount } = await db.query(
    `UPDATE devices d SET verified_by_call_at = now()
     FROM bookings b WHERE b.id = $2 AND b.shop_id = $1 AND d.id = b.device_id AND d.verified_by_call_at IS NULL`,
    [shop.id, bookingId],
  );
  if (!rowCount) {
    const { rowCount: exists } = await db.query('SELECT 1 FROM bookings WHERE id = $1 AND shop_id = $2', [bookingId, shop.id]);
    if (!exists) throw new AppError(404, 'booking_not_found');
  }
}
