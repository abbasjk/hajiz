import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { createOtpiqSender, type CodeSender } from '../src/auth/codes.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;
let plain: FastifyInstance;
const sent: { phone: string; code: string }[] = [];
let failNext = false;
const sender: CodeSender = {
  async send(phone, code) {
    if (failNext) {
      failNext = false;
      throw new Error('provider down');
    }
    sent.push({ phone, code });
  },
};

function call(target: FastifyInstance, method: 'GET' | 'POST', url: string, body?: unknown, ip = '10.0.0.1') {
  return target.inject({ method, url, headers: { ...appHeaders, 'x-forwarded-for': ip }, payload: body as object | undefined });
}

const lastCode = (phone: string) => sent.filter((s) => s.phone === phone).at(-1)!.code;
const wrong = (code: string) => (code === '000000' ? '111111' : '000000');

/** يجعل آخر رمز للرقم قديماً بما يكفي لطلب رمز جديد */
const ageCodes = (phone: string) =>
  pool.query(`UPDATE phone_codes SET created_at = created_at - interval '2 minutes' WHERE phone = $1`, [phone]);

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent', codeSender: sender });
  plain = await buildApp({ pool, logLevel: 'silent' });
});

afterAll(async () => {
  await app.close();
  await plain.close();
  await pool.end();
});

describe('phone codes', () => {
  it('without the code service, registration needs no code', async () => {
    expect((await call(plain, 'GET', '/v1/config')).json().phoneVerification).toBe(false);
    expect((await call(plain, 'POST', '/v1/auth/code', { phone: '07700000101' })).json()).toEqual({ required: false });
    const res = await call(plain, 'POST', '/v1/auth/register', { name: 'سجاد', phone: '07700000101', deviceIdentifier: 'plain-device-1' });
    expect(res.statusCode).toBe(200);
  });

  it('asks for a code, rejects a wrong one, and trusts the phone on the right one', async () => {
    expect((await call(app, 'GET', '/v1/config')).json().phoneVerification).toBe(true);
    const phone = '07700000102';
    const noCode = await call(app, 'POST', '/v1/auth/register', { name: 'زينب', phone, deviceIdentifier: 'code-device-1' });
    expect(noCode.json().error.code).toBe('code_required');

    const req = await call(app, 'POST', '/v1/auth/code', { phone: '0770 000 0102' });
    expect(req.json()).toMatchObject({ required: true, expiresIn: 600, resendIn: 60 });
    const code = lastCode(phone);
    expect(code).toMatch(/^\d{6}$/);
    const stored = await pool.query('SELECT code_hash FROM phone_codes WHERE phone = $1', [phone]);
    expect(stored.rows[0].code_hash).not.toContain(code);

    const bad = await call(app, 'POST', '/v1/auth/register', { name: 'زينب', phone, deviceIdentifier: 'code-device-1', code: wrong(code) });
    expect(bad.json().error.code).toBe('code_invalid');

    const ok = await call(app, 'POST', '/v1/auth/register', { name: 'زينب', phone, deviceIdentifier: 'code-device-1', code });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().trustedDevice).toBe(true);

    // الرمز يُستعمل مرة واحدة
    const again = await call(app, 'POST', '/v1/auth/register', { name: 'زينب', phone, deviceIdentifier: 'code-device-2', code });
    expect(again.json().error.code).toBe('code_expired');
  });

  it('a new phone for an existing number is trusted after the code, with no manual review', async () => {
    const phone = '07700000103';
    await call(plain, 'POST', '/v1/auth/register', { name: 'حيدر', phone, deviceIdentifier: 'old-phone-103' });
    const untrusted = await call(plain, 'POST', '/v1/auth/register', { name: 'حيدر', phone, deviceIdentifier: 'new-phone-103' });
    expect(untrusted.json().trustedDevice).toBe(false);

    await call(app, 'POST', '/v1/auth/code', { phone });
    const res = await call(app, 'POST', '/v1/auth/register', { name: 'حيدر', phone, deviceIdentifier: 'new-phone-103', code: lastCode(phone) });
    expect(res.json().trustedDevice).toBe(true);
  });

  it('limits resends, wrong attempts and requests per address', async () => {
    const phone = '07700000104';
    await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.4');
    const soon = await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.4');
    expect(soon.statusCode).toBe(429);
    expect(soon.json().error.code).toBe('code_too_soon');

    const code = lastCode(phone);
    for (let i = 0; i < 5; i++) {
      await call(app, 'POST', '/v1/auth/register', { name: 'علي', phone, deviceIdentifier: 'limit-device', code: wrong(code) });
    }
    const locked = await call(app, 'POST', '/v1/auth/register', { name: 'علي', phone, deviceIdentifier: 'limit-device', code });
    expect(locked.json().error.code).toBe('code_expired');

    for (let i = 0; i < 4; i++) {
      await ageCodes(phone);
      expect((await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.4')).statusCode).toBe(200);
    }
    await ageCodes(phone);
    expect((await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.4')).json().error.code).toBe('too_many_codes');

    for (let i = 0; i < 5; i++) await call(app, 'POST', '/v1/auth/code', { phone: `0770000020${i}` }, '10.0.0.9');
    for (let i = 5; i < 10; i++) await call(app, 'POST', '/v1/auth/code', { phone: `0770000020${i}` }, '10.0.0.9');
    const perIp = await call(app, 'POST', '/v1/auth/code', { phone: '07700000299' }, '10.0.0.9');
    expect(perIp.json().error.code).toBe('too_many_codes');
  });

  it('does not count a code the provider failed to send', async () => {
    const phone = '07700000105';
    failNext = true;
    const res = await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.5');
    expect(res.statusCode).toBe(502);
    expect(res.json().error.code).toBe('code_send_failed');
    expect((await call(app, 'POST', '/v1/auth/code', { phone }, '10.0.0.5')).statusCode).toBe(200);
  });

  it('sends the Iraqi number in international form to the provider', async () => {
    const requests: { url: string; body: Record<string, unknown>; auth: string }[] = [];
    const fake = (async (url: string, init: RequestInit) => {
      requests.push({ url, body: JSON.parse(init.body as string), auth: (init.headers as Record<string, string>).authorization! });
      return new Response('{"smsId":"x"}', { status: 200 });
    }) as unknown as typeof fetch;
    await createOtpiqSender('sk_test', 'whatsapp-sms', fake).send('07701234567', '123456');
    expect(requests[0]).toEqual({
      url: 'https://api.otpiq.com/api/sms',
      auth: 'Bearer sk_test',
      body: { phoneNumber: '9647701234567', smsType: 'verification', verificationCode: '123456', provider: 'whatsapp-sms' },
    });

    const failing = (async () => new Response('{"error":"Insufficient credit"}', { status: 400 })) as unknown as typeof fetch;
    await expect(createOtpiqSender('sk_test', 'sms', failing).send('07701234567', '1')).rejects.toThrow(/400/);
  });
});
