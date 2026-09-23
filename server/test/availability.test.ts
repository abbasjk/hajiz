import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { availableSlots, isSlotAvailable, loadShop } from '../src/booking/availability.js';
import { loadSettings } from '../src/booking/settings.js';
import type { Pool } from '../src/db/pool.js';
import { createShop, createUser, local, MONDAY, resetBookings, TUESDAY, type ShopFixture } from './fixtures.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let shop: ShopFixture;
let customerId: number;
const SUNDAY_NOW = local('2026-10-04', '10:00');

const times = (slots: Date[]) =>
  slots.map((s) => new Date(s.getTime() + 3 * 3600_000).toISOString().slice(11, 16));

beforeAll(async () => {
  pool = await freshDatabase();
  shop = await createShop(pool);
  customerId = (await createUser(pool)).userId;
});

beforeEach(async () => {
  await resetBookings(pool);
  await pool.query('UPDATE shops SET buffer_minutes = 0, min_lead_minutes = 0 WHERE id = $1', [shop.shopId]);
  await pool.query('DELETE FROM closures; DELETE FROM temporary_schedules;');
  await pool.query(`DELETE FROM weekly_periods WHERE schedule_id = $1 AND day_of_week <> 1`, [shop.scheduleId]);
});

afterAll(async () => {
  await pool.end();
});

async function slots(serviceIds = [shop.haircut], date = MONDAY, now = SUNDAY_NOW) {
  return (await availableSlots(pool, { shopId: shop.shopId, serviceIds, date, now })).slots;
}

async function insertBooking(start: string, end: string, status = 'confirmed') {
  await pool.query(
    `INSERT INTO bookings (customer_id, shop_id, schedule_id, starts_at, ends_at, status)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [customerId, shop.shopId, shop.scheduleId, local(MONDAY, start), local(MONDAY, end), status],
  );
}

describe('available slots', () => {
  it('splits working hours into quarter hours and skips the break', async () => {
    const result = times(await slots());
    expect(result[0]).toBe('09:00');
    expect(result).toContain('11:30');
    expect(result).not.toContain('11:45'); // 30 دقيقة لا تتسع قبل 12:00
    expect(result.filter((t) => t >= '12:00' && t < '16:00')).toEqual([]);
    expect(result.at(-1)).toBe('19:30');
    expect(result).toHaveLength(11 + 15);
  });

  it('adds up the durations of several services', async () => {
    const result = times(await slots([shop.haircut, shop.beard]));
    expect(result).toContain('11:15');
    expect(result).not.toContain('11:30');
  });

  it('returns nothing on a day off', async () => {
    expect(await slots([shop.haircut], TUESDAY)).toEqual([]);
  });

  it('removes times taken by active bookings, including pending requests', async () => {
    await insertBooking('10:00', '10:30', 'confirmed');
    await insertBooking('17:00', '17:30', 'pending_shop');
    const result = times(await slots());
    for (const t of ['09:45', '10:00', '10:15', '16:45', '17:00', '17:15']) expect(result).not.toContain(t);
    expect(result).toContain('09:30');
    expect(result).toContain('10:30');
  });

  it('frees times of cancelled or expired bookings', async () => {
    await insertBooking('10:00', '10:30', 'expired');
    await insertBooking('10:00', '10:30', 'cancelled_by_customer');
    expect(times(await slots())).toContain('10:00');
  });

  it('keeps the buffer time free around bookings', async () => {
    await pool.query('UPDATE shops SET buffer_minutes = 10 WHERE id = $1', [shop.shopId]);
    await insertBooking('10:00', '10:30');
    const result = times(await slots());
    expect(result).not.toContain('09:30'); // ينتهي 10:00، والفاصل يبدأ 09:50
    expect(result).not.toContain('10:30'); // الفاصل ينتهي 10:40
    expect(result).toContain('09:15');
    expect(result).toContain('10:45');
  });

  it('removes times during an emergency closure', async () => {
    await pool.query('INSERT INTO closures (schedule_id, starts_at, ends_at) VALUES ($1, $2, $3)', [
      shop.scheduleId, local(MONDAY, '16:00'), local(MONDAY, '20:00'),
    ]);
    const result = times(await slots());
    expect(result.at(-1)).toBe('11:30');
  });

  it('uses a temporary schedule instead of the weekly one while it lasts', async () => {
    const { rows: [temp] } = await pool.query(
      `INSERT INTO temporary_schedules (schedule_id, name, from_date, to_date)
       VALUES ($1, 'رمضان', $2, $2) RETURNING id`,
      [shop.scheduleId, MONDAY],
    );
    await pool.query(
      `INSERT INTO temporary_schedule_periods (temporary_schedule_id, day_of_week, start_time, end_time)
       VALUES ($1, 1, '21:00', '22:00')`,
      [temp.id],
    );
    expect(times(await slots())).toEqual(['21:00', '21:15', '21:30']);
  });

  it('handles a shift that runs past midnight', async () => {
    await pool.query(
      `INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time) VALUES ($1, 1, '21:00', '02:00')`,
      [shop.scheduleId],
    );
    const result = await slots();
    expect(times(result).at(-1)).toBe('01:30');
    expect(result.at(-1)).toEqual(local(TUESDAY, '01:30'));

    const settings = await loadSettings(pool);
    const s = await loadShop(pool, shop.shopId);
    const ok = await isSlotAvailable(pool, {
      shop: s, durationMinutes: 30, start: local(TUESDAY, '01:30'), now: SUNDAY_NOW, settings,
    });
    expect(ok).toBe(true);
    await pool.query(`DELETE FROM weekly_periods WHERE schedule_id = $1 AND start_time = '21:00'`, [shop.scheduleId]);
  });

  it('respects the minimum 3 hours before booking', async () => {
    const result = times(await slots([shop.haircut], MONDAY, local(MONDAY, '08:00')));
    expect(result[0]).toBe('11:00');
  });

  it('lets the shop raise the minimum lead time but never lower it', async () => {
    await pool.query('UPDATE shops SET min_lead_minutes = 300 WHERE id = $1', [shop.shopId]);
    expect(times(await slots([shop.haircut], MONDAY, local(MONDAY, '08:00')))[0]).toBe('16:00');
    await pool.query('UPDATE shops SET min_lead_minutes = 30 WHERE id = $1', [shop.shopId]);
    expect(times(await slots([shop.haircut], MONDAY, local(MONDAY, '08:00')))[0]).toBe('11:00');
  });

  it('rejects services from another shop', async () => {
    const other = await createShop(pool);
    await expect(slots([other.haircut])).rejects.toMatchObject({ code: 'invalid_services' });
  });

  it('hides shops that are not approved', async () => {
    await pool.query(`UPDATE shops SET status = 'suspended' WHERE id = $1`, [shop.shopId]);
    await expect(slots()).rejects.toMatchObject({ code: 'shop_not_found' });
    await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shop.shopId]);
  });
});

describe('GET /v1/shops/:shopId/slots', () => {
  let app: FastifyInstance;
  beforeAll(async () => {
    app = await buildApp({ pool, logLevel: 'silent' });
  });
  afterAll(async () => {
    await app.close();
  });

  it('returns ISO times for a future date', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/shops/${shop.shopId}/slots?date=2027-01-04&services=${shop.haircut},${shop.beard}`,
      headers: appHeaders,
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.durationMinutes).toBe(45);
    expect(body.slots[0]).toBe(local('2027-01-04', '09:00').toISOString());
  });

  it('rejects a malformed date', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/v1/shops/${shop.shopId}/slots?date=2027-02-30&services=${shop.haircut}`,
      headers: appHeaders,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ error: { code: 'invalid_request' } });
  });
});
