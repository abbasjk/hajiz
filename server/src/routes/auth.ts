import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { registerDevice } from '../auth/devices.js';
import { requireAuth, authOf } from '../auth/hook.js';
import { AppError } from '../lib/errors.js';
import { normalizeIraqiPhone } from '../lib/phone.js';

const body = z.object({
  name: z.string().trim().min(2).max(60),
  phone: z.string().max(30),
  deviceIdentifier: z.string().min(8).max(100),
});

export async function authRoutes(app: FastifyInstance) {
  app.post('/auth/register', async (request) => {
    const parsed = body.safeParse(request.body);
    if (!parsed.success) throw new AppError(400, 'invalid_request');
    const phone = normalizeIraqiPhone(parsed.data.phone);
    if (!phone) throw new AppError(400, 'invalid_phone');
    return registerDevice(app.pool, { ...parsed.data, phone });
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
