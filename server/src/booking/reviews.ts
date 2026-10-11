import type { Pool } from '../db/pool.js';
import type { Queryable } from './db.js';
import { withTransaction } from './tx.js';
import { AppError } from '../lib/errors.js';

/** متوسط التقييم وعددها لمحل؛ المخفية من الإدارة لا تُحسب */
export const RATING_SQL = (shop: string) => `
  (SELECT round(avg(r.stars)::numeric, 1)::float8 FROM reviews r WHERE r.shop_id = ${shop} AND r.hidden_at IS NULL) AS rating,
  (SELECT count(*)::int FROM reviews r WHERE r.shop_id = ${shop} AND r.hidden_at IS NULL) AS "ratingCount"`;

/**
 * هل يستطيع الزبون تقييم هذا الحجز: مكتمل، لم يُقيّم بعد، وضمن المدة المسموحة بعد الموعد.
 * يُستخدم داخل استعلام الحجز (b هو جدول الحجوزات).
 */
export const CAN_REVIEW_SQL = `(
  b.status = 'completed'
  AND NOT EXISTS (SELECT 1 FROM reviews r WHERE r.booking_id = b.id)
  AND b.ends_at > now() - make_interval(days => (SELECT (value #>> '{}')::int FROM settings WHERE key = 'review_window_days'))
)`;

export interface ReviewInput {
  bookingId: number;
  customerId: number;
  stars: number;
  comment?: string;
}

/** تقييم واحد لكل حجز مكتمل، من صاحب الحجز فقط */
export async function addReview(pool: Pool, input: ReviewInput) {
  if (!Number.isInteger(input.stars) || input.stars < 1 || input.stars > 5) throw new AppError(400, 'invalid_request');
  const comment = input.comment?.trim() || null;
  return withTransaction(pool, async (tx) => {
    const { rows } = await tx.query<{ shop_id: number; can_review: boolean; reviewed: boolean; status: string }>(
      `SELECT b.shop_id, b.status, ${CAN_REVIEW_SQL} AS can_review,
              EXISTS (SELECT 1 FROM reviews r WHERE r.booking_id = b.id) AS reviewed
       FROM bookings b WHERE b.id = $1 AND b.customer_id = $2 FOR UPDATE OF b`,
      [input.bookingId, input.customerId],
    );
    const b = rows[0];
    if (!b) throw new AppError(404, 'booking_not_found');
    if (b.reviewed) throw new AppError(409, 'already_reviewed');
    if (b.status !== 'completed') throw new AppError(409, 'review_not_allowed');
    if (!b.can_review) throw new AppError(409, 'review_window_closed');
    await tx.query('INSERT INTO reviews (booking_id, shop_id, stars, comment) VALUES ($1, $2, $3, $4)', [
      input.bookingId,
      b.shop_id,
      input.stars,
      comment,
    ]);
  });
}

/** آخر التقييمات الظاهرة لمحل، باسم الزبون الأول فقط */
export async function latestReviews(db: Queryable, shopId: number, limit = 20) {
  const { rows } = await db.query(
    `SELECT r.id, r.stars, r.comment, r.created_at AS "createdAt",
            nullif(split_part(trim(u.name), ' ', 1), '') AS "customerName"
     FROM reviews r
     JOIN bookings b ON b.id = r.booking_id
     JOIN users u ON u.id = b.customer_id
     WHERE r.shop_id = $1 AND r.hidden_at IS NULL
     ORDER BY r.created_at DESC, r.id DESC
     LIMIT $2`,
    [shopId, limit],
  );
  return rows;
}
