import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  acceptBooking,
  cancelByCustomer,
  cancelByShop,
  chooseProposedTime,
  createBooking,
  declineProposal,
  markCompleted,
  markNoShow,
  proposeTimes,
  rejectBooking,
} from '../src/booking/bookings.js';
import { availableSlots } from '../src/booking/availability.js';
import { autoComplete, expireOverdue } from '../src/booking/jobs.js';
import type { Pool } from '../src/db/pool.js';
import { addDevice, createShop, createUser, local, MONDAY, resetBookings, type ShopFixture } from './fixtures.js';
import { freshDatabase } from './helpers.js';

let pool: Pool;
let shop: ShopFixture;
let instantShop: ShopFixture;
let customer: { userId: number; deviceId: number; phone: string };

// الأحد 10:00 صباحاً، ومواعيد الاختبار يوم الاثنين (غداً)
const NOW = local('2026-10-04', '10:00');

beforeAll(async () => {
  pool = await freshDatabase();
  shop = await createShop(pool);
  instantShop = await createShop(pool, { instantBooking: true });
  customer = await createUser(pool);
});

beforeEach(async () => {
  await resetBookings(pool);
});

afterAll(async () => {
  await pool.end();
});

function book(time: string, overrides: Partial<Parameters<typeof createBooking>[1]> = {}) {
  return createBooking(pool, {
    customerId: customer.userId,
    deviceId: customer.deviceId,
    shopId: shop.shopId,
    serviceIds: [shop.haircut],
    startsAt: local(MONDAY, time),
    now: NOW,
    ...overrides,
  });
}

const owner = () => ({ ownerId: shop.ownerId });
const asCustomer = () => ({ customerId: customer.userId });

async function status(bookingId: number) {
  const { rows } = await pool.query('SELECT status FROM bookings WHERE id = $1', [bookingId]);
  return rows[0].status;
}

async function commitmentEvents(phone = customer.phone) {
  const { rows } = await pool.query('SELECT type FROM commitment_events WHERE phone = $1', [phone]);
  return rows.map((r) => r.type);
}

describe('creating a booking request', () => {
  it('waits for the shop, with the normal deadline for tomorrow (1 hour)', async () => {
    const b = await book('10:00');
    expect(b.status).toBe('pending_shop');
    expect(b.isInstant).toBe(false);
    expect(b.responseDeadline).toEqual(local('2026-10-04', '11:00'));
    expect(b.endsAt).toEqual(local(MONDAY, '10:30'));
  });

  it('uses the shop deadline mode', async () => {
    await pool.query(`UPDATE shops SET deadline_mode = 'fast' WHERE id = $1`, [shop.shopId]);
    const b = await book('10:00');
    await pool.query(`UPDATE shops SET deadline_mode = 'normal' WHERE id = $1`, [shop.shopId]);
    expect(b.responseDeadline).toEqual(local('2026-10-04', '10:30'));
  });

  it('locks the time for everyone else', async () => {
    await book('10:00');
    const other = await createUser(pool);
    await expect(
      book('10:15', { customerId: other.userId, deviceId: other.deviceId }),
    ).rejects.toMatchObject({ code: 'slot_unavailable' });
  });

  it('gives the time to only one of two simultaneous requests', async () => {
    const others = await Promise.all([createUser(pool), createUser(pool), createUser(pool)]);
    const results = await Promise.allSettled(
      others.map((o) => book('10:00', { customerId: o.userId, deviceId: o.deviceId })),
    );
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    for (const r of results.filter((r) => r.status === 'rejected')) {
      expect((r as PromiseRejectedResult).reason).toMatchObject({ code: 'slot_unavailable' });
    }
  });

  it('holds the pending limit under simultaneous requests', async () => {
    const results = await Promise.allSettled(['09:00', '10:00', '11:00', '16:00'].map((t) => book(t)));
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(2);
  });

  it('refuses a time that is not one of the available slots', async () => {
    await expect(book('10:05')).rejects.toMatchObject({ code: 'slot_unavailable' });
    await expect(book('13:00')).rejects.toMatchObject({ code: 'slot_unavailable' }); // الاستراحة
  });

  it('allows at most 2 pending requests per customer', async () => {
    await book('09:00');
    await book('10:00');
    await expect(book('11:00')).rejects.toMatchObject({ code: 'too_many_pending' });
  });

  it('does not let an owner book at their own shop', async () => {
    const { rows } = await pool.query('SELECT id FROM devices WHERE user_id = $1', [shop.ownerId]);
    await expect(
      book('10:00', { customerId: shop.ownerId, deviceId: rows[0].id }),
    ).rejects.toMatchObject({ code: 'own_shop' });
  });

  it('saves service names, durations and prices inside the booking', async () => {
    const b = await book('10:00', { serviceIds: [shop.haircut, shop.beard] });
    await pool.query('UPDATE services SET price = 99999 WHERE id = $1', [shop.haircut]);
    const { rows } = await pool.query(
      'SELECT service_name, duration_minutes, price FROM booking_services WHERE booking_id = $1 ORDER BY id',
      [b.id],
    );
    await pool.query('UPDATE services SET price = 10000 WHERE id = $1', [shop.haircut]);
    expect(rows).toEqual([
      { service_name: 'حلاقة', duration_minutes: 30, price: 10000 },
      { service_name: 'لحية', duration_minutes: 15, price: 5000 },
    ]);
    expect(b.endsAt).toEqual(local(MONDAY, '10:45'));
  });

  it('writes the first status into the history', async () => {
    const b = await book('10:00');
    const { rows } = await pool.query('SELECT from_status, to_status, actor FROM booking_status_history WHERE booking_id = $1', [b.id]);
    expect(rows).toEqual([{ from_status: null, to_status: 'pending_shop', actor: 'customer' }]);
  });
});

describe('instant booking', () => {
  const bookInstant = (time: string, deviceId = customer.deviceId) =>
    book(time, { shopId: instantShop.shopId, serviceIds: [instantShop.haircut], deviceId });

  it('confirms right away from the device the number registered with', async () => {
    const b = await bookInstant('10:00');
    expect(b.status).toBe('confirmed');
    expect(b.isInstant).toBe(true);
    expect(b.responseDeadline).toBeNull();
  });

  it('needs approval from a new device until the shop confirms by phone', async () => {
    const newDevice = await addDevice(pool, customer.userId);
    expect((await bookInstant('10:00', newDevice)).status).toBe('pending_shop');
    await pool.query('UPDATE devices SET verified_by_call_at = now() WHERE id = $1', [newDevice]);
    expect((await bookInstant('11:00', newDevice)).status).toBe('confirmed');
  });

  it('needs approval after 3 no-shows in 90 days, and the penalty fades with time', async () => {
    const insertNoShow = (daysAgo: number) =>
      pool.query(
        `INSERT INTO commitment_events (phone, type, occurred_at) VALUES ($1, 'no_show', $2::timestamptz - make_interval(days => $3))`,
        [customer.phone, NOW, daysAgo],
      );
    await insertNoShow(10);
    await insertNoShow(20);
    await insertNoShow(100); // خارج فترة العقوبة
    expect((await bookInstant('09:00')).status).toBe('confirmed');
    await insertNoShow(30);
    expect((await bookInstant('10:00')).status).toBe('pending_shop');
  });
});

describe('shop response', () => {
  it('accepts a pending request', async () => {
    const b = await book('10:00');
    const r = await acceptBooking(pool, { bookingId: b.id, ...owner(), now: NOW });
    expect(r.status).toBe('confirmed');
    expect(r.responseDeadline).toBeNull();
  });

  it('cannot accept after the deadline, even before the job runs', async () => {
    const b = await book('10:00');
    await expect(
      acceptBooking(pool, { bookingId: b.id, ...owner(), now: local('2026-10-04', '11:00') }),
    ).rejects.toMatchObject({ code: 'booking_expired' });
  });

  it('hides bookings of other shops', async () => {
    const b = await book('10:00');
    await expect(
      acceptBooking(pool, { bookingId: b.id, ownerId: instantShop.ownerId, now: NOW }),
    ).rejects.toMatchObject({ code: 'booking_not_found' });
  });

  it('rejects with a reason and frees the time', async () => {
    const b = await book('10:00');
    await expect(rejectBooking(pool, { bookingId: b.id, ...owner(), now: NOW, reason: ' ' })).rejects.toMatchObject({
      code: 'reason_required',
    });
    expect((await rejectBooking(pool, { bookingId: b.id, ...owner(), now: NOW, reason: 'مشغول' })).status).toBe('rejected');
    await expect(book('10:00')).resolves.toBeDefined();
  });
});

describe('proposing other times', () => {
  const propose = (bookingId: number, times: string[], now = NOW) =>
    proposeTimes(pool, { bookingId, ...owner(), now, times: times.map((t) => local(MONDAY, t)), message: 'آسف' });

  async function proposedIds(bookingId: number) {
    const { rows } = await pool.query('SELECT id FROM proposed_times WHERE booking_id = $1 ORDER BY starts_at', [bookingId]);
    return rows.map((r) => r.id as number);
  }

  it('requires two or three different times', async () => {
    const b = await book('10:00');
    await expect(propose(b.id, ['11:00'])).rejects.toMatchObject({ code: 'invalid_proposal' });
    await expect(propose(b.id, ['11:00', '11:00'])).rejects.toMatchObject({ code: 'invalid_proposal' });
    await expect(propose(b.id, ['09:00', '09:30', '11:00', '11:30'])).rejects.toMatchObject({ code: 'invalid_proposal' });
  });

  it('only proposes available times', async () => {
    const b = await book('10:00');
    await expect(propose(b.id, ['11:00', '13:00'])).rejects.toMatchObject({ code: 'slot_unavailable' });
  });

  it('waits for the customer, with the fixed customer deadline, and keeps the original time', async () => {
    const b = await book('10:00');
    const r = await propose(b.id, ['11:00', '16:00']);
    expect(r.status).toBe('pending_customer');
    expect(r.responseDeadline).toEqual(local('2026-10-04', '11:00'));
    const { rows } = await pool.query('SELECT modification_message FROM bookings WHERE id = $1', [b.id]);
    expect(rows[0].modification_message).toBe('آسف');
    const monday = await availableSlots(pool, { shopId: shop.shopId, serviceIds: [shop.haircut], date: MONDAY, now: NOW });
    expect(monday.slots).not.toContainEqual(local(MONDAY, '10:00'));
    expect(monday.slots).toContainEqual(local(MONDAY, '11:00')); // المقترح لا يُقفل
  });

  it('confirms the chosen time and frees the original one', async () => {
    const b = await book('10:00');
    await propose(b.id, ['11:00', '16:00']);
    const [first] = await proposedIds(b.id);
    const r = await chooseProposedTime(pool, { bookingId: b.id, ...asCustomer(), now: NOW, proposedTimeId: first! });
    expect(r.status).toBe('confirmed');
    expect(r.startsAt).toEqual(local(MONDAY, '11:00'));
    const other = await createUser(pool);
    await expect(book('10:00', { customerId: other.userId, deviceId: other.deviceId })).resolves.toBeDefined();
  });

  it('first come first served: a taken proposal leaves the request open', async () => {
    const b = await book('10:00');
    await propose(b.id, ['11:00', '16:00']);
    const other = await createUser(pool);
    await book('11:00', { customerId: other.userId, deviceId: other.deviceId });
    const [first, second] = await proposedIds(b.id);
    await expect(
      chooseProposedTime(pool, { bookingId: b.id, ...asCustomer(), now: NOW, proposedTimeId: first! }),
    ).rejects.toMatchObject({ code: 'time_no_longer_available' });
    expect(await status(b.id)).toBe('pending_customer');
    const r = await chooseProposedTime(pool, { bookingId: b.id, ...asCustomer(), now: NOW, proposedTimeId: second! });
    expect(r.startsAt).toEqual(local(MONDAY, '16:00'));
  });

  it('declining cancels the booking without a mark on the customer', async () => {
    const b = await book('10:00');
    await propose(b.id, ['11:00', '16:00']);
    expect((await declineProposal(pool, { bookingId: b.id, ...asCustomer(), now: NOW })).status).toBe(
      'cancelled_by_customer',
    );
    expect(await commitmentEvents()).toEqual([]);
  });
});

describe('cancellation and commitment record', () => {
  async function confirmed(time: string) {
    const b = await book(time);
    await acceptBooking(pool, { bookingId: b.id, ...owner(), now: NOW });
    return b;
  }

  it('early cancellation is free and not recorded', async () => {
    const b = await confirmed('10:00');
    const r = await cancelByCustomer(pool, { bookingId: b.id, ...asCustomer(), now: local(MONDAY, '07:59') });
    expect(r.status).toBe('cancelled_by_customer');
    expect(await commitmentEvents()).toEqual([]);
  });

  it('late cancellation is allowed but recorded', async () => {
    const b = await confirmed('10:00');
    await cancelByCustomer(pool, { bookingId: b.id, ...asCustomer(), now: local(MONDAY, '08:30') });
    const { rows } = await pool.query('SELECT cancelled_late FROM bookings WHERE id = $1', [b.id]);
    expect(rows[0].cancelled_late).toBe(true);
    expect(await commitmentEvents()).toEqual(['late_cancel']);
  });

  it('uses the shop free-cancellation limit', async () => {
    await pool.query('UPDATE shops SET free_cancel_hours = 24 WHERE id = $1', [shop.shopId]);
    const b = await confirmed('10:00');
    await cancelByCustomer(pool, { bookingId: b.id, ...asCustomer(), now: local('2026-10-04', '12:00') });
    await pool.query('UPDATE shops SET free_cancel_hours = 2 WHERE id = $1', [shop.shopId]);
    expect(await commitmentEvents()).toEqual(['late_cancel']);
  });

  it('cancelling a pending request is never late', async () => {
    const b = await book('10:00');
    await cancelByCustomer(pool, { bookingId: b.id, ...asCustomer(), now: NOW });
    expect(await commitmentEvents()).toEqual([]);
  });

  it('the shop cancels with a reason', async () => {
    const b = await confirmed('10:00');
    const r = await cancelByShop(pool, { bookingId: b.id, ...owner(), now: NOW, reason: 'إغلاق طارئ' });
    expect(r.status).toBe('cancelled_by_shop');
  });

  it('no-show only after the appointment time, and it is recorded', async () => {
    const b = await confirmed('10:00');
    await expect(markNoShow(pool, { bookingId: b.id, ...owner(), now: local(MONDAY, '09:59') })).rejects.toMatchObject({
      code: 'too_early',
    });
    expect((await markNoShow(pool, { bookingId: b.id, ...owner(), now: local(MONDAY, '10:20') })).status).toBe('no_show');
    expect(await commitmentEvents()).toEqual(['no_show']);
  });

  it('the shop marks a booking completed', async () => {
    const b = await confirmed('10:00');
    expect((await markCompleted(pool, { bookingId: b.id, ...owner(), now: local(MONDAY, '10:30') })).status).toBe('completed');
  });
});

describe('automatic jobs', () => {
  it('expires requests past their deadline and frees the time', async () => {
    const b = await book('10:00');
    expect(await expireOverdue(pool, local('2026-10-04', '10:59'))).toEqual([]);
    expect(await expireOverdue(pool, local('2026-10-04', '11:00'))).toEqual([b.id]);
    expect(await status(b.id)).toBe('expired');
    const { rows } = await pool.query(
      `SELECT from_status, to_status, actor FROM booking_status_history WHERE booking_id = $1 ORDER BY id DESC LIMIT 1`,
      [b.id],
    );
    expect(rows[0]).toEqual({ from_status: 'pending_shop', to_status: 'expired', actor: 'system' });
    await expect(book('10:00')).resolves.toBeDefined();
  });

  it('expires a proposal the customer did not answer', async () => {
    const b = await book('10:00');
    const r = await proposeTimes(pool, {
      bookingId: b.id, ...owner(), now: NOW, times: [local(MONDAY, '11:00'), local(MONDAY, '16:00')],
    });
    expect(await expireOverdue(pool, r.responseDeadline!)).toEqual([b.id]);
  });

  it('completes confirmed bookings 3 hours after they end', async () => {
    const b = await book('10:00');
    await acceptBooking(pool, { bookingId: b.id, ...owner(), now: NOW });
    expect(await autoComplete(pool, local(MONDAY, '13:29'))).toEqual([]);
    expect(await autoComplete(pool, local(MONDAY, '13:30'))).toEqual([b.id]);
    expect(await status(b.id)).toBe('completed');
  });
});
