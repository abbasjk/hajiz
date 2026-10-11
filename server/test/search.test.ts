import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let keyCounter = 0;
let workshop: number;
let barber: number;

function call(method: 'GET' | 'POST' | 'PUT', url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders, 'idempotency-key': `k-${Date.now()}-${++keyCounter}` };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

/** محل معتمد بالخدمات المعطاة */
async function shopWith(phone: string, name: string, services: string[]) {
  const reg = await call('POST', '/v1/auth/register', undefined, { name: 'صاحب', phone, deviceIdentifier: `device-${phone}` });
  const token = reg.json().token as string;
  const { rows: [d] } = await pool.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
  const { rows: [a] } = await pool.query(
    `INSERT INTO areas (district_id, name) VALUES ($1, 'العشار')
     ON CONFLICT (district_id, name) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
    [d.id],
  );
  const { rows: [t] } = await pool.query('SELECT id FROM business_types ORDER BY id LIMIT 1');
  await call('PUT', '/v1/owner/shop', token, {
    name, businessTypeId: t.id, districtId: d.id, areaId: a.id, latitude: 30.5, longitude: 47.8,
  });
  for (const s of services) {
    await call('POST', '/v1/owner/services', token, { name: s, durationMinutes: 30, priceType: 'fixed', price: 10000 });
  }
  await call('PUT', '/v1/owner/hours', token, {
    periods: [0, 1, 2, 3, 4, 5, 6].map((day) => ({ dayOfWeek: day, from: '09:00', to: '21:00' })),
  });
  await call('POST', '/v1/owner/shop/submit', token);
  const shop = (await call('GET', '/v1/owner/shop', token)).json().shop;
  await pool.query(`UPDATE shops SET status = 'approved' WHERE id = $1`, [shop.id]);
  return shop.id as number;
}

async function search(q: string) {
  const res = await call('GET', `/v1/shops?q=${encodeURIComponent(q)}`);
  expect(res.statusCode).toBe(200);
  return res.json().shops as { id: number; name: string; matchedService: { name: string; price: number } | null }[];
}

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
  workshop = await shopWith('07700000901', 'ورشة الإختبار', ['تبديل زيت وفلتر', 'فحص كهرباء']);
  barber = await shopWith('07700000902', 'صالون الأمير', ['قص شعر', 'تهذيب لحية', 'تنظيف بشرة']);
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('search', () => {
  it('finds a shop by part of a service name and returns that service', async () => {
    const shops = await search('زيت');
    expect(shops.map((s) => s.id)).toEqual([workshop]);
    expect(shops[0]!.matchedService).toMatchObject({ name: 'تبديل زيت وفلتر', price: 10000 });
  });

  it('ignores alef forms, taa marbuta and diacritics', async () => {
    expect((await search('اختبار')).map((s) => s.id)).toEqual([workshop]);
    expect((await search('لحيه')).map((s) => s.id)).toEqual([barber]);
    expect((await search('بَشَرَة')).map((s) => s.id)).toEqual([barber]);
  });

  it('accepts letters typed on a Kurdish keyboard', async () => {
    // ی و ک من لوحة المفاتيح الكردية
    await pool.query(`UPDATE services SET name = 'كي ملابس' WHERE name = 'فحص كهرباء'`);
    expect((await search('کی')).map((s) => s.id)).toEqual([workshop]);
  });

  it('matches shop names without a service', async () => {
    const shops = await search('الامير');
    expect(shops.map((s) => s.id)).toEqual([barber]);
    expect(shops[0]!.matchedService).toBeNull();
  });

  it('skips inactive services', async () => {
    await pool.query(`UPDATE services SET active = false WHERE name = 'تنظيف بشرة'`);
    expect(await search('بشرة')).toEqual([]);
  });

  it('treats % and _ as plain characters', async () => {
    expect(await search('%')).toEqual([]);
    expect(await search('_')).toEqual([]);
  });

  it('has no matched service when there is no search text', async () => {
    const res = await call('GET', '/v1/shops');
    const shops = res.json().shops as { matchedService: unknown }[];
    expect(shops).toHaveLength(2);
    expect(shops.every((s) => s.matchedService === null)).toBe(true);
  });
});
