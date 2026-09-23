import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { authOf, requireAuth } from '../auth/hook.js';
import { loadShop, slotsForDate } from '../booking/availability.js';
import {
  acceptBooking,
  cancelByShop,
  markCompleted,
  markNoShow,
  proposeTimes,
  rejectBooking,
} from '../booking/bookings.js';
import { loadSettings } from '../booking/settings.js';
import { isLocalDate, minutesBetween } from '../booking/time.js';
import { AppError } from '../lib/errors.js';
import { idempotent } from '../lib/idempotency.js';
import { ownerBooking, ownerDashboard, ownerDay, verifyCustomerDevice } from '../owner/bookings.js';
import { createClosure, deleteClosure } from '../owner/closures.js';
import {
  addPhoto,
  addService,
  addTemporarySchedule,
  deletePhoto,
  deleteTemporarySchedule,
  getOwnerShop,
  missingForReview,
  requestArea,
  requireShop,
  saveShopDetails,
  setWeeklyHours,
  submitForReview,
  updateBookingSettings,
  updateService,
} from '../owner/shop.js';

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const r = schema.safeParse(value);
  if (!r.success) throw new AppError(400, 'invalid_request');
  return r.data;
}

const id = z.coerce.number().int().positive();
const idParams = z.object({ id });
const nullableText = (max: number) => z.string().trim().max(max).nullable().optional();
const period = z.object({ dayOfWeek: z.number().int(), from: z.string(), to: z.string() });

const detailsBody = z.object({
  name: z.string().trim().min(2).max(60).optional(),
  businessTypeId: id.nullable().optional(),
  description: nullableText(500),
  phone: nullableText(20),
  districtId: id.nullable().optional(),
  areaId: id.nullable().optional(),
  street: nullableText(100),
  landmark: nullableText(100),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
}).refine((b) => (b.latitude === undefined) === (b.longitude === undefined));

const serviceBody = z.object({
  name: z.string().max(60),
  durationMinutes: z.number().int(),
  priceType: z.enum(['fixed', 'starts_from', 'after_inspection']),
  price: z.number().int().nullable(),
  active: z.boolean().optional(),
});

const settingsBody = z.object({
  deadlineMode: z.enum(['fast', 'normal', 'flexible']).optional(),
  freeCancelHours: z.number().int().optional(),
  instantBooking: z.boolean().optional(),
  bufferMinutes: z.number().int().optional(),
  minLeadMinutes: z.number().int().optional(),
});

const reasonBody = z.object({ reason: z.string().trim().min(1).max(60) });
const datetime = z.iso.datetime({ offset: true }).transform((s) => new Date(s));

export async function ownerRoutes(app: FastifyInstance) {
  app.addHook('onRequest', requireAuth(app.pool));
  const owner = (request: FastifyRequest) => authOf(request).userId;

  const shopView = async (ownerId: number) => {
    const shop = await getOwnerShop(app.pool, ownerId);
    return { shop, missing: shop ? await missingForReview(app.pool, shop.id) : [] };
  };

  // ---------------- طلب فتح المحل وإدارته ----------------

  app.get('/owner/shop', async (request) => shopView(owner(request)));

  app.put('/owner/shop', async (request) => {
    await saveShopDetails(app.pool, owner(request), parse(detailsBody, request.body));
    return shopView(owner(request));
  });

  app.post('/owner/shop/submit', async (request) => {
    await submitForReview(app.pool, owner(request));
    return shopView(owner(request));
  });

  app.post('/owner/services', async (request) => {
    await addService(app.pool, owner(request), parse(serviceBody, request.body));
    return shopView(owner(request));
  });

  app.put('/owner/services/:id', async (request) => {
    await updateService(app.pool, owner(request), parse(idParams, request.params).id, parse(serviceBody, request.body));
    return shopView(owner(request));
  });

  app.put('/owner/hours', async (request) => {
    const { periods } = parse(z.object({ periods: z.array(period).max(50) }), request.body);
    await setWeeklyHours(app.pool, owner(request), periods);
    return shopView(owner(request));
  });

  app.post('/owner/temporary-schedules', async (request) => {
    const body = parse(
      z.object({ name: z.string().max(40), fromDate: z.string(), toDate: z.string(), periods: z.array(period).max(50) }),
      request.body,
    );
    await addTemporarySchedule(app.pool, owner(request), body);
    return shopView(owner(request));
  });

  app.delete('/owner/temporary-schedules/:id', async (request) => {
    await deleteTemporarySchedule(app.pool, owner(request), parse(idParams, request.params).id);
    return shopView(owner(request));
  });

  app.put('/owner/settings', async (request) => {
    await updateBookingSettings(app.pool, owner(request), parse(settingsBody, request.body));
    return shopView(owner(request));
  });

  // الصور تصل مصغّرة من التطبيق بصيغة base64
  app.post('/owner/photos', { bodyLimit: 3 * 1024 * 1024 }, async (request) => {
    const body = parse(z.object({ contentType: z.string(), data: z.string().max(2_500_000) }), request.body);
    await addPhoto(app.pool, owner(request), body.contentType, body.data);
    return shopView(owner(request));
  });

  app.delete('/owner/photos/:id', async (request) => {
    await deletePhoto(app.pool, owner(request), parse(idParams, request.params).id);
    return shopView(owner(request));
  });

  app.post('/owner/area-requests', async (request) => {
    const body = parse(z.object({ districtId: id, name: z.string() }), request.body);
    await requestArea(app.pool, owner(request), body.districtId, body.name);
    return { ok: true };
  });

  app.post('/owner/closures', async (request) => {
    const body = parse(z.object({ startsAt: datetime, endsAt: datetime, reason: z.string().max(100).optional() }), request.body);
    return idempotent(app.pool, request, owner(request), () =>
      createClosure(app.pool, owner(request), { ...body, now: new Date() }),
    );
  });

  app.delete('/owner/closures/:id', async (request) => {
    await deleteClosure(app.pool, owner(request), parse(idParams, request.params).id);
    return shopView(owner(request));
  });

  // ---------------- الطلبات والحجوزات ----------------

  app.get('/owner/dashboard', async (request) => {
    const shop = await requireShop(app.pool, owner(request));
    return { ...(await ownerDashboard(app.pool, shop, new Date())), serverTime: new Date().toISOString() };
  });

  app.get('/owner/day', async (request) => {
    const { date } = parse(z.object({ date: z.string().refine(isLocalDate) }), request.query);
    const shop = await requireShop(app.pool, owner(request));
    return { date, bookings: await ownerDay(app.pool, shop, date), serverTime: new Date().toISOString() };
  });

  const view = async (request: FastifyRequest, bookingId: number) => {
    const shop = await requireShop(app.pool, owner(request));
    return { booking: await ownerBooking(app.pool, shop, bookingId), serverTime: new Date().toISOString() };
  };

  app.get('/owner/bookings/:id', async (request) => view(request, parse(idParams, request.params).id));

  /** أوقات متاحة لاقتراحها بديلاً: بمدة الحجز نفسه، ولا يُحسب الحجز نفسه مشغولاً. */
  app.get('/owner/bookings/:id/slots', async (request) => {
    const bookingId = parse(idParams, request.params).id;
    const { date } = parse(z.object({ date: z.string().refine(isLocalDate) }), request.query);
    const owned = await requireShop(app.pool, owner(request));
    const { rows } = await app.pool.query(
      'SELECT starts_at, ends_at FROM bookings WHERE id = $1 AND shop_id = $2',
      [bookingId, owned.id],
    );
    if (!rows[0]) throw new AppError(404, 'booking_not_found');
    const now = new Date();
    const slots = await slotsForDate(app.pool, {
      shop: await loadShop(app.pool, owned.id),
      durationMinutes: minutesBetween(rows[0].starts_at, rows[0].ends_at),
      date,
      now,
      settings: await loadSettings(app.pool),
      excludeBookingId: bookingId,
    });
    return { date, slots: slots.map((s) => s.toISOString()) };
  });

  const action = (path: string, run: (request: FastifyRequest, bookingId: number, ownerId: number, now: Date) => Promise<unknown>) => {
    app.post(`/owner/bookings/:id/${path}`, async (request) => {
      const bookingId = parse(idParams, request.params).id;
      const ownerId = owner(request);
      await view(request, bookingId);
      return idempotent(app.pool, request, ownerId, async () => {
        await run(request, bookingId, ownerId, new Date());
        return view(request, bookingId);
      });
    });
  };

  action('accept', (_r, bookingId, ownerId, now) => acceptBooking(app.pool, { bookingId, ownerId, now }));
  action('reject', (r, bookingId, ownerId, now) =>
    rejectBooking(app.pool, { bookingId, ownerId, now, reason: parse(reasonBody, r.body).reason }));
  action('propose', (r, bookingId, ownerId, now) => {
    const body = parse(z.object({ times: z.array(datetime).min(1).max(3), message: z.string().max(200).optional() }), r.body);
    return proposeTimes(app.pool, { bookingId, ownerId, now, ...body });
  });
  action('cancel', (r, bookingId, ownerId, now) =>
    cancelByShop(app.pool, { bookingId, ownerId, now, reason: parse(reasonBody, r.body).reason }));
  action('no-show', (_r, bookingId, ownerId, now) => markNoShow(app.pool, { bookingId, ownerId, now }));
  action('complete', (_r, bookingId, ownerId, now) => markCompleted(app.pool, { bookingId, ownerId, now }));
  action('verify-device', async (_r, bookingId, ownerId) =>
    verifyCustomerDevice(app.pool, await requireShop(app.pool, ownerId), bookingId));
}

/** صور المحلات؛ خارج /v1 لأن الصور تُطلب مباشرة دون ترويسات الإصدار. */
export async function photoRoutes(app: FastifyInstance) {
  app.get('/photos/:id', async (request, reply) => {
    const { id: photoId } = parse(idParams, request.params);
    const { rows } = await app.pool.query(
      `SELECT p.data, p.content_type FROM shop_photos p JOIN shops s ON s.id = p.shop_id
       WHERE p.id = $1 AND p.data IS NOT NULL`,
      [photoId],
    );
    if (!rows[0]) throw new AppError(404, 'not_found');
    return reply
      .header('content-type', rows[0].content_type)
      .header('cache-control', 'public, max-age=86400')
      .send(rows[0].data);
  });
}
