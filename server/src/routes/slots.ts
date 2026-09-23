import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { availableSlots } from '../booking/availability.js';
import { isLocalDate } from '../booking/time.js';
import { AppError } from '../lib/errors.js';

const params = z.object({ shopId: z.coerce.number().int().positive() });
const query = z.object({
  date: z.string().refine(isLocalDate),
  // أرقام الخدمات مفصولة بفواصل: services=3,7
  services: z.string().regex(/^\d+(,\d+)*$/).transform((s) => s.split(',').map(Number)),
});

export async function slotRoutes(app: FastifyInstance) {
  // الأوقات المتاحة ليوم واحد، تُعرض للزبون بلا حساب
  app.get('/shops/:shopId/slots', async (request) => {
    const p = params.safeParse(request.params);
    const q = query.safeParse(request.query);
    if (!p.success || !q.success) throw new AppError(400, 'invalid_request');
    const result = await availableSlots(app.pool, {
      shopId: p.data.shopId,
      serviceIds: q.data.services,
      date: q.data.date,
      now: new Date(),
    });
    return {
      date: q.data.date,
      durationMinutes: result.durationMinutes,
      slots: result.slots.map((s) => s.toISOString()),
    };
  });
}
