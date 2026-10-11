import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassword } from '../src/admin/auth.js';
import { buildApp } from '../src/app.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let adminToken: string;
let ipCounter = 0;

/** كل طلب من عنوان مختلف، إلا إذا حُدد، حتى لا يتدخل حد المحاولات */
function submit(body: unknown, ip = `10.0.0.${++ipCounter}`) {
  return app.inject({ method: 'POST', url: '/delete-account', payload: body as object, remoteAddress: ip });
}

function admin(method: 'GET' | 'POST', url: string, body?: unknown) {
  return app.inject({ method, url: `/admin/api${url}`, headers: { authorization: `Bearer ${adminToken}` }, payload: body as object | undefined });
}

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', ['abbas', await hashPassword('correct-horse-battery')]);
  adminToken = (await app.inject({ method: 'POST', url: '/admin/api/login', payload: { username: 'abbas', password: 'correct-horse-battery' } })).json().token;
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('account deletion page', () => {
  it('serves the page', async () => {
    const res = await app.inject({ method: 'GET', url: '/delete-account' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/html');
    expect(res.body).toContain('حذف حسابك');
  });

  it('rejects a bad number and answers the same whether or not an account exists', async () => {
    expect((await submit({ phone: '12345' })).json().error.code).toBe('invalid_phone');
    const unknown = await submit({ phone: '0770 000 0999' });
    expect(unknown.statusCode).toBe(200);
    expect(unknown.json()).toEqual({ ok: true });
  });

  it('ignores bots that fill the hidden field', async () => {
    await submit({ phone: '07700000998', website: 'spam' });
    const { rowCount } = await pool.query(`SELECT 1 FROM deletion_requests WHERE phone = '07700000998'`);
    expect(rowCount).toBe(0);
  });

  it('limits attempts per address', async () => {
    for (let i = 0; i < 5; i++) await submit({ phone: '12' }, '10.9.9.9');
    expect((await submit({ phone: '07700000997' }, '10.9.9.9')).statusCode).toBe(429);
  });

  it('lets the admin delete the account after calling, then keeps only the last digits', async () => {
    const reg = await app.inject({
      method: 'POST', url: '/v1/auth/register', headers: appHeaders,
      payload: { name: 'علي حسين', phone: '07700000901', deviceIdentifier: 'device-07700000901' },
    });
    const userId = reg.json().user.id as number;

    await submit({ phone: '+964 770 000 0901', name: 'علي' });
    await submit({ phone: '07700000901', note: 'لا أستخدم التطبيق' });

    const { requests } = (await admin('GET', '/deletion-requests')).json();
    const mine = requests.filter((r: { phone: string }) => r.phone === '07700000901');
    expect(mine).toHaveLength(1);
    expect(mine[0]).toMatchObject({ userId, userName: 'علي حسين', name: 'علي', note: 'لا أستخدم التطبيق', upcomingBookings: 0, shop: null });
    expect((await admin('GET', '/stats')).json().pendingDeletions).toBe(2);

    expect((await admin('POST', `/deletion-requests/${mine[0].id}/delete`)).statusCode).toBe(200);
    const { rows: [u] } = await pool.query('SELECT deleted_at, phone FROM users WHERE id = $1', [userId]);
    expect(u.deleted_at).not.toBeNull();

    const resolved = (await admin('GET', '/deletion-requests?status=resolved')).json().requests;
    expect(resolved[0]).toMatchObject({ phone: '*******0901', status: 'done', resolvedBy: 'abbas' });
    const { rowCount } = await pool.query(`SELECT 1 FROM deletion_requests WHERE phone = '07700000901'`);
    expect(rowCount).toBe(0);
  });

  it('cannot delete when no account has the number; the admin rejects instead', async () => {
    const { requests } = (await admin('GET', '/deletion-requests')).json();
    const r = requests.find((x: { phone: string }) => x.phone === '07700000999');
    expect(r.userId).toBeNull();
    const res = await admin('POST', `/deletion-requests/${r.id}/delete`);
    expect(res.json().error.code).toBe('account_not_found');
    expect((await admin('POST', `/deletion-requests/${r.id}/reject`, { note: 'لا يوجد حساب' })).statusCode).toBe(200);
    expect((await admin('GET', '/stats')).json().pendingDeletions).toBe(0);
  });
});

describe('privacy page', () => {
  const page = async () => (await app.inject({ method: 'GET', url: '/privacy' })).body;

  it('points to the deletion page until a contact email is set', async () => {
    const html = await page();
    expect(html).toContain('سياسة الخصوصية');
    expect(html).not.toContain('{{CONTACT}}');
    expect(html).toContain('href="/delete-account"');
    expect(html).not.toContain('mailto:');
  });

  it('shows the contact email from settings, and never injects markup', async () => {
    await pool.query(`UPDATE settings SET value = '"help@example.com"' WHERE key = 'contact_email'`);
    expect(await page()).toContain('href="mailto:help@example.com"');

    await pool.query(`UPDATE settings SET value = $1 WHERE key = 'contact_email'`, [JSON.stringify('<script>x</script>@a.b')]);
    const html = await page();
    expect(html).not.toContain('<script>x');
    expect(html).not.toContain('mailto:');
  });
});
