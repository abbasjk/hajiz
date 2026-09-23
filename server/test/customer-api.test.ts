import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { proposeTimes } from '../src/booking/bookings.js';
import { addDays, toLocalDate } from '../src/booking/time.js';
import { seedDemoShop } from '../src/db/demo.js';
import type { Pool } from '../src/db/pool.js';
import { normalizeIraqiPhone } from '../src/lib/phone.js';
import { createShop, type ShopFixture } from './fixtures.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let shop: ShopFixture;

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
  shop = await createShop(pool);
  // يعمل كل أيام الأسبوع حتى تكون الاختبارات مستقلة عن تاريخ تشغيلها
  await pool.query('DELETE FROM weekly_periods WHERE schedule_id = $1', [shop.scheduleId]);
  for (let d = 0; d < 7; d++) {
    await pool.query(
      `INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time) VALUES ($1, $2, '09:00', '21:00')`,
      [shop.scheduleId, d],
    );
  }
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

let keyCounter = 0;
const newKey = () => `key-${Date.now()}-${++keyCounter}`;

function call(method: 'GET' | 'POST', url: string, opts: { token?: string; body?: unknown; key?: string | null } = {}) {
  const headers: Record<string, string> = { ...appHeaders };
  if (opts.token) headers.authorization = `Bearer ${opts.token}`;
  if (method === 'POST' && opts.key !== null) headers['idempotency-key'] = opts.key ?? newKey();
  return app.inject({ method, url, headers, payload: opts.body as object | undefined });
}

async function register(phone: string, deviceIdentifier: string, name = 'حسن علي') {
  const res = await call('POST', '/v1/auth/register', { body: { name, phone, deviceIdentifier }, key: null });
  expect(res.statusCode).toBe(200);
  return res.json();
}

/** أول وقت متاح بعد أسبوع (بعيد عن حد الإلغاء المجاني وأقل وقت قبل الحجز). */
async function slotNextWeek(offset = 0) {
  const date = addDays(toLocalDate(new Date()), 7);
  const res = await call('GET', `/v1/shops/${shop.shopId}/slots?date=${date}&services=${shop.haircut}`);
  return res.json().slots[offset] as string;
}

describe('phone numbers', () => {
  it.each([
    ['07701234567', '07701234567'],
    ['7701234567', '07701234567'],
    ['+964 770 123 4567', '07701234567'],
    ['00964-770-123-4567', '07701234567'],
    ['٠٧٧٠١٢٣٤٥٦٧', '07701234567'],
  ])('%s → %s', (input, out) => expect(normalizeIraqiPhone(input)).toBe(out));

  it.each(['0770123456', '06701234567', 'abc', ''])('rejects %s', (input) => {
    expect(normalizeIraqiPhone(input)).toBeNull();
  });
});

describe('registration at first booking', () => {
  it('saves the number, name and device together; that device is trusted', async () => {
    const r = await register('0771 000 0001', 'device-aaaaaaaa');
    expect(r.user).toMatchObject({ name: 'حسن علي', phone: '07710000001' });
    expect(r.trustedDevice).toBe(true);
    const me = await call('GET', '/v1/me', { token: r.token });
    expect(me.json()).toMatchObject({ user: { phone: '07710000001' }, trustedDevice: true });
  });

  it('the same number from another device is allowed but not trusted, and keeps the stored name', async () => {
    await register('07710000002', 'device-first-1');
    const other = await register('07710000002', 'device-other-2', 'اسم آخر');
    expect(other.trustedDevice).toBe(false);
    expect(other.user.name).toBe('حسن علي');
  });

  it('registering the same device again replaces the old token', async () => {
    const first = await register('07710000003', 'device-same-33');
    const second = await register('07710000003', 'device-same-33');
    expect((await call('GET', '/v1/me', { token: first.token })).statusCode).toBe(401);
    expect((await call('GET', '/v1/me', { token: second.token })).statusCode).toBe(200);
    expect(second.trustedDevice).toBe(true);
  });

  it('rejects an invalid phone', async () => {
    const res = await call('POST', '/v1/auth/register', {
      body: { name: 'حسن', phone: '12345', deviceIdentifier: 'device-bad-phone' }, key: null,
    });
    expect(res.json()).toEqual({ error: { code: 'invalid_phone' } });
  });

  it('protected routes need a valid token', async () => {
    expect((await call('GET', '/v1/me/bookings')).statusCode).toBe(401);
    expect((await call('GET', '/v1/me/bookings', { token: 'nope' })).statusCode).toBe(401);
  });
});

describe('browsing shops', () => {
  let second: ShopFixture;
  beforeAll(async () => {
    second = await createShop(pool);
    await pool.query(`UPDATE shops SET name = 'حلاق الزبير', latitude = 30.39, longitude = 47.70 WHERE id = $1`, [second.shopId]);
    await pool.query(`UPDATE shops SET name = 'صالون العشار', latitude = 30.51, longitude = 47.78 WHERE id = $1`, [shop.shopId]);
  });

  it('lists approved shops, searchable by name', async () => {
    const res = await call('GET', `/v1/shops?q=${encodeURIComponent('الزبير')}`);
    expect(res.json().shops.map((s: { id: number }) => s.id)).toEqual([second.shopId]);
  });

  it('sorts by distance from the customer', async () => {
    const res = await call('GET', '/v1/shops?sort=distance&lat=30.51&lng=47.78');
    const shops = res.json().shops;
    expect(shops[0].id).toBe(shop.shopId);
    expect(shops[0].distanceKm).toBe(0);
    expect(shops[1].distanceKm).toBeGreaterThan(10);
  });

  it('sorts by the soonest available time', async () => {
    const res = await call('GET', '/v1/shops?sort=soonest');
    const shops = res.json().shops;
    expect(shops[0].id).toBe(shop.shopId); // يعمل كل يوم، والآخر الاثنين فقط
    expect(shops[0].nextAvailable).toEqual(expect.any(String));
  });

  it('filters by business type and area', async () => {
    const { rows } = await pool.query('SELECT area_id FROM shops WHERE id = $1', [second.shopId]);
    const res = await call('GET', `/v1/shops?areaId=${rows[0].area_id}`);
    expect(res.json().shops.map((s: { id: number }) => s.id)).toEqual([second.shopId]);
  });

  it('shows the shop page with services and hours, but no commitment badge yet', async () => {
    const res = await call('GET', `/v1/shops/${shop.shopId}`);
    expect(res.statusCode).toBe(200);
    const s = res.json().shop;
    expect(s.services.map((x: { name: string }) => x.name)).toEqual(['حلاقة', 'لحية']);
    expect(s.weeklyHours).toHaveLength(7);
    expect(s.weeklyHours[0]).toEqual({ dayOfWeek: 0, from: '09:00', to: '21:00' });
    expect(s.committed).toBe(false);
  });

  it('hides shops that are not approved', async () => {
    await pool.query(`UPDATE shops SET status = 'suspended' WHERE id = $1`, [second.shopId]);
    expect((await call('GET', `/v1/shops/${second.shopId}`)).statusCode).toBe(404);
  });
});

describe('customer bookings over the API', () => {
  let token: string;
  beforeAll(async () => {
    token = (await register('07720000001', 'device-booker-1')).token;
  });

  it('needs an idempotency key, and a repeated key returns the same booking', async () => {
    const startsAt = await slotNextWeek(0);
    const body = { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt, note: 'قصة قصيرة' };
    expect((await call('POST', '/v1/bookings', { token, body, key: null })).json()).toEqual({
      error: { code: 'idempotency_key_required' },
    });
    const key = newKey();
    const first = await call('POST', '/v1/bookings', { token, body, key });
    const again = await call('POST', '/v1/bookings', { token, body, key });
    expect(first.statusCode).toBe(200);
    expect(again.json().booking.id).toBe(first.json().booking.id);
    const b = first.json().booking;
    expect(b).toMatchObject({ status: 'pending_shop', note: 'قصة قصيرة', shop: { id: shop.shopId } });
    expect(b.services).toEqual([{ name: 'حلاقة', durationMinutes: 30, priceType: 'fixed', price: 10000 }]);
  });

  it('lists my bookings with the server time for the countdown', async () => {
    const res = await call('GET', '/v1/me/bookings', { token });
    expect(res.json().bookings).toHaveLength(1);
    expect(Date.parse(res.json().serverTime)).not.toBeNaN();
  });

  it('does not show past bookings on a new device with the same number', async () => {
    const other = await register('07720000001', 'device-booker-2');
    expect((await call('GET', '/v1/me/bookings', { token: other.token })).json().bookings).toEqual([]);
    const [mine] = (await call('GET', '/v1/me/bookings', { token })).json().bookings;
    expect((await call('GET', `/v1/bookings/${mine.id}`, { token: other.token })).statusCode).toBe(404);
    expect((await call('POST', `/v1/bookings/${mine.id}/cancel`, { token: other.token })).statusCode).toBe(404);
  });

  it('cancels a booking', async () => {
    const [mine] = (await call('GET', '/v1/me/bookings', { token })).json().bookings;
    const res = await call('POST', `/v1/bookings/${mine.id}/cancel`, { token });
    expect(res.json().booking).toMatchObject({ status: 'cancelled_by_customer', cancelledLate: false });
  });

  it('shows proposed times, marks taken ones, and confirms the chosen one', async () => {
    const startsAt = await slotNextWeek(0);
    const created = await call('POST', '/v1/bookings', {
      token, body: { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt },
    });
    const id = created.json().booking.id;
    const [a, b] = [await slotNextWeek(4), await slotNextWeek(8)];
    await proposeTimes(pool, { bookingId: id, ownerId: shop.ownerId, now: new Date(), times: [new Date(a), new Date(b)] });

    // زبون آخر يأخذ الوقت الأول: الأوقات المقترحة لا تُقفل
    const rival = (await register('07720000009', 'device-rival-9')).token;
    await call('POST', '/v1/bookings', { token: rival, body: { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: a } });

    const detail = (await call('GET', `/v1/bookings/${id}`, { token })).json().booking;
    expect(detail.status).toBe('pending_customer');
    expect(detail.proposedTimes.map((t: { available: boolean }) => t.available)).toEqual([false, true]);

    const taken = await call('POST', `/v1/bookings/${id}/choose`, { token, body: { proposedTimeId: detail.proposedTimes[0].id } });
    expect(taken.json()).toEqual({ error: { code: 'time_no_longer_available' } });
    const ok = await call('POST', `/v1/bookings/${id}/choose`, { token, body: { proposedTimeId: detail.proposedTimes[1].id } });
    expect(ok.json().booking).toMatchObject({ status: 'confirmed', startsAt: new Date(b).toISOString() });
  });
});

describe('demo shop', () => {
  it('is created once, open Saturday to Thursday', async () => {
    expect(await seedDemoShop(pool)).toBe(true);
    expect(await seedDemoShop(pool)).toBe(false);
    const { rows } = await pool.query(
      `SELECT array_agg(DISTINCT day_of_week ORDER BY day_of_week) AS days FROM weekly_periods wp
       JOIN schedules sc ON sc.id = wp.schedule_id JOIN shops s ON s.id = sc.shop_id WHERE s.name = 'صالون تجريبي'`,
    );
    expect(rows[0].days).toEqual([0, 1, 2, 3, 4, 6]);
  });
});
