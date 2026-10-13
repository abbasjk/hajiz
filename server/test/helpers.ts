import { migrate } from '../src/db/migrate.js';
import { createPool, type Pool } from '../src/db/pool.js';

export const TEST_DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? 'postgres://hajiz:hajiz@localhost:5432/hajiz_test';

/** قاعدة اختبار نظيفة: يمسح المخطط ويعيد تطبيق كل الترحيلات. */
export async function freshDatabase(): Promise<Pool> {
  const pool = createPool(TEST_DATABASE_URL);
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  await migrate(pool);
  return pool;
}

export const appHeaders = { 'x-app-platform': 'android', 'x-app-version': '0.1.0' };

/** صورة صغيرة صالحة لاختبارات رفع صور المحل */
export const TINY_PNG = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a5d80000000049454e44ae426082',
  'hex',
).toString('base64');

/** نقاط التحقق التي تطلبها الموافقة على محل */
export const APPROVE_CHECKS = { checks: { called: true, location: true, photos: true } };
