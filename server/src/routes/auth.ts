import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { CODE_TTL_SECONDS, RESEND_AFTER_SECONDS, consumeCode, requestCode } from '../auth/codes.js';
import { registerDevice } from '../auth/devices.js';
import { requireAuth, authOf } from '../auth/hook.js';
import { AppError } from '../lib/errors.js';
import { clientIp } from '../lib/ip.js';
import { normalizeIraqiPhone } from '../lib/phone.js';

const body = z.object({
  name: z.string().trim().min(2).max(60),
  phone: z.string().max(30),
  deviceIdentifier: z.string().min(8).max(100),
  code: z.string().regex(/^\d{6}$/).optional(),
});

const codeBody = z.object({ phone: z.string().max(30) });

export async function authRoutes(app: FastifyInstance) {
  /** يرسل رمز التحقق؛ required=false إذا لم تُعدّ خدمة الرموز بعد (التسجيل يعمل دونه) */
  app.post('/auth/code', async (request) => {
    const parsed = codeBody.safeParse(request.body);
    if (!parsed.success) throw new AppError(400, 'invalid_request');
    const phone = normalizeIraqiPhone(parsed.data.phone);
    if (!phone) throw new AppError(400, 'invalid_phone');
    if (!app.codeSender) return { required: false };
    await requestCode(app.pool, app.codeSender, phone, clientIp(request), request.log);
    return { required: true, expiresIn: CODE_TTL_SECONDS, resendIn: RESEND_AFTER_SECONDS };
  });

  app.post('/auth/register', async (request) => {
    const parsed = body.safeParse(request.body);
    if (!parsed.success) throw new AppError(400, 'invalid_request');
    const phone = normalizeIraqiPhone(parsed.data.phone);
    if (!phone) throw new AppError(400, 'invalid_phone');
    const { code, ...rest } = parsed.data;
    if (app.codeSender) {
      if (!code) throw new AppError(400, 'code_required');
      await consumeCode(app.pool, phone, code);
    }
    return registerDevice(app.pool, { ...rest, phone, phoneVerified: Boolean(app.codeSender) });
  });

  app.get('/me', { onRequest: requireAuth(app.pool) }, async (request) => {
    const auth = authOf(request);
    const { rows } = await app.pool.query(
      `SELECT u.id, u.name, u.phone, d.trust_requested_at IS NOT NULL AS "trustRequested"
       FROM users u JOIN devices d ON d.id = $2 WHERE u.id = $1`,
      [auth.userId, auth.deviceId],
    );
    const { trustRequested, ...user } = rows[0];
    return { user, trustedDevice: auth.trusted, trustRequested: !auth.trusted && trustRequested };
  });
}
