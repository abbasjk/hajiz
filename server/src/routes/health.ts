import type { FastifyInstance } from 'fastify';

export async function healthRoutes(app: FastifyInstance) {
  // تستخدمه منصة الاستضافة لمعرفة أن الخادم وقاعدة البيانات يعملان
  app.get('/health', async (_request, reply) => {
    try {
      await app.pool.query('SELECT 1');
      return { status: 'ok' };
    } catch {
      return reply.status(503).send({ status: 'unavailable' });
    }
  });
}
