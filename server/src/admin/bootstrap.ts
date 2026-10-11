import type { Pool } from '../db/pool.js';
import { hashPassword } from './auth.js';

/**
 * ينشئ أول حساب للوحة الإدارة من متغيرات البيئة، فقط إذا لم يوجد أي حساب بعد.
 * بعد أول دخول ناجح يُحذف المتغيران من المنصة، ولا يحدث شيء في التشغيلات اللاحقة.
 */
export async function bootstrapAdmin(pool: Pool, username?: string, password?: string): Promise<boolean> {
  if (!username || !password) return false;
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM admins');
  if (rows[0].n > 0) return false;
  const hash = await hashPassword(password);
  const res = await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2) ON CONFLICT (username) DO NOTHING', [
    username,
    hash,
  ]);
  return (res.rowCount ?? 0) > 0;
}
