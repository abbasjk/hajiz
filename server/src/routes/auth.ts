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
    const { rows } = await app.pool.query('SELECT id, name, phone FROM users WHERE id = $1', [auth.userId]);
    return { user: rows[0], trustedDevice: auth.trusted };
  });
}
