import type { Pool } from '../db/pool.js';
import { hashPassword } from './auth.js';

export const MIN_PASSWORD_LENGTH = 10;

export type BootstrapResult = 'created' | 'skipped' | 'exists' | 'invalid_username' | 'password_too_short';

/**
 * ينشئ أول حساب للوحة الإدارة من متغيرات البيئة، فقط إذا لم يوجد أي حساب بعد.
 * بعد أول دخول ناجح يُحذف المتغيران من المنصة، ولا يحدث شيء في التشغيلات اللاحقة.
 * قيمة غير صالحة لا توقف الخادم: تُسجّل في السجل فقط.
 */
export async function bootstrapAdmin(pool: Pool, username?: string, password?: string): Promise<BootstrapResult> {
  const name = username?.trim() ?? '';
  if (!name && !password) return 'skipped';
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM admins');
  if (rows[0].n > 0) return 'exists';
  if (name.length < 3 || name.length > 60) return 'invalid_username';
  if (!password || password.length < MIN_PASSWORD_LENGTH) return 'password_too_short';
  const res = await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2) ON CONFLICT (username) DO NOTHING', [
    name,
    await hashPassword(password),
  ]);
  return (res.rowCount ?? 0) > 0 ? 'created' : 'exists';
}
