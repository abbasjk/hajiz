import type { Pool } from '../db/pool.js';
import { withTransaction } from '../booking/tx.js';
import { isTrustedDevice } from '../booking/bookings.js';
import { AppError } from '../lib/errors.js';
import { hashToken, newToken } from './tokens.js';

export interface RegisterInput {
  name: string;
  phone: string; // موحّد مسبقاً
  deviceIdentifier: string;
  gender?: 'male' | 'female';
  /** أثبت الرقم برمز تحقق: هذا الهاتف موثوق مباشرة */
  phoneVerified?: boolean;
}

export interface RegisterResult {
  token: string;
  user: { id: number; name: string; phone: string; gender: string | null };
  trustedDevice: boolean;
}

/**
 * التسجيل عند أول حجز أو أول دخول. الرقم فريد.
 * - برمز تحقق (حين تكون خدمة الرموز مُعدّة): الهاتف موثوق مباشرة أياً كان.
 * - رقم جديد: يُحفظ الرقم والاسم والجهاز معاً، وهذا الجهاز موثوق.
 * - رقم موجود من جهاز آخر: يُسمح، لكن الجهاز الجديد غير موثوق حتى يؤكده صاحب محل بالاتصال،
 *   ولا يُستبدل الاسم المحفوظ.
 * - الجهاز نفسه مرة أخرى: يُعطى مفتاحاً جديداً ويبطل القديم.
 */
export async function registerDevice(pool: Pool, input: RegisterInput): Promise<RegisterResult> {
  return withTransaction(pool, async (tx) => {
    const existing = await tx.query<{ id: number; name: string; gender: string | null; deleted_at: Date | null; banned_at: Date | null }>(
      'SELECT id, name, gender, deleted_at, banned_at FROM users WHERE phone = $1 FOR UPDATE',
      [input.phone],
    );
    let user = existing.rows[0];
    if (user?.banned_at) throw new AppError(403, 'not_allowed');
    if (!user) {
      const { rows } = await tx.query(
        'INSERT INTO users (phone, name, gender) VALUES ($1, $2, $3) RETURNING id, name, gender, deleted_at, banned_at',
        [input.phone, input.name, input.gender ?? null],
      );
      user = rows[0];
    } else if (user.deleted_at) {
      // حساب محذوف يعود بالرقم نفسه؛ سجل الالتزام باقٍ لأنه مربوط بالرقم
      const { rows } = await tx.query(
        'UPDATE users SET deleted_at = NULL, name = $2, gender = coalesce($3, gender) WHERE id = $1 RETURNING id, name, gender, deleted_at, banned_at',
        [user.id, input.name, input.gender ?? null],
      );
      user = rows[0];
    } else if (input.gender && !user.gender) {
      // حساب قديم بلا جنس: يُكمل عند الدخول من جديد
      const { rows } = await tx.query(
        'UPDATE users SET gender = $2 WHERE id = $1 RETURNING id, name, gender, deleted_at, banned_at',
        [user.id, input.gender],
      );
      user = rows[0];
    }

    const token = newToken();
    const { rows } = await tx.query<{ id: number }>(
      `INSERT INTO devices (user_id, device_identifier, token_hash) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, device_identifier)
       DO UPDATE SET token_hash = EXCLUDED.token_hash, last_seen_at = now()
       RETURNING id`,
      [user!.id, input.deviceIdentifier, hashToken(token)],
    );
    if (input.phoneVerified) {
      await tx.query(
        `UPDATE devices SET phone_verified_at = now(), verified_by_call_at = coalesce(verified_by_call_at, now()),
                            trust_requested_at = NULL, trust_request_note = NULL
         WHERE id = $1`,
        [rows[0]!.id],
      );
    }
    const trustedDevice = await isTrustedDevice(tx, user!.id, rows[0]!.id);
    return { token, user: { id: user!.id, name: user!.name, phone: input.phone, gender: user!.gender ?? null }, trustedDevice };
  });
}

export interface AuthContext {
  userId: number;
  deviceId: number;
  trusted: boolean;
}

export async function authenticate(pool: Pool, token: string): Promise<AuthContext | null> {
  const { rows } = await pool.query<{ user_id: number; device_id: number; trusted: boolean }>(
    `UPDATE devices d SET last_seen_at = now()
     FROM users u
     WHERE d.token_hash = $1 AND u.id = d.user_id AND u.deleted_at IS NULL AND u.banned_at IS NULL
     RETURNING d.user_id, d.id AS device_id,
       (d.verified_by_call_at IS NOT NULL
        OR d.id = (SELECT min(id) FROM devices WHERE user_id = d.user_id)) AS trusted`,
    [hashToken(token)],
  );
  const r = rows[0];
  return r ? { userId: r.user_id, deviceId: r.device_id, trusted: r.trusted } : null;
}
