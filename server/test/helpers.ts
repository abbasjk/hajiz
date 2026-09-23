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
