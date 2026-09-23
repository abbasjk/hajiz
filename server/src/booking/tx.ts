import type { Pool } from '../db/pool.js';
import type pg from 'pg';

export async function withTransaction<T>(pool: Pool, fn: (tx: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/** رمز PostgreSQL عند مخالفة قيد منع تداخل الحجوزات. */
export function isOverlapViolation(err: unknown): boolean {
  return (err as { code?: string }).code === '23P01';
}
