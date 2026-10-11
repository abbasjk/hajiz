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
let customer: string;
let adminToken: string;

type Method = 'GET' | 'POST' | 'PUT';

function call(method: Method, url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders, 'idempotency-key': `k-${Date.now()}-${++keyCounter}` };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

async function register(phone: string, name: string) {
  const res = await call('POST', '/v1/auth/register', undefined, { name, phone, deviceIdentifier: `device-${phone}` });
  return res.json().token as string;
}

/** حجز مؤكد ثم مكتمل؛ ago: كم يوماً مضى على الموعد */
async function completedBooking(token: string, offset: number, ago = 1) {
  const date = addDays(toLocalDate(new Date()), 7);
  const slots = (await call('GET', `/v1/shops/${shopId}/slots?date=${date}&services=${serviceId}`)).json().slots as string[];
  const created = await call('POST', '/v1/bookings', token, { shopId, serviceIds: [serviceId], startsAt: slots[offset] });
  const id = created.json().booking.id as number;
  await call('POST', `/v1/owner/bookings/${id}/accept`, owner);
  await pool.query(
    `UPDATE bookings SET status = 'completed', starts_at = now() - make_interval(days => $2),
       ends_at = now() - make_interval(days => $2) + interval '30 minutes', response_deadline = NULL
     WHERE id = $1`,
    [id, ago],
  );
  return id;
}

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });

  owner = await register('07700000701', 'صاحب');
  const { rows: [d] } = await pool.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
  const { rows: [a] } = await pool.query(`INSERT INTO areas (district_id, name) VALUES ($1, 'العشار') RETURNING id`, [d.id]);
  const { rows: [t] } = await pool.query('SELECT id FROM business_types ORDER BY id LIMIT 1');
  await call('PUT', '/v1/owner/shop', owner, { name: 'صالون التقييم', businessTypeId: t.id, districtId: d.id, areaId: a.id, latitude: 30.5, longitude: 47.8 });
  await call('POST', '/v1/owner/services', owner, { name: 'قص شعر', durationMinutes: 30, priceType: 'fixed', price: 7000 });
  await call('PUT', '/v1/owner/hours', owner, {
    periods: [0, 1, 2, 3, 4, 5, 6].map((day) => ({ dayOfWeek: day, from: '09:00', to: '21:00' })),
  });
  await call('POST', '/v1/owner/shop/submit', owner);
  const shop = (await call('GET', '/v1/owner/shop', owner)).json().shop;
  shopId = shop.id;
  serviceId = shop.services[0].id;
  await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shopId]);
  await pool.query(`UPDATE settings SET value = '20' WHERE key = 'max_pending_requests_per_customer'`);

  customer = await register('07700000702', 'حيدر كاظم');

  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', ['abbas', await hashPassword('correct-horse-battery')]);
  const login = await app.inject({ method: 'POST', url: '/admin/api/login', payload: { username: 'abbas', password: 'correct-horse-battery' } });
  adminToken = login.json().token;
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('reviews', () => {
  it('cannot review a booking that is not completed', async () => {
    const date = addDays(toLocalDate(new Date()), 7);
    const slots = (await call('GET', `/v1/shops/${shopId}/slots?date=${date}&services=${serviceId}`)).json().slots as string[];
    const created = await call('POST', '/v1/bookings', customer, { shopId, serviceIds: [serviceId], startsAt: slots[10] });
    const booking = created.json().booking;
    expect(booking.canReview).toBe(false);
    const res = await call('POST', `/v1/bookings/${booking.id}/review`, customer, { stars: 5 });
    expect(res.statusCode).toBe(409);
    expect(res.json().error.code).toBe('review_not_allowed');
  });

  it('reviews a completed booking once, and the shop shows the rating', async () => {
    const id = await completedBooking(customer, 0);
    const before = (await call('GET', `/v1/bookings/${id}`, customer)).json().booking;
    expect(before).toMatchObject({ canReview: true, review: null });

    expect((await call('POST', `/v1/bookings/${id}/review`, customer, { stars: 6 })).statusCode).toBe(400);
    const res = await call('POST', `/v1/bookings/${id}/review`, customer, { stars: 4, comment: '  خدمة ممتازة  ' });
    expect(res.statusCode).toBe(200);
    expect(res.json().booking).toMatchObject({ canReview: false, review: { stars: 4, comment: 'خدمة ممتازة' } });

    const again = await call('POST', `/v1/bookings/${id}/review`, customer, { stars: 5 });
    expect(again.json().error.code).toBe('already_reviewed');

    const list = (await call('GET', '/v1/shops')).json().shops;
    expect(list[0]).toMatchObject({ id: shopId, rating: 4, ratingCount: 1 });
    const page = (await call('GET', `/v1/shops/${shopId}`)).json().shop;
    expect(page).toMatchObject({ rating: 4, ratingCount: 1 });
    // الاسم الأول فقط
    expect(page.reviews[0]).toMatchObject({ stars: 4, comment: 'خدمة ممتازة', customerName: 'حيدر' });
  });

  it('averages several reviews', async () => {
    const id = await completedBooking(customer, 2);
    await call('POST', `/v1/bookings/${id}/review`, customer, { stars: 5 });
    const list = (await call('GET', '/v1/shops')).json().shops;
    expect(list[0]).toMatchObject({ rating: 4.5, ratingCount: 2 });
  });

  it('only the customer who booked can review', async () => {
    const id = await completedBooking(customer, 4);
    const stranger = await register('07700000703', 'غريب');
    const res = await call('POST', `/v1/bookings/${id}/review`, stranger, { stars: 1 });
    expect(res.statusCode).toBe(404);
  });

  it('closes reviews after the review window', async () => {
    const id = await completedBooking(customer, 6, 20);
    expect((await call('GET', `/v1/bookings/${id}`, customer)).json().booking.canReview).toBe(false);
    const res = await call('POST', `/v1/bookings/${id}/review`, customer, { stars: 3 });
    expect(res.json().error.code).toBe('review_window_closed');
  });

  it('asks the customer to review when the shop marks the visit done', async () => {
    const date = addDays(toLocalDate(new Date()), 7);
    const slots = (await call('GET', `/v1/shops/${shopId}/slots?date=${date}&services=${serviceId}`)).json().slots as string[];
    const created = await call('POST', '/v1/bookings', customer, { shopId, serviceIds: [serviceId], startsAt: slots[8] });
    const id = created.json().booking.id as number;
    await call('POST', `/v1/owner/bookings/${id}/accept`, owner);
    await pool.query(
      `UPDATE bookings SET starts_at = now() - interval '1 hour', ends_at = now() - interval '30 minutes',
         response_deadline = NULL WHERE id = $1`,
      [id],
    );
    expect((await call('POST', `/v1/owner/bookings/${id}/complete`, owner)).statusCode).toBe(200);
    const notices = (await call('GET', '/v1/me/notifications?audience=customer', customer)).json().notifications;
    expect(notices[0]).toMatchObject({ type: 'review_request', bookingId: id, title: 'كيف كانت زيارتك؟' });
  });

  it('lets the admin hide a review, removing it from the page and the average', async () => {
    const admin = (method: 'GET' | 'POST', url: string, body?: unknown) =>
      app.inject({ method, url: `/admin/api${url}`, headers: { authorization: `Bearer ${adminToken}` }, payload: body as object | undefined });
    const { reviews } = (await admin('GET', '/reviews')).json();
    expect(reviews).toHaveLength(2);
    const low = reviews.find((r: { stars: number }) => r.stars === 4);
    expect((await admin('POST', `/reviews/${low.id}/hide`, { note: 'محتوى مسيء' })).statusCode).toBe(200);
    expect((await admin('POST', `/reviews/${low.id}/hide`, {})).statusCode).toBe(409);

    const page = (await call('GET', `/v1/shops/${shopId}`)).json().shop;
    expect(page).toMatchObject({ rating: 5, ratingCount: 1 });
    expect(page.reviews.map((r: { stars: number }) => r.stars)).toEqual([5]);
    expect((await admin('GET', '/reviews?hidden=true')).json().reviews).toHaveLength(1);

    expect((await admin('POST', `/reviews/${low.id}/unhide`, {})).statusCode).toBe(200);
    expect((await call('GET', `/v1/shops/${shopId}`)).json().shop.ratingCount).toBe(2);
  });
});
