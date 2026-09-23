import type { Pool } from '../db/pool.js';
import type { AuthContext } from '../auth/devices.js';
import { isSlotAvailable, loadShop } from './availability.js';
import { loadSettings } from './settings.js';
import { minutesBetween } from './time.js';

/**
 * ما يراه الزبون من حجوزاته. من جهاز غير موثوق (الرقم نفسه من جهاز آخر)
 * لا تظهر إلا الحجوزات التي أُرسلت من هذا الجهاز.
 */
const VISIBLE = `b.customer_id = $1 AND ($2::boolean OR b.device_id = $3)`;

const COLUMNS = `b.id, b.status, b.starts_at AS "startsAt", b.ends_at AS "endsAt",
  b.response_deadline AS "responseDeadline", b.is_instant AS "isInstant", b.customer_note AS note,
  b.modification_message AS "modificationMessage", b.cancel_reason AS "cancelReason",
  b.cancelled_by AS "cancelledBy", b.cancelled_late AS "cancelledLate", b.created_at AS "createdAt",
  json_build_object('id', s.id, 'name', s.name, 'phone', s.phone,
                    'latitude', s.latitude, 'longitude', s.longitude,
                    'freeCancelHours', s.free_cancel_hours) AS shop,
  (SELECT coalesce(json_agg(json_build_object('name', bs.service_name, 'durationMinutes', bs.duration_minutes,
                                              'priceType', bs.price_type, 'price', bs.price) ORDER BY bs.id), '[]')
   FROM booking_services bs WHERE bs.booking_id = b.id) AS services`;

export async function listCustomerBookings(pool: Pool, auth: AuthContext) {
  const { rows } = await pool.query(
    `SELECT ${COLUMNS} FROM bookings b JOIN shops s ON s.id = b.shop_id
     WHERE ${VISIBLE} ORDER BY b.starts_at DESC LIMIT 100`,
    [auth.userId, auth.trusted, auth.deviceId],
  );
  return rows;
}

export async function getCustomerBooking(pool: Pool, auth: AuthContext, bookingId: number) {
  const { rows } = await pool.query(
    `SELECT ${COLUMNS}, b.shop_id FROM bookings b JOIN shops s ON s.id = b.shop_id
     WHERE ${VISIBLE} AND b.id = $4`,
    [auth.userId, auth.trusted, auth.deviceId, bookingId],
  );
  const row = rows[0];
  if (!row) return null;
  const { shop_id: shopId, ...booking } = row;

  let proposedTimes: { id: number; startsAt: Date; endsAt: Date; available: boolean }[] = [];
  if (booking.status === 'pending_customer') {
    const { rows: times } = await pool.query(
      'SELECT id, starts_at AS "startsAt", ends_at AS "endsAt" FROM proposed_times WHERE booking_id = $1 ORDER BY starts_at',
      [booking.id],
    );
    const shop = await loadShop(pool, shopId);
    const settings = await loadSettings(pool);
    const now = new Date();
    // الأوقات المقترحة لا تُقفل: ما أخذه غيره يظهر "لم يعد متاحاً"
    proposedTimes = await Promise.all(times.map(async (t) => ({
      ...t,
      available: await isSlotAvailable(pool, {
        shop, durationMinutes: minutesBetween(t.startsAt, t.endsAt), start: t.startsAt, now, settings,
        excludeBookingId: booking.id,
      }),
    })));
  }
  return { ...booking, proposedTimes };
}
