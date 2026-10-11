import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassword } from '../src/admin/auth.js';
import { buildApp } from '../src/app.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let adminToken: string;

function call(method: 'GET' | 'POST', url: string, token?: string, body?: unknown) {
  const headers: Record<string, string> = { ...appHeaders };
  if (token) headers.authorization = `Bearer ${token}`;
  return app.inject({ method, url, headers, payload: body as object | undefined });
}

function admin(method: 'GET' | 'POST', url: string, body?: unknown) {
  return app.inject({ method, url: `/admin/api${url}`, headers: { authorization: `Bearer ${adminToken}` }, payload: (body ?? {}) as object });
}

async function register(device: string) {
  const res = await call('POST', '/v1/auth/register', undefined, { name: 'كرار جاسم', phone: '07700000951', deviceIdentifier: device });
  return res.json().token as string;
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

describe('trust requests', () => {
  let first: string;
  let second: string;

  it('a new phone for the same number starts untrusted and can ask to be trusted', async () => {
    first = await register('old-phone-device');
    second = await register('new-phone-device');
    expect((await call('GET', '/v1/me', second)).json()).toMatchObject({ trustedDevice: false, trustRequested: false });

    const already = await call('POST', '/v1/me/trust-request', first, {});
    expect(already.json().error.code).toBe('already_trusted');

    expect((await call('POST', '/v1/me/trust-request', second, { note: 'غيّرت هاتفي' })).statusCode).toBe(200);
    expect((await call('GET', '/v1/me', second)).json()).toMatchObject({ trustedDevice: false, trustRequested: true });

    const { requests } = (await admin('GET', '/trust-requests')).json();
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ name: 'كرار جاسم', phone: '07700000951', note: 'غيّرت هاتفي', shop: null });
    expect(requests[0].trustedLastSeen).not.toBeNull();
    expect((await admin('GET', '/stats')).json().pendingTrust).toBe(1);
  });

  it('the admin trusts it, the request clears, and the phone is told', async () => {
    const { requests } = (await admin('GET', '/trust-requests')).json();
    expect((await admin('POST', `/devices/${requests[0].id}/trust`)).statusCode).toBe(200);

    expect((await call('GET', '/v1/me', second)).json()).toMatchObject({ trustedDevice: true, trustRequested: false });
    expect((await admin('GET', '/trust-requests')).json().requests).toHaveLength(0);
    const notices = (await call('GET', '/v1/me/notifications?audience=customer', second)).json().notifications;
    expect(notices[0]).toMatchObject({ type: 'device_trusted', title: 'تم توثيق هاتفك' });
  });

  it('the admin can dismiss a request', async () => {
    const third = await register('third-phone-device');
    await call('POST', '/v1/me/trust-request', third, {});
    const { requests } = (await admin('GET', '/trust-requests')).json();
    expect((await admin('POST', `/trust-requests/${requests[0].id}/dismiss`, { note: 'لم يرد' })).statusCode).toBe(200);
    expect((await admin('GET', '/trust-requests')).json().requests).toHaveLength(0);
    expect((await call('GET', '/v1/me', third)).json()).toMatchObject({ trustedDevice: false, trustRequested: false });
  });
});
