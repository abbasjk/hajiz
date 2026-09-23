import type { FastifyRequest } from 'fastify';
import type { Pool } from '../db/pool.js';
import { AppError } from './errors.js';

/**
 * منع الإرسال المكرر: الطلب يحمل Idempotency-Key فريداً من التطبيق.
 * إذا وصل المفتاح نفسه مرة ثانية (ضغطتان أو إعادة إرسال بعد انقطاع) تُعاد النتيجة الأولى.
 * الأخطاء لا تُحفظ، فيمكن إعادة المحاولة بالمفتاح نفسه.
 */
export async function idempotent<T>(pool: Pool, request: FastifyRequest, userId: number, run: () => Promise<T>): Promise<T> {
  const key = request.headers['idempotency-key'];
  if (typeof key !== 'string' || key.length < 8 || key.length > 100) {
    throw new AppError(400, 'idempotency_key_required');
  }
  const previous = await pool.query<{ response_body: T }>(
    'SELECT response_body FROM idempotency_keys WHERE user_id = $1 AND key = $2',
    [userId, key],
  );
  if (previous.rows[0]) return previous.rows[0].response_body;

  const result = await run();
  await pool.query(
    `INSERT INTO idempotency_keys (user_id, key, response_code, response_body) VALUES ($1, $2, 200, $3)
     ON CONFLICT DO NOTHING`,
    [userId, key, JSON.stringify(result)],
  );
  return result;
}
