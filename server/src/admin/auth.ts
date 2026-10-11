import { randomBytes, scrypt as scryptCb, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import type { FastifyRequest } from 'fastify';
import type { Pool } from '../db/pool.js';
import { hashToken, newToken } from '../auth/tokens.js';
import { AppError } from '../lib/errors.js';

const scrypt = promisify(scryptCb) as (password: string, salt: Buffer, keylen: number) => Promise<Buffer>;

/** مدة جلسة لوحة الإدارة */
export const SESSION_HOURS = 12;

declare module 'fastify' {
  interface FastifyRequest {
    adminId?: number;
  }
}

/** كلمة المرور تُحفظ مجزّأة بخوارزمية بطيئة: scrypt$الملح$البصمة */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, salt, hash] = stored.split('$');
  if (scheme !== 'scrypt' || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64');
  const actual = await scrypt(password, Buffer.from(salt, 'base64'), expected.length);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/** يعيد مفتاح جلسة جديداً، أو null إذا كانت البيانات خاطئة أو الحساب معطلاً. */
export async function login(pool: Pool, username: string, password: string): Promise<string | null> {
  const { rows } = await pool.query<{ id: number; password_hash: string; disabled_at: Date | null }>(
    'SELECT id, password_hash, disabled_at FROM admins WHERE username = $1',
    [username],
  );
  const admin = rows[0];
  // نتحقق دائماً حتى لا يكشف زمن الرد إن كان اسم المستخدم موجوداً
  const ok = await verifyPassword(password, admin?.password_hash ?? 'scrypt$AAAAAAAAAAAAAAAAAAAAAA==$' + 'A'.repeat(88));
  if (!admin || !ok || admin.disabled_at) return null;
  const token = newToken();
  await pool.query(
    `INSERT INTO admin_sessions (token_hash, admin_id, expires_at) VALUES ($1, $2, now() + make_interval(hours => $3))`,
    [hashToken(token), admin.id, SESSION_HOURS],
  );
  await pool.query('DELETE FROM admin_sessions WHERE expires_at < now()');
  return token;
}

export async function logout(pool: Pool, token: string) {
  await pool.query('DELETE FROM admin_sessions WHERE token_hash = $1', [hashToken(token)]);
}

export function bearer(request: FastifyRequest): string {
  const header = request.headers.authorization;
  return header?.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

/** يتطلب جلسة إدارة صالحة لحساب غير معطل. */
export function requireAdmin(pool: Pool) {
  return async (request: FastifyRequest) => {
    const token = bearer(request);
    if (!token) throw new AppError(401, 'unauthorized');
    const { rows } = await pool.query<{ admin_id: number }>(
      `SELECT s.admin_id FROM admin_sessions s JOIN admins a ON a.id = s.admin_id
       WHERE s.token_hash = $1 AND s.expires_at > now() AND a.disabled_at IS NULL`,
      [hashToken(token)],
    );
    if (!rows[0]) throw new AppError(401, 'unauthorized');
    request.adminId = rows[0].admin_id;
  };
}

/** حد بسيط لمحاولات الدخول الفاشلة لكل عنوان، يكفي لخادم واحد */
export class LoginLimiter {
  private readonly failures = new Map<string, number[]>();

  constructor(
    private readonly max = 10,
    private readonly windowMs = 15 * 60_000,
  ) {}

  private recent(key: string): number[] {
    const now = Date.now();
    const list = (this.failures.get(key) ?? []).filter((t) => now - t < this.windowMs);
    this.failures.set(key, list);
    return list;
  }

  blocked(key: string): boolean {
    return this.recent(key).length >= this.max;
  }

  fail(key: string) {
    this.recent(key).push(Date.now());
  }

  reset(key: string) {
    this.failures.delete(key);
  }
}
