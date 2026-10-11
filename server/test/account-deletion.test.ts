import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassword } from '../src/admin/auth.js';
import { buildApp } from '../src/app.js';
import { addDays, toLocalDate } from '../src/booking/time.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let keyCounter = 0;
let owner: string;
let shopId: number;
let serviceId: number;
let adminToken: string;

type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';

function call(method: Method, url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders, 'idempotency-key': `k-${Date.now()}-${++keyCounter}` };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

async function register(phone: string, name: string, device = `device-${phone}`) {
  const res = await call('POST', '/v1/auth/register', undefined, { name, phone, deviceIdentifier: device });
  return res.json() as { token: string; user: { id: number } };
}

let slotIndex = 0;
async function book(token: string) {
  const date = addDays(toLocalDate(new Date()), 7);
  const slots = (await call('GET', `/v1/shops/${shopId}/slots?date=${date}&services=${serviceId}`)).json().slots as string[];
  const res = await call('POST', '/v1/bookings', token, { shopId, serviceIds: [serviceId], startsAt: slots[slotIndex++ * 2] });
  return res.json().booking.id as number;
}

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });

  owner = (await register('07700000801', 'صاحب المحل')).token;
  const { rows: [d] } = await pool.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
  const { rows: [a] } = await pool.query(`INSERT INTO areas (district_id, name) VALUES ($1, 'الجزائر') RETURNING id`, [d.id]);
  const { rows: [t] } = await pool.query('SELECT id FROM business_types ORDER BY id LIMIT 1');
  await call('PUT', '/v1/owner/shop', owner, { name: 'صالون الحذف', businessTypeId: t.id, districtId: d.id, areaId: a.id, latitude: 30.5, longitude: 47.8 });
  await call('POST', '/v1/owner/services', owner, { name: 'حلاقة', durationMinutes: 30, priceType: 'fixed', price: 5000 });
  await call('PUT', '/v1/owner/hours', owner, {
    periods: [0, 1, 2, 3, 4, 5, 6].map((day) => ({ dayOfWeek: day, from: '09:00', to: '21:00' })),
  });
  await call('POST', '/v1/owner/shop/submit', owner);
  const shop = (await call('GET', '/v1/owner/shop', owner)).json().shop;
  shopId = shop.id;
  serviceId = shop.services[0].id;
  await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shopId]);

  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', ['abbas', await hashPassword('correct-horse-battery')]);
  adminToken = (await app.inject({ method: 'POST', url: '/admin/api/login', payload: { username: 'abbas', password: 'correct-horse-battery' } })).json().token;
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('account deletion', () => {
  it('refuses an untrusted device (someone else typing the number)', async () => {
    await register('07700000802', 'زبون');
    const other = await register('07700000802', 'منتحل', 'someone-elses-phone');
    expect((await call('GET', '/v1/me/deletion', other.token)).statusCode).toBe(403);
    const res = await call('DELETE', '/v1/me', other.token);
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('untrusted_device');
  });

  it('deletes a customer: cancels upcoming bookings, tells the shop, and forgets the person', async () => {
    const { token, user } = await register('07700000803', 'مرتضى علي');
    const upcoming = await book(token);
    await call('POST', `/v1/owner/bookings/${upcoming}/accept`, owner);

    // حجز سابق مكتمل مع تقييم
    const past = await book(token);
    await call('POST', `/v1/owner/bookings/${past}/accept`, owner);
    await pool.query(
      `UPDATE bookings SET status = 'completed', starts_at = now() - interval '1 day',
         ends_at = now() - interval '1 day' + interval '30 minutes', response_deadline = NULL WHERE id = $1`,
      [past],
    );
    await call('POST', `/v1/bookings/${past}/review`, token, { stars: 5, comment: 'رائع جداً' });

    expect((await call('GET', '/v1/me/deletion', token)).json()).toEqual({ upcomingBookings: 1, shop: null });

    expect((await call('DELETE', '/v1/me', token)).statusCode).toBe(200);
    // المفتاح لم يعد يعمل
    expect((await call('GET', '/v1/bookings', token)).statusCode).toBe(401);

    const cancelled = (await call('GET', `/v1/owner/bookings/${upcoming}`, owner)).json().booking;
    expect(cancelled).toMatchObject({ status: 'cancelled_by_customer', cancelReason: 'account_deleted' });
    expect(cancelled.customer).toMatchObject({ deleted: true, phone: null, name: '' });

    const notices = (await call('GET', '/v1/me/notifications?audience=shop', owner)).json().notifications;
    expect(notices[0]).toMatchObject({ type: 'customer_cancelled', bookingId: upcoming });
    expect(notices[0].body).toContain('مرتضى علي');

    const { rows: [u] } = await pool.query('SELECT name, phone, deleted_at FROM users WHERE id = $1', [user.id]);
    expect(u.name).toBe('');
    expect(u.phone).toBe(`deleted:${user.id}`);
    expect(u.deleted_at).not.toBeNull();
    expect((await pool.query('SELECT 1 FROM devices WHERE user_id = $1', [user.id])).rowCount).toBe(0);

    // النجوم تبقى، والتعليق والاسم يذهبان
    const page = (await call('GET', `/v1/shops/${shopId}`)).json().shop;
    expect(page.ratingCount).toBe(1);
    expect(page.reviews[0]).toMatchObject({ stars: 5, comment: null, customerName: null });

    // الرقم نفسه يسجل من جديد كحساب جديد بلا حجوزات قديمة
    const again = await register('07700000803', 'مرتضى');
    expect(again.user.id).not.toBe(user.id);
    expect((await call('GET', '/v1/bookings', again.token)).json().bookings).toHaveLength(0);
  });

  it('deletes a shop owner: closes the shop for good and tells their customers', async () => {
    const customer = await register('07700000804', 'سجاد');
    const id = await book(customer.token);
    await call('POST', `/v1/owner/bookings/${id}/accept`, owner);

    expect((await call('GET', '/v1/me/deletion', owner)).json()).toEqual({
      upcomingBookings: 0,
      shop: { name: 'صالون الحذف', upcomingBookings: 1 },
    });
    expect((await call('DELETE', '/v1/me', owner)).statusCode).toBe(200);

    const booking = (await call('GET', `/v1/bookings/${id}`, customer.token)).json().booking;
    expect(booking).toMatchObject({ status: 'cancelled_by_shop', cancelReason: 'shop_closed' });
    const notices = (await call('GET', '/v1/me/notifications?audience=customer', customer.token)).json().notifications;
    expect(notices[0]).toMatchObject({ type: 'shop_cancelled', bookingId: id });

    expect((await call('GET', '/v1/shops')).json().shops).toHaveLength(0);
    expect((await call('GET', `/v1/shops/${shopId}`)).statusCode).toBe(404);

    const admin = (url: string) =>
      app.inject({ method: 'POST', url: `/admin/api${url}`, headers: { authorization: `Bearer ${adminToken}` }, payload: {} });
    const res = await admin(`/shops/${shopId}/reinstate`);
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('shop_closed');
  });
});
