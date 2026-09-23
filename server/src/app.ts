import Fastify, { type FastifyInstance } from 'fastify';
import type { Pool } from './db/pool.js';
import { AppError } from './lib/errors.js';
import { configRoutes } from './routes/config.js';
import { healthRoutes } from './routes/health.js';
import { slotRoutes } from './routes/slots.js';
import { versionCheck } from './lib/version-check.js';

export interface AppOptions {
  pool: Pool;
  logLevel?: string;
}

declare module 'fastify' {
  interface FastifyInstance {
    pool: Pool;
  }
}

export async function buildApp({ pool, logLevel = 'info' }: AppOptions): Promise<FastifyInstance> {
  const app = Fastify({ logger: { level: logLevel } });
  app.decorate('pool', pool);

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
  // كل مسارات التطبيق تحت /v1 وتمر بفحص الإصدار
  await app.register(
    async (v1) => {
      v1.addHook('onRequest', versionCheck(pool));
      await v1.register(configRoutes);
      await v1.register(slotRoutes);
    },
    { prefix: '/v1' },
  );

  return app;
}
