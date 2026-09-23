import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { addDays, toLocalDate } from '../src/booking/time.js';
import type { Pool } from '../src/db/pool.js';
import { validatePeriods } from '../src/owner/periods.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let keyCounter = 0;

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

type Method = 'GET' | 'POST' | 'PUT' | 'DELETE';
function call(method: Method, url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders, 'idempotency-key': `k-${Date.now()}-${++keyCounter}` };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

async function register(phone: string, device: string, name = 'علي') {
  const res = await call('POST', '/v1/auth/register', undefined, { name, phone, deviceIdentifier: device });
  return res.json() as { token: string; user: { id: number } };
}

async function refs() {
  const { rows: [d] } = await pool.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
  const { rows: [a] } = await pool.query(
    `INSERT INTO areas (district_id, name) VALUES ($1, $2) ON CONFLICT (district_id, name) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
    [d.id, 'العشار'],
  );
  const { rows: [t] } = await pool.query(`SELECT id FROM business_types ORDER BY id LIMIT 1`);
  return { districtId: d.id as number, areaId: a.id as number, businessTypeId: t.id as number };
}

const everyDay = [0, 1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, from: '09:00', to: '21:00' }));

/** صاحب محل مقبول بخدمة 30 دقيقة، يعمل كل يوم من 9 إلى 9 */
async function approvedShop(phone: string) {
  const owner = await register(phone, `owner-${phone}`);
  const r = await refs();
  await call('PUT', '/v1/owner/shop', owner.token, { name: `محل ${phone}`, ...r, latitude: 30.5, longitude: 47.8 });
  await call('POST', '/v1/owner/services', owner.token, { name: 'حلاقة', durationMinutes: 30, priceType: 'fixed', price: 10000 });
  await call('PUT', '/v1/owner/hours', owner.token, { periods: everyDay });
  await call('POST', '/v1/owner/shop/submit', owner.token);
  const shop = (await call('GET', '/v1/owner/shop', owner.token)).json().shop;
  await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shop.id]);
  return { token: owner.token, shopId: shop.id as number, serviceId: shop.services[0].id as number };
}

async function slotNextWeek(shopId: number, serviceId: number, offset = 0) {
  const date = addDays(toLocalDate(new Date()), 7);
  const res = await call('GET', `/v1/shops/${shopId}/slots?date=${date}&services=${serviceId}`);
  return res.json().slots[offset] as string;
}

async function book(token: string, shopId: number, serviceId: number, startsAt: string) {
  const res = await call('POST', '/v1/bookings', token, { shopId, serviceIds: [serviceId], startsAt });
  expect(res.statusCode).toBe(200);
  return res.json().booking as { id: number; status: string };
}

describe('working hours validation', () => {
  it('accepts several periods a day and shifts past midnight', () => {
    expect(() => validatePeriods([
      { dayOfWeek: 1, from: '09:00', to: '13:00' },
      { dayOfWeek: 1, from: '16:00', to: '02:00' },
      { dayOfWeek: 2, from: '09:00', to: '13:00' },
    ])).not.toThrow();
  });

  it('rejects overlapping periods, including a Saturday night running into Sunday', () => {
    expect(() => validatePeriods([
      { dayOfWeek: 1, from: '09:00', to: '13:00' },
      { dayOfWeek: 1, from: '12:00', to: '15:00' },
    ])).toThrow('overlapping_periods');
    expect(() => validatePeriods([
      { dayOfWeek: 6, from: '20:00', to: '03:00' },
      { dayOfWeek: 0, from: '02:00', to: '05:00' },
    ])).toThrow('overlapping_periods');
    expect(() => validatePeriods([{ dayOfWeek: 1, from: '25:00', to: '13:00' }])).toThrow('invalid_period');
  });
});

describe('shop application', () => {
  let token: string;
  beforeAll(async () => {
    token = (await register('07811111111', 'owner-app-1')).token;
  });

  it('starts with no shop, and the first save creates a draft', async () => {
    expect((await call('GET', '/v1/owner/shop', token)).json()).toEqual({ shop: null, missing: [] });
    const res = await call('PUT', '/v1/owner/shop', token, { name: 'صالون الورد', description: 'حلاقة وتجميل' });
    expect(res.json().shop).toMatchObject({ name: 'صالون الورد', status: 'draft' });
  });

  it('cannot be submitted until address, location, services and hours are set', async () => {
    const res = await call('POST', '/v1/owner/shop/submit', token);
    expect(res.json().error).toEqual({
      code: 'incomplete_shop', missing: ['businessType', 'address', 'location', 'services', 'hours'],
    });
  });

  it('saves step by step and is submitted for review', async () => {
    const r = await refs();
    await call('PUT', '/v1/owner/shop', token, { ...r, landmark: 'قرب الجامع', latitude: 30.51, longitude: 47.78 });
    const svc = await call('POST', '/v1/owner/services', token, { name: 'حلاقة', durationMinutes: 30, priceType: 'fixed', price: 10000 });
    expect(svc.json().shop.services).toHaveLength(1);
    const bad = await call('POST', '/v1/owner/services', token, { name: 'فحص', durationMinutes: 30, priceType: 'after_inspection', price: 5000 });
    expect(bad.json().error.code).toBe('invalid_service');
    await call('PUT', '/v1/owner/hours', token, { periods: everyDay });
    const res = await call('POST', '/v1/owner/shop/submit', token);
    expect(res.json()).toMatchObject({ shop: { status: 'under_review' }, missing: [] });
  });

  it('is hidden from customers until the admin approves it', async () => {
    const { shop } = (await call('GET', '/v1/owner/shop', token)).json();
    expect((await call('GET', `/v1/shops/${shop.id}`)).statusCode).toBe(404);
    await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shop.id]);
    expect((await call('GET', `/v1/shops/${shop.id}`)).statusCode).toBe(200);
  });

  it('rejects an area from another district', async () => {
    const { rows: [other] } = await pool.query(`SELECT id FROM districts WHERE name = 'الزبير'`);
    const r = await refs();
    const res = await call('PUT', '/v1/owner/shop', token, { districtId: other.id, areaId: r.areaId });
    expect(res.json().error.code).toBe('area_not_in_district');
  });

  it('lets the owner ask for a missing area', async () => {
    const r = await refs();
    expect((await call('POST', '/v1/owner/area-requests', token, { districtId: r.districtId, name: 'حي الحسين' })).statusCode).toBe(200);
    const { rows } = await pool.query(`SELECT name, status FROM area_requests`);
    expect(rows).toEqual([{ name: 'حي الحسين', status: 'pending' }]);
  });

  it('keeps the minimum lead time at 3 hours or more', async () => {
    expect((await call('PUT', '/v1/owner/settings', token, { minLeadMinutes: 60 })).json().error.code).toBe('invalid_settings');
    const ok = await call('PUT', '/v1/owner/settings', token, { minLeadMinutes: 240, deadlineMode: 'flexible', freeCancelHours: 6, bufferMinutes: 10 });
    expect(ok.json().shop).toMatchObject({ minLeadMinutes: 240, deadlineMode: 'flexible', freeCancelHours: 6, bufferMinutes: 10 });
  });

  it('adds a temporary schedule and refuses one that overlaps it', async () => {
    const body = {
      name: 'رمضان', fromDate: '2027-02-08', toDate: '2027-03-09',
      periods: everyDay.map((p) => ({ ...p, from: '20:00', to: '02:00' })),
    };
    const res = await call('POST', '/v1/owner/temporary-schedules', token, body);
    expect(res.json().shop.temporarySchedules[0]).toMatchObject({ name: 'رمضان', fromDate: '2027-02-08' });
    expect(res.json().shop.temporarySchedules[0].periods).toHaveLength(7);
    const again = await call('POST', '/v1/owner/temporary-schedules', token, { ...body, name: 'عيد' });
    expect(again.json().error.code).toBe('temporary_schedule_overlap');
  });

  it('uploads photos that customers can load', async () => {
    const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a5d80000000049454e44ae426082', 'hex');
    const res = await call('POST', '/v1/owner/photos', token, { contentType: 'image/png', data: png.toString('base64') });
    const url = res.json().shop.photos[0].url as string;
    expect(url).toMatch(/^\/photos\/\d+$/);
    const img = await app.inject({ method: 'GET', url });
    expect(img.headers['content-type']).toBe('image/png');
    expect(img.rawPayload.equals(png)).toBe(true);
    expect((await call('POST', '/v1/owner/photos', token, { contentType: 'text/html', data: 'aGk=' })).json().error.code).toBe('invalid_photo');
  });
});

describe('owner dashboard and actions', () => {
  let owner: Awaited<ReturnType<typeof approvedShop>>;
  let customer: { token: string; user: { id: number } };

  beforeAll(async () => {
    owner = await approvedShop('07822222222');
    customer = await register('07833333333', 'cust-dev-1', 'حسن');
  });

  it('lists requests waiting for a reply with the customer phone', async () => {
    const b = await book(customer.token, owner.shopId, owner.serviceId, await slotNextWeek(owner.shopId, owner.serviceId, 0));
    const res = await call('GET', '/v1/owner/dashboard', owner.token);
    const pending = res.json().pending;
    expect(pending.map((p: { id: number }) => p.id)).toContain(b.id);
    expect(pending[0].customer).toMatchObject({ name: 'حسن', phone: '07833333333', newDevice: false });
  });

  it('accepts from the dashboard, and the day view shows the booking', async () => {
    const [p] = (await call('GET', '/v1/owner/dashboard', owner.token)).json().pending;
    const res = await call('POST', `/v1/owner/bookings/${p.id}/accept`, owner.token);
    expect(res.json().booking.status).toBe('confirmed');
    const date = toLocalDate(new Date(p.startsAt));
    const day = await call('GET', `/v1/owner/day?date=${date}`, owner.token);
    expect(day.json().bookings.map((x: { id: number }) => x.id)).toContain(p.id);
  });

  it('proposes another time for a confirmed booking instead of cancelling it', async () => {
    const [p] = (await call('GET', `/v1/owner/day?date=${addDays(toLocalDate(new Date()), 7)}`, owner.token)).json().bookings;
    const slots = (await call('GET', `/v1/owner/bookings/${p.id}/slots?date=${addDays(toLocalDate(new Date()), 8)}`, owner.token)).json().slots;
    const res = await call('POST', `/v1/owner/bookings/${p.id}/propose`, owner.token, { times: [slots[0]], message: 'عندي ظرف' });
    expect(res.json().booking).toMatchObject({ status: 'pending_customer', modificationMessage: 'عندي ظرف' });
    expect(res.json().booking.proposedTimes).toHaveLength(1);
    const seen = (await call('GET', `/v1/bookings/${p.id}`, customer.token)).json().booking;
    expect(seen.proposedTimes[0]).toMatchObject({ available: true });
  });

  it('rejects with a reason code shown to the customer, and hides the phone afterwards', async () => {
    const b = await book(customer.token, owner.shopId, owner.serviceId, await slotNextWeek(owner.shopId, owner.serviceId, 6));
    const res = await call('POST', `/v1/owner/bookings/${b.id}/reject`, owner.token, { reason: 'busy' });
    expect(res.json().booking).toMatchObject({ status: 'rejected', cancelReason: 'busy' });
    expect(res.json().booking.customer.phone).toBeNull();
    expect((await call('GET', `/v1/bookings/${b.id}`, customer.token)).json().booking.cancelReason).toBe('busy');
  });

  it('flags a request from a new device, and verifying by phone makes it trusted', async () => {
    const other = await register('07833333333', 'cust-dev-2');
    const b = await book(other.token, owner.shopId, owner.serviceId, await slotNextWeek(owner.shopId, owner.serviceId, 10));
    const detail = (await call('GET', `/v1/owner/bookings/${b.id}`, owner.token)).json().booking;
    expect(detail.customer.newDevice).toBe(true);
    expect(detail.customer.stats).toEqual({ attended: 0, lateCancels: 0, noShows: 0 });
    const verified = await call('POST', `/v1/owner/bookings/${b.id}/verify-device`, owner.token);
    expect(verified.json().booking.customer.newDevice).toBe(false);
    expect((await call('GET', '/v1/me', other.token)).json().trustedDevice).toBe(true);
  });

  it('refuses shop management from a second device with the same number', async () => {
    const intruder = await register('07822222222', 'another-phone');
    const res = await call('GET', '/v1/owner/dashboard', intruder.token);
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('untrusted_device');
    expect((await call('PUT', '/v1/owner/shop', intruder.token, { name: 'مخترق' })).statusCode).toBe(403);
  });

  it('does not let another owner see or act on the booking', async () => {
    const stranger = await approvedShop('07844444444');
    const [p] = (await call('GET', '/v1/owner/dashboard', owner.token)).json().pending;
    expect((await call('GET', `/v1/owner/bookings/${p.id}`, stranger.token)).statusCode).toBe(404);
    expect((await call('POST', `/v1/owner/bookings/${p.id}/accept`, stranger.token)).statusCode).toBe(404);
  });
});

describe('emergency closure', () => {
  it('offers the affected customer the nearest alternatives, and frees nothing inside the closure', async () => {
    const owner = await approvedShop('07855555555');
    const customer = await register('07866666666', 'cust-closure');
    const startsAt = await slotNextWeek(owner.shopId, owner.serviceId, 4);
    const b = await book(customer.token, owner.shopId, owner.serviceId, startsAt);
    await call('POST', `/v1/owner/bookings/${b.id}/accept`, owner.token);

    const start = new Date(new Date(startsAt).getTime() - 3600_000);
    const end = new Date(new Date(startsAt).getTime() + 3 * 3600_000);
    const res = await call('POST', '/v1/owner/closures', owner.token, { startsAt: start.toISOString(), endsAt: end.toISOString() });
    expect(res.json()).toMatchObject({ moved: [b.id], cancelled: [] });

    const seen = (await call('GET', `/v1/bookings/${b.id}`, customer.token)).json().booking;
    expect(seen).toMatchObject({ status: 'pending_customer', cancelReason: 'emergency_closure' });
    expect(seen.proposedTimes).toHaveLength(3);
    for (const t of seen.proposedTimes) {
      const at = new Date(t.startsAt).getTime();
      expect(at < start.getTime() || at >= end.getTime()).toBe(true);
    }
    const shop = (await call('GET', '/v1/owner/shop', owner.token)).json().shop;
    expect(shop.closures).toHaveLength(1);
  });
});
