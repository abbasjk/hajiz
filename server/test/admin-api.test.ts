import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassword, verifyPassword } from '../src/admin/auth.js';
import { bootstrapAdmin } from '../src/admin/bootstrap.js';
import { buildApp } from '../src/app.js';
import type { Pool } from '../src/db/pool.js';
import { sameShape } from '../src/routes/admin.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let adminToken: string;
let keyCounter = 0;

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', ['abbas', await hashPassword('correct-horse-battery')]);
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

function admin(method: Method, url: string, body?: unknown, token: string | null = adminToken) {
  const headers: Record<string, string> = {};
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url: `/admin/api${url}`, headers, payload: body as object | undefined });
}

function v1(method: Method, url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders, 'idempotency-key': `k-${Date.now()}-${++keyCounter}` };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url: `/v1${url}`, headers, payload: body as object | undefined });
}

async function register(phone: string, device: string, name = 'علي') {
  const res = await v1('POST', '/auth/register', undefined, { name, phone, deviceIdentifier: device });
  return res.json() as { token: string; user: { id: number } };
}

async function refs() {
  const { rows: [d] } = await pool.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
  const { rows: [a] } = await pool.query(
    `INSERT INTO areas (district_id, name) VALUES ($1, 'العشار')
     ON CONFLICT (district_id, name) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
    [d.id],
  );
  const { rows: [t] } = await pool.query('SELECT id FROM business_types ORDER BY id LIMIT 1');
  return { districtId: d.id as number, areaId: a.id as number, businessTypeId: t.id as number };
}

/** صاحب محل أرسل طلبه للمراجعة */
async function submittedShop(phone: string) {
  const owner = await register(phone, `owner-${phone}`);
  await v1('PUT', '/owner/shop', owner.token, { name: `محل ${phone}`, ...(await refs()), latitude: 30.5, longitude: 47.8 });
  await v1('POST', '/owner/services', owner.token, { name: 'حلاقة', durationMinutes: 30, priceType: 'fixed', price: 10000 });
  await v1('PUT', '/owner/hours', owner.token, {
    periods: [0, 1, 2, 3, 4, 5, 6].map((d) => ({ dayOfWeek: d, from: '09:00', to: '21:00' })),
  });
  const submit = await v1('POST', '/owner/shop/submit', owner.token);
  expect(submit.statusCode).toBe(200);
  const shop = (await v1('GET', '/owner/shop', owner.token)).json().shop;
  return { token: owner.token, userId: owner.user.id, shopId: shop.id as number };
}

async function ownerNotifications(token: string): Promise<string[]> {
  const res = await v1('GET', '/me/notifications?audience=shop', token);
  return res.json().notifications.map((n: { type: string }) => n.type);
}

describe('passwords', () => {
  it('hashes and verifies', async () => {
    const hash = await hashPassword('secret-password');
    expect(hash.startsWith('scrypt$')).toBe(true);
    expect(await verifyPassword('secret-password', hash)).toBe(true);
    expect(await verifyPassword('wrong-password', hash)).toBe(false);
    expect(await verifyPassword('anything', 'garbage')).toBe(false);
  });

  it('creates the first admin from environment variables only once', async () => {
    expect(await bootstrapAdmin(pool, 'second', 'another-password')).toBe(false); // يوجد حساب مسبقاً
    expect(await bootstrapAdmin(pool, undefined, undefined)).toBe(false);
  });
});

describe('admin login', () => {
  it('serves the panel page', async () => {
    const res = await app.inject({ method: 'GET', url: '/admin' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('لوحة إدارة حجز');
  });

  it('rejects wrong passwords and requests without a session', async () => {
    const bad = await admin('POST', '/login', { username: 'abbas', password: 'wrong' }, null);
    expect(bad.statusCode).toBe(401);
    expect(bad.json().error.code).toBe('invalid_login');
    expect((await admin('GET', '/stats', undefined, null)).statusCode).toBe(401);
    expect((await admin('GET', '/stats', undefined, 'not-a-token')).statusCode).toBe(401);
  });

  it('logs in and reads stats', async () => {
    const res = await admin('POST', '/login', { username: 'abbas', password: 'correct-horse-battery' }, null);
    expect(res.statusCode).toBe(200);
    adminToken = res.json().token;
    const stats = await admin('GET', '/stats');
    expect(stats.statusCode).toBe(200);
    expect(stats.json()).toMatchObject({ pendingShops: 0, activeShops: 0 });
  });

  it('refuses disabled admins', async () => {
    await pool.query('INSERT INTO admins (username, password_hash, disabled_at) VALUES ($1, $2, now())', [
      'old',
      await hashPassword('old-password-123'),
    ]);
    const res = await admin('POST', '/login', { username: 'old', password: 'old-password-123' }, null);
    expect(res.statusCode).toBe(401);
  });

  it('logs out', async () => {
    const login = await admin('POST', '/login', { username: 'abbas', password: 'correct-horse-battery' }, null);
    const token = login.json().token as string;
    expect((await admin('POST', '/logout', undefined, token)).statusCode).toBe(200);
    expect((await admin('GET', '/stats', undefined, token)).statusCode).toBe(401);
  });
});

describe('shop review', () => {
  it('lists shops waiting for review, oldest first, with details', async () => {
    const a = await submittedShop('07700000101');
    const b = await submittedShop('07700000102');
    const list = await admin('GET', '/shops?status=under_review');
    const ids = list.json().shops.map((s: { id: number }) => s.id);
    expect(ids).toEqual([a.shopId, b.shopId]);

    const details = await admin('GET', `/shops/${a.shopId}`);
    expect(details.statusCode).toBe(200);
    expect(details.json()).toMatchObject({ status: 'under_review', ownerPhone: '9647700000101' });
    expect(details.json().services).toHaveLength(1);
    expect(details.json().weeklyHours).toHaveLength(7);
    expect((await admin('GET', '/stats')).json().pendingShops).toBe(2);
  });

  it('rejects with a required note, notifies the owner, and the owner can resubmit', async () => {
    const shop = await submittedShop('07700000103');
    const noNote = await admin('POST', `/shops/${shop.shopId}/reject`, {});
    expect(noNote.statusCode).toBe(400);
    expect(noNote.json().error.code).toBe('note_required');

    const res = await admin('POST', `/shops/${shop.shopId}/reject`, { note: 'أضف صورة واضحة للواجهة' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'rejected', reviewNote: 'أضف صورة واضحة للواجهة', reviewedBy: 'abbas' });
    expect(await ownerNotifications(shop.token)).toContain('shop_rejected');

    const ownerView = (await v1('GET', '/owner/shop', shop.token)).json().shop;
    expect(ownerView.reviewNote).toBe('أضف صورة واضحة للواجهة');

    expect((await v1('POST', '/owner/shop/submit', shop.token)).statusCode).toBe(200);
    expect((await admin('GET', `/shops/${shop.shopId}`)).json().status).toBe('under_review');
  });

  it('approves: the shop becomes visible to customers and the owner is notified', async () => {
    const shop = await submittedShop('07700000104');
    const res = await admin('POST', `/shops/${shop.shopId}/approve`, {});
    expect(res.statusCode).toBe(200);
    expect(res.json().status).toBe('approved');
    expect(res.json().reviewNote).toBeNull();
    expect(await ownerNotifications(shop.token)).toContain('shop_approved');

    const visible = (await v1('GET', '/shops')).json().shops.map((s: { id: number }) => s.id);
    expect(visible).toContain(shop.shopId);

    // لا يمكن الموافقة مرتين
    const again = await admin('POST', `/shops/${shop.shopId}/approve`, {});
    expect(again.statusCode).toBe(409);
    expect(again.json().error.code).toBe('invalid_transition');
  });

  it('suspends and reinstates, hiding the shop meanwhile', async () => {
    const shop = await submittedShop('07700000105');
    await admin('POST', `/shops/${shop.shopId}/approve`, {});
    expect((await admin('POST', `/shops/${shop.shopId}/suspend`, {})).statusCode).toBe(400);

    const suspended = await admin('POST', `/shops/${shop.shopId}/suspend`, { note: 'شكاوى متكررة' });
    expect(suspended.json().status).toBe('suspended');
    const hidden = (await v1('GET', '/shops')).json().shops.map((s: { id: number }) => s.id);
    expect(hidden).not.toContain(shop.shopId);
    expect(await ownerNotifications(shop.token)).toContain('shop_suspended');

    const back = await admin('POST', `/shops/${shop.shopId}/reinstate`, {});
    expect(back.json().status).toBe('approved');
    expect(back.json().history.map((h: { action: string }) => h.action)).toEqual(['reinstate', 'suspend', 'approve']);
  });

  it('returns 404 for unknown shops', async () => {
    expect((await admin('GET', '/shops/999999')).statusCode).toBe(404);
    expect((await admin('POST', '/shops/999999/approve', {})).statusCode).toBe(404);
  });
});

describe('area requests', () => {
  it('approves a request into a real area, with an optional corrected name', async () => {
    const owner = await register('07700000201', 'owner-area');
    const { districtId } = await refs();
    expect((await v1('POST', '/owner/area-requests', owner.token, { districtId, name: 'الجزاير' })).statusCode).toBe(200);

    const list = (await admin('GET', '/area-requests')).json().requests;
    expect(list).toHaveLength(1);
    const res = await admin('POST', `/area-requests/${list[0].id}/approve`, { name: 'الجزائر' });
    expect(res.statusCode).toBe(200);
    const { rows } = await pool.query('SELECT name FROM areas WHERE id = $1', [res.json().areaId]);
    expect(rows[0].name).toBe('الجزائر');
    expect((await admin('GET', '/area-requests')).json().requests).toHaveLength(0);
  });

  it('rejects a request', async () => {
    const owner = await register('07700000202', 'owner-area-2');
    const { districtId } = await refs();
    await v1('POST', '/owner/area-requests', owner.token, { districtId, name: 'منطقة غير موجودة' });
    const [req] = (await admin('GET', '/area-requests')).json().requests;
    expect((await admin('POST', `/area-requests/${req.id}/reject`)).statusCode).toBe(200);
    expect((await admin('POST', `/area-requests/${req.id}/reject`)).statusCode).toBe(404);
  });
});

describe('users and devices', () => {
  it('trusts a second device so the owner can manage the shop from a new phone', async () => {
    const shop = await submittedShop('07700000301');
    const second = await register('07700000301', 'new-phone');
    expect((await v1('GET', '/owner/dashboard', second.token)).statusCode).toBe(403);

    const user = (await admin('GET', `/users/${shop.userId}`)).json();
    expect(user.devices).toHaveLength(2);
    const newDevice = user.devices.find((d: { trusted: boolean }) => !d.trusted);
    expect((await admin('POST', `/devices/${newDevice.id}/trust`)).statusCode).toBe(200);

    const after = (await admin('GET', `/users/${shop.userId}`)).json();
    expect(after.devices.every((d: { trusted: boolean }) => d.trusted)).toBe(true);
    expect((await v1('GET', '/owner/shop', second.token)).statusCode).toBe(200);
  });

  it('bans and unbans a user', async () => {
    const user = await register('07700000302', 'ban-me');
    expect((await v1('GET', '/me/bookings', user.token)).statusCode).toBe(200);
    expect((await admin('POST', `/users/${user.user.id}/ban`, { note: 'إساءة' })).statusCode).toBe(200);
    expect((await v1('GET', '/me/bookings', user.token)).statusCode).toBe(401);
    expect((await admin('POST', `/users/${user.user.id}/ban`, {})).statusCode).toBe(409);
    expect((await admin('POST', `/users/${user.user.id}/unban`, {})).statusCode).toBe(200);
    expect((await v1('GET', '/me/bookings', user.token)).statusCode).toBe(200);
  });

  it('searches users by phone', async () => {
    const res = await admin('GET', '/users?q=7700000302');
    expect(res.json().users.map((u: { phone: string }) => u.phone)).toEqual(['9647700000302']);
  });
});

describe('catalog', () => {
  it('adds and hides business types and areas', async () => {
    const created = await admin('POST', '/business-types', { name: 'غسيل سيارات' });
    expect(created.statusCode).toBe(200);
    expect((await admin('POST', '/business-types', { name: 'غسيل سيارات' })).statusCode).toBe(409);
    expect((await admin('PATCH', `/business-types/${created.json().id}`, { active: false })).statusCode).toBe(200);

    const config = (await v1('GET', '/config')).json();
    const typeNames = JSON.stringify(config);
    expect(typeNames).not.toContain('غسيل سيارات');

    const { districtId } = await refs();
    const area = await admin('POST', '/areas', { districtId, name: 'الطويسة' });
    expect(area.statusCode).toBe(200);
    expect((await admin('POST', '/areas', { districtId: 99999, name: 'لا قضاء' })).statusCode).toBe(400);
    const catalog = (await admin('GET', '/catalog')).json();
    expect(catalog.areas.map((a: { name: string }) => a.name)).toContain('الطويسة');
  });
});

describe('settings', () => {
  it('only accepts values with the same shape', () => {
    expect(sameShape(180, 240)).toBe(true);
    expect(sameShape(180, -1)).toBe(false);
    expect(sameShape(180, '240')).toBe(false);
    expect(sameShape({ a: 1, b: 2 }, { b: 3, a: 4 })).toBe(true);
    expect(sameShape({ a: 1, b: 2 }, { a: 1 })).toBe(false);
    expect(sameShape({ a: 1 }, { a: 1, c: 2 })).toBe(false);
    expect(sameShape([1, 2], [6, 12, 24])).toBe(true);
    expect(sameShape([1, 2], [])).toBe(false);
  });

  it('updates a setting and applies it immediately', async () => {
    expect((await admin('PUT', '/settings/min_lead_minutes', { value: 120 })).statusCode).toBe(200);
    const { rows } = await pool.query(`SELECT value FROM settings WHERE key = 'min_lead_minutes'`);
    expect(rows[0].value).toBe(120);
    expect((await admin('PUT', '/settings/min_lead_minutes', { value: 'abc' })).statusCode).toBe(400);
    expect((await admin('PUT', '/settings/no_such_key', { value: 1 })).statusCode).toBe(404);
    expect((await admin('PUT', '/settings/display_timezone', { value: 'UTC' })).statusCode).toBe(403);
  });

  it('updates app versions, refusing a minimum newer than the latest', async () => {
    expect((await admin('PUT', '/app-versions/android', { minVersion: '0.2.0', latestVersion: '0.1.0' })).statusCode).toBe(400);
    expect((await admin('PUT', '/app-versions/android', { minVersion: '0.1.0', latestVersion: '0.2.0' })).statusCode).toBe(200);
    const versions = (await admin('GET', '/app-versions')).json().versions;
    expect(versions.find((v: { platform: string }) => v.platform === 'android')).toMatchObject({ latestVersion: '0.2.0' });
  });

  it('records every action in the log', async () => {
    const actions = (await admin('GET', '/actions')).json().actions;
    const kinds = new Set(actions.map((a: { targetType: string }) => a.targetType));
    for (const k of ['shop', 'area_request', 'device', 'user', 'business_type', 'setting', 'app_version']) expect(kinds).toContain(k);
    expect(actions.every((a: { username: string }) => a.username === 'abbas')).toBe(true);
  });
});
