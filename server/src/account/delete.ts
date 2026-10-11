import type { Pool } from '../db/pool.js';
import type { Queryable } from '../booking/db.js';
import { cancelForAccountDeletion } from '../booking/bookings.js';
import { withTransaction } from '../booking/tx.js';
import { AppError } from '../lib/errors.js';

const ACTIVE = `('pending_shop', 'pending_customer', 'confirmed')`;

/** ما سيحدث عند الحذف، ليعرضه التطبيق قبل التأكيد */
export async function deletionPreview(db: Queryable, userId: number, now: Date) {
  const { rows } = await db.query(
    `SELECT
       (SELECT count(*)::int FROM bookings
        WHERE customer_id = $1 AND status IN ${ACTIVE} AND starts_at > $2) AS "upcomingBookings",
       (SELECT json_build_object(
                 'name', s.name,
                 'upcomingBookings', (SELECT count(*)::int FROM bookings b
                                      WHERE b.shop_id = s.id AND b.customer_id <> $1
                                        AND b.status IN ${ACTIVE} AND b.starts_at > $2))
        FROM shops s WHERE s.owner_id = $1 AND s.closed_at IS NULL) AS shop`,
    [userId, now],
  );
  return rows[0] as { upcomingBookings: number; shop: { name: string; upcomingBookings: number } | null };
}

export interface DeletionResult {
  /** الاسم قبل الحذف، ليظهر لصاحب المحل في إشعار الإلغاء */
  customerName: string;
  asCustomer: number[];
  asShop: number[];
}

/**
 * حذف الحساب نهائياً:
 * - تُلغى الحجوزات القادمة (زبوناً وصاحب محل).
 * - يُغلق المحل نهائياً ويختفي عن الزبائن، وتُحذف صوره ورقمه.
 * - يُمسح الاسم والرقم والأجهزة والإشعارات؛ الرقم نفسه يستطيع التسجيل لاحقاً كحساب جديد.
 * - تبقى الحجوزات القديمة عند المحلات دون اسم، وتبقى نجوم التقييمات دون تعليق ولا اسم.
 * - سجل الالتزام مربوط بالرقم لا بالحساب، فيبقى.
 */
export async function deleteAccount(pool: Pool, userId: number, now: Date): Promise<DeletionResult> {
  return withTransaction(pool, async (tx) => {
    const { rows } = await tx.query<{ name: string }>(
      'SELECT name FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE',
      [userId],
    );
    const user = rows[0];
    if (!user) throw new AppError(404, 'not_found');

    const cancelled = await cancelForAccountDeletion(tx, userId, now);

    await tx.query('DELETE FROM shop_photos WHERE shop_id IN (SELECT id FROM shops WHERE owner_id = $1)', [userId]);
    await tx.query(
      `UPDATE shops SET closed_at = $2, updated_at = $2, phone = NULL,
              status = CASE WHEN status = 'draft' THEN status ELSE 'suspended' END
       WHERE owner_id = $1`,
      [userId, now],
    );
    await tx.query(
      `UPDATE reviews r SET comment = NULL FROM bookings b WHERE b.id = r.booking_id AND b.customer_id = $1`,
      [userId],
    );
    await tx.query('DELETE FROM notifications WHERE user_id = $1', [userId]);
    await tx.query('DELETE FROM idempotency_keys WHERE user_id = $1', [userId]);
    await tx.query('DELETE FROM devices WHERE user_id = $1', [userId]);
    await tx.query(
      `UPDATE users SET deleted_at = $2, name = '', phone = 'deleted:' || id WHERE id = $1`,
      [userId, now],
    );
    return { customerName: user.name, ...cancelled };
  });
}
