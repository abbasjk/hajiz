import { readFileSync } from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassword } from '../src/admin/auth.js';
import { buildApp } from '../src/app.js';
import { hashToken } from '../src/auth/tokens.js';
import type { Pool } from '../src/db/pool.js';
import { createShop, type ShopFixture } from './fixtures.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let shop: ShopFixture;
let other: ShopFixture;
let ownerToken: string;
let adminToken: string;

function call(method: 'GET' | 'POST' | 'PUT' | 'PATCH', url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

function admin(method: 'GET' | 'POST' | 'PATCH', url: string, body?: unknown) {
  return app.inject({ method, url: `/admin/api${url}`, headers: { authorization: `Bearer ${adminToken}` }, payload: (body ?? {}) as object });
}

const categoryId = async (icon: string) =>
  (await pool.query('SELECT id FROM service_categories WHERE icon = $1', [icon])).rows[0].id as number;

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
  shop = await createShop(pool);
  other = await createShop(pool);
  const { rows } = await pool.query('SELECT id FROM devices WHERE user_id = $1', [shop.ownerId]);
  await pool.query('UPDATE devices SET token_hash = $1 WHERE id = $2', [hashToken('owner-token'), rows[0].id]);
  ownerToken = 'owner-token';
  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', ['abbas', await hashPassword('correct-horse-battery')]);
  adminToken = (await app.inject({ method: 'POST', url: '/admin/api/login', payload: { username: 'abbas', password: 'correct-horse-battery' } })).json().token;
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('service categories', () => {
  it('lists the ten categories with their icons in the app config', async () => {
    const config = (await call('GET', '/v1/config')).json();
    expect(config.serviceCategories).toHaveLength(10);
    expect(config.serviceCategories[0]).toMatchObject({ name: 'حلاقة الشعر', icon: 'haircut' });
  });

  it('lets the owner pick a category for a service, and keeps it when an old app edits without one', async () => {
    const dye = await categoryId('dye');
    const res = await call('POST', '/v1/owner/services', ownerToken, { name: 'صبغة كاملة', durationMinutes: 60, priceType: 'fixed', price: 25000, categoryId: dye });
    expect(res.statusCode).toBe(200);
    const service = res.json().shop.services.find((s: { name: string }) => s.name === 'صبغة كاملة');
    expect(service.categoryId).toBe(dye);

    const edit = await call('PUT', `/v1/owner/services/${service.id}`, ownerToken, { name: 'صبغة كاملة', durationMinutes: 45, priceType: 'fixed', price: 25000 });
    expect(edit.statusCode).toBe(200);
    expect(edit.json().shop.services.find((s: { id: number }) => s.id === service.id).categoryId).toBe(dye);

    const bad = await call('POST', '/v1/owner/services', ownerToken, { name: 'شيء', durationMinutes: 30, priceType: 'fixed', price: 1, categoryId: 99999 });
    expect(bad.json().error.code).toBe('invalid_service');
  });

  it('filters shops by category and shows the matching service on the card', async () => {
    const res = await call('GET', `/v1/shops?serviceCategoryId=${await categoryId('dye')}`);
    const shops = res.json().shops;
    expect(shops.map((s: { id: number }) => s.id)).toEqual([shop.shopId]);
    expect(shops[0].matchedService).toMatchObject({ name: 'صبغة كاملة', price: 25000 });
    expect(shops.some((s: { id: number }) => s.id === other.shopId)).toBe(false);
  });

  it('guesses a category for existing services from their names, most specific first', async () => {
    const names = ['حلاقة ذقن بالموس', 'تهذيب اللحية', 'صبغ شعر', 'حلاقة شعر للأطفال', 'قصة شعر', 'تدليك'];
    const ids: number[] = [];
    for (const name of names) {
      const { rows } = await pool.query(
        `INSERT INTO services (shop_id, name, duration_minutes, price_type, price) VALUES ($1, $2, 20, 'fixed', 5000) RETURNING id`,
        [other.shopId, name],
      );
      ids.push(rows[0].id);
    }
    // قواعد الترحيل نفسها، تُشغَّل على هذه الخدمات
    const sql = readFileSync(new URL('../migrations/018_service_categories.sql', import.meta.url), 'utf8');
    await pool.query(sql.slice(sql.indexOf('WITH rules')));
    const { rows } = await pool.query(
      `SELECT s.id, c.icon FROM services s LEFT JOIN service_categories c ON c.id = s.category_id WHERE s.id = ANY($1)`,
      [ids],
    );
    const icon = (i: number) => rows.find((r) => r.id === ids[i])?.icon ?? null;
    expect([0, 1, 2, 3, 4, 5].map(icon)).toEqual(['razor', 'beard', 'dye', 'kids', 'haircut', null]);
  });

  it('lets the admin add, rename, hide and re-icon categories', async () => {
    const created = await admin('POST', '/service-categories', { name: 'مساج', icon: 'skin' });
    expect(created.statusCode).toBe(200);
    const id = created.json().id;
    expect((await admin('POST', '/service-categories', { name: 'مساج', icon: 'skin' })).json().error.code).toBe('name_exists');
    expect((await admin('POST', '/service-categories', { name: 'أخرى', icon: 'unknown' })).statusCode).toBe(400);

    expect((await admin('PATCH', `/service-categories/${id}`, { name: 'مساج الرأس', icon: 'treatment' })).statusCode).toBe(200);
    let config = (await call('GET', '/v1/config')).json();
    expect(config.serviceCategories.find((c: { id: number }) => c.id === id)).toMatchObject({ name: 'مساج الرأس', icon: 'treatment' });

    await admin('PATCH', `/service-categories/${id}`, { active: false });
    config = (await call('GET', '/v1/config')).json();
    expect(config.serviceCategories.some((c: { id: number }) => c.id === id)).toBe(false);
    const catalog = (await admin('GET', '/catalog')).json();
    expect(catalog.serviceCategories.find((c: { id: number }) => c.id === id)).toMatchObject({ active: false, services: 0 });
  });
});
