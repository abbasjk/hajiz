import type { Queryable } from '../booking/db.js';
import type { Notifier } from './notifier.js';
import type { NotificationType } from './texts.js';

/** ما حدث للحجز؛ كل حدث يحدد من يُبلَّغ وبأي إشعار */
export type BookingEvent =
  | 'created'
  | 'accepted'
  | 'rejected'
  | 'proposed'
  | 'customer_chose'
  | 'customer_declined'
  | 'customer_cancelled'
  | 'shop_cancelled'
  | 'closure_moved'
  | 'expired';

interface Context {
  id: number;
  status: string;
  startsAt: Date;
  responseDeadline: Date | null;
  customerId: number;
  customerName: string;
  ownerId: number;
  shopName: string;
  expiredFrom: string | null;
}

async function loadContext(db: Queryable, bookingId: number): Promise<Context | null> {
  const { rows } = await db.query(
    `SELECT b.id, b.status, b.starts_at AS "startsAt", b.response_deadline AS "responseDeadline",
            b.customer_id AS "customerId", u.name AS "customerName",
            s.owner_id AS "ownerId", s.name AS "shopName",
            (SELECT from_status FROM booking_status_history
             WHERE booking_id = b.id AND to_status = 'expired' ORDER BY id DESC LIMIT 1) AS "expiredFrom"
     FROM bookings b JOIN users u ON u.id = b.customer_id JOIN shops s ON s.id = b.shop_id
     WHERE b.id = $1`,
    [bookingId],
  );
  return rows[0] ?? null;
}

const minutesLeft = (deadline: Date | null, now: Date) =>
  deadline ? Math.max(1, Math.ceil((deadline.getTime() - now.getTime()) / 60_000)) : undefined;

export async function bookingEvent(notifier: Notifier, db: Queryable, bookingId: number, event: BookingEvent, now = new Date()) {
  const c = await loadContext(db, bookingId);
  if (!c) return;
  const startsAt = c.startsAt.toISOString();
  const minutes = minutesLeft(c.responseDeadline, now);
  const toShop = (type: NotificationType) =>
    notifier.notify({ userId: c.ownerId, type, bookingId, params: { customer: c.customerName, startsAt, minutes } });
  const toCustomer = (type: NotificationType) =>
    notifier.notify({ userId: c.customerId, type, bookingId, params: { shop: c.shopName, startsAt, minutes } });

  switch (event) {
    case 'created':
      return toShop(c.status === 'confirmed' ? 'new_instant_booking' : 'new_request');
    case 'accepted':
      return toCustomer('accepted');
    case 'rejected':
      return toCustomer('rejected');
    case 'proposed':
      return toCustomer('proposal');
    case 'customer_chose':
      return toShop('customer_chose');
    case 'customer_declined':
      return toShop('customer_declined');
    case 'customer_cancelled':
      return toShop('customer_cancelled');
    case 'shop_cancelled':
      return toCustomer('shop_cancelled');
    case 'closure_moved':
      return toCustomer('closure_proposal');
    case 'expired':
      // المحل لم يرد، أو الزبون لم يختر من الأوقات المقترحة
      return toCustomer(c.expiredFrom === 'pending_customer' ? 'expired_customer' : 'expired_shop');
  }
}
