import { createHash, randomInt, timingSafeEqual } from 'node:crypto';
import type { Pool } from '../db/pool.js';
import { AppError } from '../lib/errors.js';

/** يرسل رمز التحقق إلى الرقم (بصيغة 07xxxxxxxxx) */
export interface CodeSender {
  send(phone: string, code: string): Promise<void>;
}

export const CODE_TTL_SECONDS = 600;
export const RESEND_AFTER_SECONDS = 60;
const MAX_ATTEMPTS = 5;
const PER_PHONE_PER_HOUR = 5;
const PER_IP_PER_HOUR = 10;
// سقف عام يحمي الرصيد من إغراق آلي
const GLOBAL_PER_HOUR = 300;

const hashCode = (phone: string, code: string) => createHash('sha256').update(`${phone}:${code}`).digest('hex');

/**
 * يرسل رمزاً جديداً من ستة أرقام. الحدود: رمز كل دقيقة للرقم الواحد،
 * وخمسة في الساعة للرقم، وعشرة في الساعة للعنوان الواحد.
 */
export async function requestCode(
  pool: Pool,
  sender: CodeSender,
  phone: string,
  ip: string,
  log?: { error(obj: unknown, msg?: string): void },
): Promise<void> {
  const { rows: [stats] } = await pool.query<{ last_seconds: number | null; phone_hour: number; ip_hour: number; all_hour: number }>(
    `SELECT extract(epoch FROM now() - max(created_at) FILTER (WHERE phone = $1))::int AS last_seconds,
            count(*) FILTER (WHERE phone = $1)::int AS phone_hour,
            count(*) FILTER (WHERE ip = $2)::int AS ip_hour,
            count(*)::int AS all_hour
     FROM phone_codes WHERE created_at > now() - interval '1 hour'`,
    [phone, ip],
  );
  if (stats!.last_seconds !== null && stats!.last_seconds < RESEND_AFTER_SECONDS) {
    throw new AppError(429, 'code_too_soon', { retryAfter: RESEND_AFTER_SECONDS - stats!.last_seconds });
  }
  if (stats!.phone_hour >= PER_PHONE_PER_HOUR || stats!.ip_hour >= PER_IP_PER_HOUR || stats!.all_hour >= GLOBAL_PER_HOUR) {
    throw new AppError(429, 'too_many_codes');
  }

  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  const { rows: [row] } = await pool.query<{ id: number }>(
    `INSERT INTO phone_codes (phone, code_hash, ip, expires_at)
     VALUES ($1, $2, $3, now() + make_interval(secs => $4)) RETURNING id`,
    [phone, hashCode(phone, code), ip, CODE_TTL_SECONDS],
  );
  try {
    await sender.send(phone, code);
  } catch (err) {
    // لم يصل الرمز: لا يُحسب على صاحب الرقم
    await pool.query('DELETE FROM phone_codes WHERE id = $1', [row!.id]);
    log?.error(err, 'phone code not sent');
    throw new AppError(502, 'code_send_failed');
  }
}

/**
 * يتحقق من آخر رمز أُرسل للرقم ويستهلكه. المحاولة الخاطئة تُحفظ فوراً،
 * وبعد خمس محاولات يلزم طلب رمز جديد.
 */
export async function consumeCode(pool: Pool, phone: string, code: string): Promise<void> {
  const { rows: [row] } = await pool.query<{ id: number; code_hash: string; attempts: number; expired: boolean }>(
    `SELECT id, code_hash, attempts, expires_at < now() AS expired FROM phone_codes
     WHERE phone = $1 AND used_at IS NULL ORDER BY id DESC LIMIT 1`,
    [phone],
  );
  if (!row || row.expired || row.attempts >= MAX_ATTEMPTS) throw new AppError(400, 'code_expired');
  const given = Buffer.from(hashCode(phone, code));
  if (!timingSafeEqual(given, Buffer.from(row.code_hash))) {
    await pool.query('UPDATE phone_codes SET attempts = attempts + 1 WHERE id = $1', [row.id]);
    throw new AppError(400, 'code_invalid');
  }
  // الاستهلاك مشروط: طلبان متزامنان بالرمز نفسه لا ينجحان معاً
  const { rowCount } = await pool.query('UPDATE phone_codes SET used_at = now() WHERE id = $1 AND used_at IS NULL', [row.id]);
  if (rowCount !== 1) throw new AppError(400, 'code_expired');
}

/** إرسال الرمز عبر الواتساب أولاً ثم الرسالة القصيرة، من خدمة رموز عراقية */
export function createOtpiqSender(apiKey: string, provider = 'whatsapp-sms', fetchImpl: typeof fetch = fetch): CodeSender {
  return {
    async send(phone, code) {
      const res = await fetchImpl('https://api.otpiq.com/api/sms', {
        method: 'POST',
        headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          phoneNumber: `964${phone.slice(1)}`,
          smsType: 'verification',
          verificationCode: code,
          provider,
        }),
        signal: AbortSignal.timeout(15_000),
      });
      if (!res.ok) {
        const text = await res.text().catch(() => '');
        throw new Error(`otp provider ${res.status}: ${text.slice(0, 300)}`);
      }
    },
  };
}
