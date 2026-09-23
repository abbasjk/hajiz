import Fastify, { type FastifyInstance } from 'fastify';
import type { Pool } from './db/pool.js';
import { AppError } from './lib/errors.js';
import { configRoutes } from './routes/config.js';
import { healthRoutes } from './routes/health.js';
import { slotRoutes } from './routes/slots.js';
import { authRoutes } from './routes/auth.js';
import { bookingRoutes } from './routes/bookings.js';
import { shopRoutes } from './routes/shops.js';
import { ownerRoutes, photoRoutes } from './routes/owner.js';
import { versionCheck } from './lib/version-check.js';
import { Notifier } from './notify/notifier.js';
import { LogSender, type PushSender } from './notify/sender.js';
import { bookingEvent, type BookingEvent } from './notify/events.js';
import { meRoutes } from './routes/me.js';

export interface AppOptions {
  pool: Pool;
  logLevel?: string;
  /** مرسل الإشعارات؛ الافتراضي يسجّلها فقط (قبل إعداد Firebase وفي الاختبارات) */
  sender?: PushSender;
}

declare module 'fastify' {
  interface FastifyInstance {
    pool: Pool;
    notifier: Notifier;
    /** يبلّغ الطرف الآخر بما حدث للحجز؛ لا يُفشل العملية إذا تعذر الإرسال */
    bookingEvent(bookingId: number, event: BookingEvent): Promise<unknown>;
  }
}

export async function buildApp({ pool, logLevel = 'info', sender }: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({ logger: { level: logLevel } });
  app.decorate('pool', pool);
  const notifier = new Notifier(pool, sender ?? new LogSender(app.log), app.log);
  app.decorate('notifier', notifier);
  app.decorate('bookingEvent', async (bookingId: number, event: BookingEvent) => {
    try {
      await bookingEvent(notifier, pool, bookingId, event);
    } catch (err) {
      app.log.error(err, 'booking event failed');
    }
  });

  app.setErrorHandler((err, request, reply) => {
    if (err instanceof AppError) {
      return reply.status(err.statusCode).send({ error: { code: err.code, ...err.details } });
    }
    const statusCode = (err as { statusCode?: number }).statusCode;
    if (statusCode && statusCode < 500) {
      return reply.status(statusCode).send({ error: { code: 'bad_request' } });
    }
    request.log.error(err);
    return reply.status(500).send({ error: { code: 'internal_error' } });
  });

  app.setNotFoundHandler((_request, reply) => {
    reply.status(404).send({ error: { code: 'not_found' } });
  });

  await app.register(healthRoutes);
  await app.register(photoRoutes);
  // كل مسارات التطبيق تحت /v1 وتمر بفحص الإصدار
  await app.register(
    async (v1) => {
      v1.addHook('onRequest', versionCheck(pool));
      await v1.register(configRoutes);
      await v1.register(slotRoutes);
      await v1.register(shopRoutes);
      await v1.register(authRoutes);
      await v1.register(bookingRoutes);
      await v1.register(ownerRoutes);
      await v1.register(meRoutes);
    },
    { prefix: '/v1' },
  );

  return app;
}
