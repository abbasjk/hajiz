import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { authOf, requireAuth } from '../auth/hook.js';
import { cancelByCustomer, chooseProposedTime, createBooking, declineProposal } from '../booking/bookings.js';
import { getCustomerBooking, listCustomerBookings } from '../booking/customer-view.js';
import { AppError } from '../lib/errors.js';
import { idempotent } from '../lib/idempotency.js';

const createBody = z.object({
  shopId: z.number().int().positive(),
  serviceIds: z.array(z.number().int().positive()).min(1).max(10),
  startsAt: z.iso.datetime({ offset: true }),
  note: z.string().max(300).optional(),
});
const idParams = z.object({ bookingId: z.coerce.number().int().positive() });

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const r = schema.safeParse(value);
  if (!r.success) throw new AppError(400, 'invalid_request');
  return r.data;
}

export async function bookingRoutes(app: FastifyInstance) {
  app.addHook('onRequest', requireAuth(app.pool));

  const view = async (request: FastifyRequest, bookingId: number) => {
    const booking = await getCustomerBooking(app.pool, authOf(request), bookingId);
    if (!booking) throw new AppError(404, 'booking_not_found');
    return { booking, serverTime: new Date().toISOString() };
  };

  app.post('/bookings', async (request) => {
    const auth = authOf(request);
    const body = parse(createBody, request.body);
    return idempotent(app.pool, request, auth.userId, async () => {
      const created = await createBooking(app.pool, {
        customerId: auth.userId,
        deviceId: auth.deviceId,
        shopId: body.shopId,
        serviceIds: body.serviceIds,
        startsAt: new Date(body.startsAt),
        note: body.note,
        now: new Date(),
      });
      return view(request, created.id);
    });
  });

  // حجوزاتي: التطبيق يقسمها إلى قيد الانتظار، مؤكدة، سابقة؛ serverTime للعداد التنازلي
  app.get('/me/bookings', async (request) => ({
    bookings: await listCustomerBookings(app.pool, authOf(request)),
    serverTime: new Date().toISOString(),
  }));

  app.get('/bookings/:bookingId', async (request) => view(request, parse(idParams, request.params).bookingId));

  // كل إجراء يتحقق أولاً أن الحجز ظاهر لهذا الجهاز
  const action = (
    path: string,
    run: (request: FastifyRequest, bookingId: number, customerId: number) => Promise<unknown>,
  ) => {
    app.post(`/bookings/:bookingId/${path}`, async (request) => {
      const { bookingId } = parse(idParams, request.params);
      const auth = authOf(request);
      await view(request, bookingId);
      return idempotent(app.pool, request, auth.userId, async () => {
        await run(request, bookingId, auth.userId);
        return view(request, bookingId);
      });
    });
  };

  action('cancel', (_r, bookingId, customerId) => cancelByCustomer(app.pool, { bookingId, customerId, now: new Date() }));
  action('decline', (_r, bookingId, customerId) => declineProposal(app.pool, { bookingId, customerId, now: new Date() }));
  action('choose', (request, bookingId, customerId) => {
    const { proposedTimeId } = parse(z.object({ proposedTimeId: z.number().int().positive() }), request.body);
    return chooseProposedTime(app.pool, { bookingId, customerId, proposedTimeId, now: new Date() });
  });
}
