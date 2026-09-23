import { createHash, randomBytes } from 'node:crypto';

/** مفتاح دخول عشوائي يُعطى للجهاز مرة واحدة؛ الخادم يحفظ بصمته فقط. */
export function newToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
