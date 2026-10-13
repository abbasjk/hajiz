import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { bearer, LoginLimiter, login, logout, requireAdmin } from '../admin/auth.js';
import { withTransaction } from '../booking/tx.js';
import type { Queryable } from '../booking/db.js';
import { toLocalDate } from '../booking/time.js';
import { AppError } from '../lib/errors.js';
import { compareVersions, isValidVersion } from '../lib/version.js';
import type { NotificationType } from '../notify/texts.js';
import { RATING_SQL } from '../booking/reviews.js';
import { deleteAccountAndNotify } from '../account/delete.js';
import { MAX_PHOTO_BYTES, PHOTO_TYPES } from '../owner/shop.js';

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const r = schema.safeParse(value);
  if (!r.success) throw new AppError(400, 'invalid_request');
  return r.data;
}

const idParams = z.object({ id: z.coerce.number().int().positive() });
const noteBody = z.object({ note: z.string().trim().max(300).optional() }).default({});
/** الموافقة على محل تتطلب أن تؤكد الإدارة ثلاث نقاط تحقق */
const approveChecks = z.object({
  checks: z.object({ called: z.literal(true), location: z.literal(true), photos: z.literal(true) }),
});
const CHECKS_NOTE = 'تحقق: اتصال برقم المحل، مطابقة الموقع، الصور حقيقية';
const nameText = z.string().trim().min(2).max(60);
/** أيقونات أنواع العمل التي يعرفها التطبيق */
const categoryIcon = z.enum(['haircut', 'beard', 'dye', 'kids', 'skin', 'groom', 'treatment', 'threading', 'styling', 'razor']);
const iconName = z.enum(['store', 'scissors', 'sparkles', 'stethoscope', 'tooth', 'car', 'wrench', 'spa', 'face', 'pets', 'fitness', 'camera']);

// صفحة اللوحة: ملف واحد بجانب مجلد المصدر (يعمل من src أثناء التطوير ومن dist بعد البناء)
const PAGE_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../admin/index.html');

/** إعدادات لا تُعدّل من اللوحة لأن تغييرها يكسر الحسابات */
const READ_ONLY_SETTINGS = new Set(['display_timezone']);

/** القيمة الجديدة يجب أن تطابق شكل القديمة: نفس النوع ونفس المفاتيح، والأرقام غير سالبة */
export function sameShape(old: unknown, next: unknown): boolean {
  if (typeof old === 'number') return typeof next === 'number' && Number.isFinite(next) && next >= 0;
  if (typeof old === 'boolean' || typeof old === 'string') return typeof next === typeof old;
  if (Array.isArray(old)) {
    return Array.isArray(next) && next.length > 0 && next.every((v) => sameShape(old[0], v));
  }
  if (old && typeof old === 'object') {
    if (!next || typeof next !== 'object' || Array.isArray(next)) return false;
    const a = Object.keys(old).sort();
    const b = Object.keys(next).sort();
    return (
      a.length === b.length &&
      a.every((k, i) => k === b[i] && sameShape((old as Record<string, unknown>)[k], (next as Record<string, unknown>)[k]))
    );
  }
  return false;
}

async function logAction(db: Queryable, adminId: number, action: string, targetType: string, targetId: number | null, note?: string) {
  await db.query('INSERT INTO admin_actions (admin_id, action, target_type, target_id, note) VALUES ($1, $2, $3, $4, $5)', [
    adminId,
    action,
    targetType,
    targetId,
    note ?? null,
  ]);
}

/** انتقالات حالة المحل المسموحة من اللوحة، والإشعار الذي يصل لصاحبه */
const SHOP_ACTIONS = {
  approve: { from: ['under_review'], to: 'approved', notice: 'shop_approved', noteRequired: false },
  reject: { from: ['under_review'], to: 'rejected', notice: 'shop_rejected', noteRequired: true },
  suspend: { from: ['approved'], to: 'suspended', notice: 'shop_suspended', noteRequired: true },
  reinstate: { from: ['suspended'], to: 'approved', notice: 'shop_reinstated', noteRequired: false },
} as const satisfies Record<string, { from: readonly string[]; to: string; notice: NotificationType; noteRequired: boolean }>;

export async function adminRoutes(app: FastifyInstance) {
  const limiter = new LoginLimiter();

  // الصفحة نفسها عامة؛ البيانات كلها خلف الدخول
  app.get('/admin', async (_request, reply) => {
    const html = await readFile(PAGE_PATH, 'utf8');
    return reply
      .header('content-type', 'text/html; charset=utf-8')
      .header('cache-control', 'no-store')
      .header('x-frame-options', 'DENY')
      .send(html);
  });

  await app.register(
    async (api) => {
      api.post('/login', async (request, reply) => {
        const body = parse(z.object({ username: z.string().trim().min(1).max(60), password: z.string().min(1).max(200) }), request.body);
        if (limiter.blocked(request.ip)) throw new AppError(429, 'too_many_attempts');
        const token = await login(app.pool, body.username, body.password);
        if (!token) {
          limiter.fail(request.ip);
          throw new AppError(401, 'invalid_login');
        }
        limiter.reset(request.ip);
        return reply.send({ token });
      });

      await api.register(async (secure) => {
        secure.addHook('onRequest', requireAdmin(app.pool));
        const adminId = (request: { adminId?: number }) => request.adminId!;

        secure.post('/logout', async (request) => {
          await logout(app.pool, bearer(request));
          return { ok: true };
        });

        secure.get('/me', async (request) => {
          const { rows } = await app.pool.query('SELECT username FROM admins WHERE id = $1', [adminId(request)]);
          return { username: rows[0]?.username };
        });

        // ------------------------------------------------------------
        // نظرة عامة
        // ------------------------------------------------------------
        secure.get('/stats', async () => {
          const today = toLocalDate(new Date());
          const { rows } = await app.pool.query(
            `SELECT
               (SELECT count(*)::int FROM shops WHERE status = 'under_review') AS "pendingShops",
               (SELECT count(*)::int FROM shops WHERE status = 'approved') AS "activeShops",
               (SELECT count(*)::int FROM area_requests WHERE status = 'pending') AS "pendingAreas",
               (SELECT count(*)::int FROM deletion_requests WHERE status = 'pending') AS "pendingDeletions",
               (SELECT count(*)::int FROM devices d JOIN users u ON u.id = d.user_id
                 WHERE d.trust_requested_at IS NOT NULL AND d.verified_by_call_at IS NULL
                   AND u.deleted_at IS NULL AND u.banned_at IS NULL) AS "pendingTrust",
               (SELECT count(*)::int FROM users WHERE deleted_at IS NULL) AS users,
               (SELECT count(*)::int FROM bookings
                 WHERE (starts_at AT TIME ZONE 'Asia/Baghdad')::date = $1::date
                   AND status IN ('confirmed', 'completed', 'no_show')) AS "bookingsToday",
               (SELECT count(*)::int FROM bookings
                 WHERE status = 'expired' AND (updated_at AT TIME ZONE 'Asia/Baghdad')::date = $1::date) AS "expiredToday"`,
            [today],
          );
          return rows[0];
        });

        // ------------------------------------------------------------
        // المحلات
        // ------------------------------------------------------------
        secure.get('/shops', async (request) => {
          const q = parse(
            z.object({
              status: z.enum(['draft', 'under_review', 'approved', 'rejected', 'suspended']).default('under_review'),
              q: z.string().trim().max(60).optional(),
            }),
            request.query,
          );
          const { rows } = await app.pool.query(
            `SELECT s.id, s.name, s.status, s.submitted_at AS "submittedAt", s.reviewed_at AS "reviewedAt",
                    s.review_note AS "reviewNote", u.phone AS "ownerPhone", u.name AS "ownerName",
                    bt.name AS "businessType", d.name AS district, a.name AS area,
                    (SELECT count(*)::int FROM bookings b WHERE b.shop_id = s.id
                      AND b.status IN ('pending_shop', 'pending_customer', 'confirmed') AND b.starts_at > now()) AS "upcomingBookings"
             FROM shops s
             JOIN users u ON u.id = s.owner_id
             LEFT JOIN business_types bt ON bt.id = s.business_type_id
             LEFT JOIN districts d ON d.id = s.district_id
             LEFT JOIN areas a ON a.id = s.area_id
             WHERE s.status = $1
               AND ($2::text IS NULL OR s.name ILIKE '%' || $2 || '%' OR u.phone LIKE '%' || $2 || '%')
             ORDER BY coalesce(s.submitted_at, s.updated_at) ${q.status === 'under_review' ? 'ASC' : 'DESC'}
             LIMIT 200`,
            [q.status, q.q || null],
          );
          return { shops: rows };
        });

        const shopDetails = async (db: Queryable, id: number) => {
          const { rows } = await db.query(
            `SELECT s.id, s.name, s.status, s.description, s.phone, s.street, s.landmark, s.latitude, s.longitude,
                    s.review_note AS "reviewNote", s.submitted_at AS "submittedAt", s.reviewed_at AS "reviewedAt",
                    s.instant_booking AS "instantBooking", s.deadline_mode AS "deadlineMode", s.created_at AS "createdAt",
                    s.closed_at AS "closedAt", s.review_checks AS "reviewChecks", s.featured_at AS "featuredAt",
                    u.id AS "ownerId", u.phone AS "ownerPhone", u.name AS "ownerName",
                    bt.name AS "businessType", d.name AS district, a.name AS area,
                    rv.username AS "reviewedBy",
                    ${RATING_SQL('s.id')},
                    (SELECT id FROM schedules WHERE shop_id = s.id ORDER BY id LIMIT 1) AS "scheduleId"
             FROM shops s
             JOIN users u ON u.id = s.owner_id
             LEFT JOIN business_types bt ON bt.id = s.business_type_id
             LEFT JOIN districts d ON d.id = s.district_id
             LEFT JOIN areas a ON a.id = s.area_id
             LEFT JOIN admins rv ON rv.id = s.reviewed_by
             WHERE s.id = $1`,
            [id],
          );
          const shop = rows[0];
          if (!shop) throw new AppError(404, 'not_found');
          const [services, hours, photos, history, upcoming, similar] = await Promise.all([
            db.query(
              `SELECT id, name, duration_minutes AS "durationMinutes", price_type AS "priceType", price, active
               FROM services WHERE shop_id = $1 ORDER BY id`,
              [id],
            ),
            db.query(
              `SELECT day_of_week AS "dayOfWeek", to_char(start_time, 'HH24:MI') AS "from", to_char(end_time, 'HH24:MI') AS "to"
               FROM weekly_periods WHERE schedule_id = $1 ORDER BY day_of_week, start_time`,
              [shop.scheduleId ?? 0],
            ),
            db.query(`SELECT coalesce(url, '/photos/' || id) AS url FROM shop_photos WHERE shop_id = $1 ORDER BY sort_order, id`, [id]),
            db.query(
              `SELECT x.action, x.note, x.created_at AS "createdAt", ad.username
               FROM admin_actions x LEFT JOIN admins ad ON ad.id = x.admin_id
               WHERE x.target_type = 'shop' AND x.target_id = $1 ORDER BY x.id DESC LIMIT 20`,
              [id],
            ),
            db.query(
              `SELECT count(*)::int AS n FROM bookings WHERE shop_id = $1
                 AND status IN ('pending_shop', 'pending_customer', 'confirmed') AND starts_at > now()`,
              [id],
            ),
            // محلات مشابهة: الرقم نفسه، أو الاسم نفسه، أو على بعد نحو خمسين متراً.
            // تنبيه للمراجعة فقط: محلان متجاوران في سوق واحد أمر طبيعي
            db.query(
              `SELECT o.id, o.name, o.status,
                      (o.phone IS NOT NULL AND o.phone = s.phone) AS "samePhone",
                      (ar_norm(o.name) = ar_norm(s.name)) AS "sameName",
                      (o.latitude IS NOT NULL AND s.latitude IS NOT NULL
                       AND abs(o.latitude - s.latitude) < 0.0005 AND abs(o.longitude - s.longitude) < 0.0006) AS nearby
               FROM shops s JOIN shops o ON o.id <> s.id
               WHERE s.id = $1 AND o.closed_at IS NULL AND o.status <> 'draft'
                 AND ((o.phone IS NOT NULL AND o.phone = s.phone)
                      OR ar_norm(o.name) = ar_norm(s.name)
                      OR (o.latitude IS NOT NULL AND s.latitude IS NOT NULL
                          AND abs(o.latitude - s.latitude) < 0.0005 AND abs(o.longitude - s.longitude) < 0.0006))
               ORDER BY o.id LIMIT 10`,
              [id],
            ),
          ]);
          const { scheduleId: _scheduleId, ...rest } = shop;
          return {
            ...rest,
            services: services.rows,
            weeklyHours: hours.rows,
            photos: photos.rows.map((p) => p.url as string),
            history: history.rows,
            upcomingBookings: upcoming.rows[0]?.n ?? 0,
            similar: similar.rows,
          };
        };

        secure.get('/shops/:id', async (request) => shopDetails(app.pool, parse(idParams, request.params).id));

        for (const [action, rule] of Object.entries(SHOP_ACTIONS)) {
          secure.post(`/shops/:id/${action}`, async (request) => {
            const { id } = parse(idParams, request.params);
            const { note } = parse(noteBody, request.body ?? {});
            if (rule.noteRequired && !note) throw new AppError(400, 'note_required');
            const approving = action === 'approve';
            if (approving && !approveChecks.safeParse(request.body ?? {}).success) throw new AppError(400, 'checks_required');
            const changed = await withTransaction(app.pool, async (tx) => {
              const { rows } = await tx.query<{ status: string; owner_id: number; name: string; closed_at: Date | null }>(
                'SELECT status, owner_id, name, closed_at FROM shops WHERE id = $1 FOR UPDATE',
                [id],
              );
              const shop = rows[0];
              if (!shop) throw new AppError(404, 'not_found');
              // صاحبه حذف حسابه؛ لا يعود المحل
              if (shop.closed_at) throw new AppError(409, 'shop_closed');
              if (!(rule.from as readonly string[]).includes(shop.status)) {
                throw new AppError(409, 'invalid_transition', { status: shop.status });
              }
              await tx.query(
                `UPDATE shops SET status = $2::shop_status, review_note = $3, reviewed_at = now(), reviewed_by = $4, updated_at = now(),
                                  review_checks = CASE WHEN $5 THEN jsonb_build_object('called', true, 'location', true, 'photos', true) ELSE review_checks END
                 WHERE id = $1`,
                [id, rule.to, rule.noteRequired ? note : null, adminId(request), approving],
              );
              await logAction(tx, adminId(request), action, 'shop', id, approving ? CHECKS_NOTE : note);
              return shop;
            });
            await app.notifier.notify({ userId: changed.owner_id, type: rule.notice, params: { shop: changed.name, note } });
            return shopDetails(app.pool, id);
          });
        }

        // ------------------------------------------------------------
        // طلبات إضافة المناطق
        // ------------------------------------------------------------
        secure.get('/area-requests', async () => {
          const { rows } = await app.pool.query(
            `SELECT r.id, r.name, r.created_at AS "createdAt", d.id AS "districtId", d.name AS district,
                    u.phone AS "requestedByPhone", u.name AS "requestedByName",
                    EXISTS (SELECT 1 FROM areas a WHERE a.district_id = r.district_id AND a.name = r.name) AS "alreadyExists"
             FROM area_requests r
             JOIN districts d ON d.id = r.district_id
             LEFT JOIN users u ON u.id = r.requested_by
             WHERE r.status = 'pending' ORDER BY r.created_at`,
          );
          return { requests: rows };
        });

        secure.post('/area-requests/:id/approve', async (request) => {
          const { id } = parse(idParams, request.params);
          const body = parse(z.object({ name: nameText.optional() }).default({}), request.body ?? {});
          return withTransaction(app.pool, async (tx) => {
            const { rows } = await tx.query<{ district_id: number; name: string }>(
              `SELECT district_id, name FROM area_requests WHERE id = $1 AND status = 'pending' FOR UPDATE`,
              [id],
            );
            const req = rows[0];
            if (!req) throw new AppError(404, 'not_found');
            const name = body.name ?? req.name;
            // إذا كانت المنطقة موجودة (أو معطلة) تُفعّل بدل إنشاء نسخة ثانية
            const area = await tx.query<{ id: number }>(
              `INSERT INTO areas (district_id, name) VALUES ($1, $2)
               ON CONFLICT (district_id, name) DO UPDATE SET active = true RETURNING id`,
              [req.district_id, name],
            );
            await tx.query(`UPDATE area_requests SET status = 'approved', resolved_at = now() WHERE id = $1`, [id]);
            await logAction(tx, adminId(request), 'approve', 'area_request', id, name);
            return { areaId: area.rows[0]!.id };
          });
        });

        secure.post('/area-requests/:id/reject', async (request) => {
          const { id } = parse(idParams, request.params);
          const { rowCount } = await app.pool.query(
            `UPDATE area_requests SET status = 'rejected', resolved_at = now() WHERE id = $1 AND status = 'pending'`,
            [id],
          );
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'reject', 'area_request', id);
          return { ok: true };
        });

        // ------------------------------------------------------------
        // طلبات حذف الحساب من صفحة الموقع
        // بعد البت في الطلب لا يبقى منه إلا آخر أربعة أرقام
        // ------------------------------------------------------------
        const MASK = `'*******' || right(phone, 4)`;

        secure.get('/deletion-requests', async (request) => {
          const { status } = parse(z.object({ status: z.enum(['pending', 'resolved']).default('pending') }), request.query);
          const { rows } = await app.pool.query(
            status === 'pending'
              ? `SELECT r.id, r.phone, r.name, r.note, r.status, r.created_at AS "createdAt",
                        u.id AS "userId", u.name AS "userName", u.created_at AS "userSince",
                        (SELECT count(*)::int FROM bookings b WHERE b.customer_id = u.id
                          AND b.status IN ('pending_shop', 'pending_customer', 'confirmed') AND b.starts_at > now()) AS "upcomingBookings",
                        (SELECT json_build_object('id', s.id, 'name', s.name, 'status', s.status)
                         FROM shops s WHERE s.owner_id = u.id AND s.closed_at IS NULL) AS shop
                 FROM deletion_requests r
                 LEFT JOIN users u ON u.phone = r.phone AND u.deleted_at IS NULL
                 WHERE r.status = 'pending'
                 ORDER BY r.created_at`
              : `SELECT r.id, r.phone, r.status, r.created_at AS "createdAt", r.resolved_at AS "resolvedAt",
                        r.resolution_note AS "resolutionNote", a.username AS "resolvedBy"
                 FROM deletion_requests r LEFT JOIN admins a ON a.id = r.resolved_by
                 WHERE r.status <> 'pending'
                 ORDER BY r.resolved_at DESC LIMIT 100`,
          );
          return { requests: rows };
        });

        secure.post('/deletion-requests/:id/delete', async (request) => {
          const { id } = parse(idParams, request.params);
          const { rows } = await app.pool.query<{ userId: number | null }>(
            `SELECT u.id AS "userId" FROM deletion_requests r
             LEFT JOIN users u ON u.phone = r.phone AND u.deleted_at IS NULL
             WHERE r.id = $1 AND r.status = 'pending'`,
            [id],
          );
          const req = rows[0];
          if (!req) throw new AppError(404, 'not_found');
          if (!req.userId) throw new AppError(409, 'account_not_found');
          await deleteAccountAndNotify(app, req.userId);
          await app.pool.query(
            `UPDATE deletion_requests SET status = 'done', resolved_at = now(), resolved_by = $2,
                    phone = ${MASK}, name = NULL, note = NULL
             WHERE id = $1`,
            [id, adminId(request)],
          );
          await logAction(app.pool, adminId(request), 'delete_account', 'user', req.userId);
          return { ok: true };
        });

        secure.post('/deletion-requests/:id/reject', async (request) => {
          const { id } = parse(idParams, request.params);
          const { note } = parse(noteBody, request.body ?? {});
          const { rowCount } = await app.pool.query(
            `UPDATE deletion_requests SET status = 'rejected', resolved_at = now(), resolved_by = $2, resolution_note = $3,
                    phone = ${MASK}, name = NULL, note = NULL
             WHERE id = $1 AND status = 'pending'`,
            [id, adminId(request), note || null],
          );
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'reject', 'deletion_request', id, note);
          return { ok: true };
        });

        // ------------------------------------------------------------
        // المستخدمون والأجهزة
        // ------------------------------------------------------------
        secure.get('/users', async (request) => {
          const { q } = parse(z.object({ q: z.string().trim().max(60).optional() }), request.query);
          const { rows } = await app.pool.query(
            `SELECT u.id, u.phone, u.name, u.created_at AS "createdAt", u.deleted_at AS "deletedAt", u.banned_at AS "bannedAt",
                    (SELECT count(*)::int FROM devices WHERE user_id = u.id) AS devices,
                    (SELECT s.status FROM shops s WHERE s.owner_id = u.id) AS "shopStatus"
             FROM users u
             WHERE $1::text IS NULL OR u.phone LIKE '%' || $1 || '%' OR u.name ILIKE '%' || $1 || '%'
             ORDER BY u.id DESC LIMIT 100`,
            [q || null],
          );
          return { users: rows };
        });

        secure.get('/users/:id', async (request) => {
          const { id } = parse(idParams, request.params);
          const { rows } = await app.pool.query(
            `SELECT u.id, u.phone, u.name, u.created_at AS "createdAt", u.deleted_at AS "deletedAt", u.banned_at AS "bannedAt",
                    (SELECT json_build_object('id', s.id, 'name', s.name, 'status', s.status) FROM shops s WHERE s.owner_id = u.id) AS shop
             FROM users u WHERE u.id = $1`,
            [id],
          );
          const user = rows[0];
          if (!user) throw new AppError(404, 'not_found');
          const [devices, record, bookings] = await Promise.all([
            app.pool.query(
              `SELECT d.id, d.device_identifier AS "identifier", d.first_seen_at AS "firstSeenAt", d.last_seen_at AS "lastSeenAt",
                      d.verified_by_call_at AS "verifiedAt", (d.push_token IS NOT NULL) AS "hasPush",
                      (d.verified_by_call_at IS NOT NULL OR d.id = (SELECT min(id) FROM devices WHERE user_id = d.user_id)) AS trusted
               FROM devices d WHERE d.user_id = $1 ORDER BY d.id`,
              [id],
            ),
            app.pool.query(
              `SELECT count(*) FILTER (WHERE type = 'no_show')::int AS "noShows",
                      count(*) FILTER (WHERE type = 'late_cancel')::int AS "lateCancels"
               FROM commitment_events WHERE phone = $1`,
              [user.phone],
            ),
            app.pool.query(
              `SELECT count(*) FILTER (WHERE status = 'completed')::int AS completed,
                      count(*)::int AS total
               FROM bookings WHERE customer_id = $1`,
              [id],
            ),
          ]);
          return { ...user, devices: devices.rows, record: { ...record.rows[0], ...bookings.rows[0] } };
        });

        for (const [action, sql] of [
          ['ban', 'UPDATE users SET banned_at = now() WHERE id = $1 AND banned_at IS NULL'],
          ['unban', 'UPDATE users SET banned_at = NULL WHERE id = $1 AND banned_at IS NOT NULL'],
        ] as const) {
          secure.post(`/users/:id/${action}`, async (request) => {
            const { id } = parse(idParams, request.params);
            const { note } = parse(noteBody, request.body ?? {});
            const { rowCount } = await app.pool.query(sql, [id]);
            if (!rowCount) throw new AppError(409, 'invalid_transition');
            await logAction(app.pool, adminId(request), action, 'user', id, note);
            return { ok: true };
          });
        }

        // توثيق جهاز: صاحب المحل غيّر هاتفه ويحتاج إدارة محله من الجهاز الجديد
        for (const [action, value] of [['trust', 'now()'], ['untrust', 'NULL']] as const) {
          secure.post(`/devices/:id/${action}`, async (request) => {
            const { id } = parse(idParams, request.params);
            const { rows } = await app.pool.query<{ user_id: number }>(
              `UPDATE devices SET verified_by_call_at = ${value}, trust_requested_at = NULL, trust_request_note = NULL
               WHERE id = $1 RETURNING user_id`,
              [id],
            );
            const device = rows[0];
            if (!device) throw new AppError(404, 'not_found');
            await logAction(app.pool, adminId(request), action, 'device', id);
            if (action === 'trust') await app.notifier.notify({ userId: device.user_id, type: 'device_trusted', params: {} });
            return { ok: true };
          });
        }

        // تمييز محل معتمد في رئيسية الزبون، أو إلغاء تمييزه
        for (const [action, value] of [['feature', 'now()'], ['unfeature', 'NULL']] as const) {
          secure.post(`/shops/:id/${action}`, async (request) => {
            const { id } = parse(idParams, request.params);
            const { rowCount } = await app.pool.query(
              `UPDATE shops SET featured_at = ${value} WHERE id = $1 AND status = 'approved' AND closed_at IS NULL`,
              [id],
            );
            if (!rowCount) throw new AppError(409, 'invalid_transition');
            await logAction(app.pool, adminId(request), action, 'shop', id);
            return shopDetails(app.pool, id);
          });
        }

        // طلبات توثيق الهواتف من التطبيق
        secure.get('/trust-requests', async () => {
          const { rows } = await app.pool.query(
            `SELECT d.id, d.trust_requested_at AS "requestedAt", d.trust_request_note AS note,
                    d.first_seen_at AS "firstSeenAt",
                    u.id AS "userId", u.name, u.phone, u.created_at AS "userSince",
                    (SELECT max(o.last_seen_at) FROM devices o
                      WHERE o.user_id = u.id AND o.id <> d.id
                        AND (o.verified_by_call_at IS NOT NULL OR o.id = (SELECT min(id) FROM devices WHERE user_id = u.id))) AS "trustedLastSeen",
                    (SELECT json_build_object('id', s.id, 'name', s.name, 'status', s.status)
                     FROM shops s WHERE s.owner_id = u.id AND s.closed_at IS NULL) AS shop
             FROM devices d JOIN users u ON u.id = d.user_id
             WHERE d.trust_requested_at IS NOT NULL AND d.verified_by_call_at IS NULL
               AND u.deleted_at IS NULL AND u.banned_at IS NULL
             ORDER BY d.trust_requested_at`,
          );
          return { requests: rows };
        });

        secure.post('/trust-requests/:id/dismiss', async (request) => {
          const { id } = parse(idParams, request.params);
          const { note } = parse(noteBody, request.body ?? {});
          const { rowCount } = await app.pool.query(
            `UPDATE devices SET trust_requested_at = NULL, trust_request_note = NULL
             WHERE id = $1 AND trust_requested_at IS NOT NULL`,
            [id],
          );
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'dismiss', 'trust_request', id, note);
          return { ok: true };
        });

        // ------------------------------------------------------------
        // القوائم: أنواع النشاط، الأقضية، المناطق
        // ------------------------------------------------------------
        secure.get('/catalog', async () => {
          const [types, districts, areas, categories] = await Promise.all([
            app.pool.query(
              `SELECT bt.id, bt.name, bt.icon, bt.sort_order AS "sortOrder", bt.active,
                      (SELECT count(*)::int FROM shops WHERE business_type_id = bt.id) AS shops
               FROM business_types bt ORDER BY bt.sort_order, bt.id`,
            ),
            app.pool.query('SELECT id, name, sort_order AS "sortOrder", active FROM districts ORDER BY sort_order, id'),
            app.pool.query(
              `SELECT a.id, a.district_id AS "districtId", a.name, a.sort_order AS "sortOrder", a.active,
                      (SELECT count(*)::int FROM shops WHERE area_id = a.id) AS shops
               FROM areas a ORDER BY a.sort_order, a.name`,
            ),
            app.pool.query(
              `SELECT c.id, c.name, c.icon, c.sort_order AS "sortOrder", c.active,
                      CASE WHEN c.photo IS NOT NULL
                        THEN '/category-photos/' || c.id || '?v=' || extract(epoch FROM c.photo_updated_at)::bigint END AS photo,
                      (SELECT count(*)::int FROM services WHERE category_id = c.id AND active) AS services
               FROM service_categories c ORDER BY c.sort_order, c.id`,
            ),
          ]);
          return { businessTypes: types.rows, districts: districts.rows, areas: areas.rows, serviceCategories: categories.rows };
        });

        const uniqueName = (err: unknown) => {
          if ((err as { code?: string }).code === '23505') throw new AppError(409, 'name_exists');
          throw err;
        };

        secure.post('/business-types', async (request) => {
          const { name, icon } = parse(z.object({ name: nameText, icon: iconName.optional() }), request.body);
          const { rows } = await app.pool
            .query(
              `INSERT INTO business_types (name, icon, sort_order)
               VALUES ($1, $2, (SELECT coalesce(max(sort_order), 0) + 1 FROM business_types)) RETURNING id`,
              [name, icon ?? 'store'],
            )
            .catch(uniqueName);
          await logAction(app.pool, adminId(request), 'create', 'business_type', rows[0].id, name);
          return { id: rows[0].id };
        });

        secure.post('/service-categories', async (request) => {
          const { name, icon } = parse(z.object({ name: nameText, icon: categoryIcon }), request.body);
          const { rows } = await app.pool
            .query(
              `INSERT INTO service_categories (name, icon, sort_order)
               VALUES ($1, $2, (SELECT coalesce(max(sort_order), 0) + 1 FROM service_categories)) RETURNING id`,
              [name, icon],
            )
            .catch(uniqueName);
          await logAction(app.pool, adminId(request), 'create', 'service_category', rows[0].id, name);
          return { id: rows[0].id };
        });

        secure.post('/service-categories/:id/photo', { bodyLimit: 3 * 1024 * 1024 }, async (request) => {
          const { id } = parse(idParams, request.params);
          const body = parse(z.object({ contentType: z.string(), data: z.string().min(1) }), request.body);
          if (!PHOTO_TYPES.has(body.contentType)) throw new AppError(400, 'invalid_photo');
          const data = Buffer.from(body.data, 'base64');
          if (data.length === 0 || data.length > MAX_PHOTO_BYTES) throw new AppError(400, 'invalid_photo');
          const { rowCount } = await app.pool.query(
            'UPDATE service_categories SET photo = $2, photo_type = $3, photo_updated_at = now() WHERE id = $1',
            [id, data, body.contentType],
          );
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'photo', 'service_categories', id);
          return { ok: true };
        });

        secure.delete('/service-categories/:id/photo', async (request) => {
          const { id } = parse(idParams, request.params);
          const { rowCount } = await app.pool.query(
            'UPDATE service_categories SET photo = NULL, photo_type = NULL, photo_updated_at = NULL WHERE id = $1',
            [id],
          );
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'remove_photo', 'service_categories', id);
          return { ok: true };
        });

        secure.patch('/service-categories/:id', async (request) => {
          const { id } = parse(idParams, request.params);
          const body = parse(
            z.object({ name: nameText.optional(), active: z.boolean().optional(), sortOrder: z.number().int().min(0).optional(), icon: categoryIcon.optional() }),
            request.body,
          );
          const { rowCount } = await app.pool
            .query(
              `UPDATE service_categories SET name = coalesce($2, name), active = coalesce($3, active),
                      sort_order = coalesce($4, sort_order), icon = coalesce($5, icon)
               WHERE id = $1`,
              [id, body.name ?? null, body.active ?? null, body.sortOrder ?? null, body.icon ?? null],
            )
            .catch(uniqueName);
          if (!rowCount) throw new AppError(404, 'not_found');
          await logAction(app.pool, adminId(request), 'update', 'service_categories', id, JSON.stringify(body));
          return { ok: true };
        });

        const editBody = z.object({
          name: nameText.optional(),
          active: z.boolean().optional(),
          sortOrder: z.number().int().min(0).optional(),
          // لأنواع العمل فقط
          icon: iconName.optional(),
        });

        for (const table of ['business_types', 'districts', 'areas'] as const) {
          const target = table === 'business_types' ? 'business-types' : table;
          secure.patch(`/${target}/:id`, async (request) => {
            const { id } = parse(idParams, request.params);
            const body = parse(editBody, request.body);
            const { rowCount } = await app.pool
              .query(
                `UPDATE ${table} SET name = coalesce($2, name), active = coalesce($3, active), sort_order = coalesce($4, sort_order)
                 ${table === 'business_types' ? ', icon = coalesce($5, icon)' : ''}
                 WHERE id = $1`,
                [id, body.name ?? null, body.active ?? null, body.sortOrder ?? null, ...(table === 'business_types' ? [body.icon ?? null] : [])],
              )
              .catch(uniqueName);
            if (!rowCount) throw new AppError(404, 'not_found');
            await logAction(app.pool, adminId(request), 'update', table, id, JSON.stringify(body));
            return { ok: true };
          });
        }

        secure.post('/areas', async (request) => {
          const body = parse(z.object({ districtId: z.number().int().positive(), name: nameText }), request.body);
          const { rows } = await app.pool
            .query('INSERT INTO areas (district_id, name) VALUES ($1, $2) RETURNING id', [body.districtId, body.name])
            .catch((err: unknown) => {
              if ((err as { code?: string }).code === '23503') throw new AppError(400, 'invalid_request');
              return uniqueName(err);
            });
          await logAction(app.pool, adminId(request), 'create', 'area', rows[0].id, body.name);
          return { id: rows[0].id };
        });

        // ------------------------------------------------------------
        // التقييمات: الإدارة تخفي المسيء منها فلا يظهر ولا يُحسب في المتوسط
        // ------------------------------------------------------------
        secure.get('/reviews', async (request) => {
          const q = parse(z.object({ hidden: z.enum(['true', 'false']).default('false') }), request.query);
          const { rows } = await app.pool.query(
            `SELECT r.id, r.stars, r.comment, r.created_at AS "createdAt", r.hidden_at AS "hiddenAt",
                    s.id AS "shopId", s.name AS "shopName", u.id AS "customerId", u.name AS "customerName", u.phone AS "customerPhone"
             FROM reviews r
             JOIN shops s ON s.id = r.shop_id
             JOIN bookings b ON b.id = r.booking_id
             JOIN users u ON u.id = b.customer_id
             WHERE (r.hidden_at IS NOT NULL) = $1
             ORDER BY r.created_at DESC, r.id DESC LIMIT 200`,
            [q.hidden === 'true'],
          );
          return { reviews: rows };
        });

        for (const [action, sql] of [
          ['hide', 'UPDATE reviews SET hidden_at = now(), hidden_by = $2 WHERE id = $1 AND hidden_at IS NULL'],
          ['unhide', 'UPDATE reviews SET hidden_at = NULL, hidden_by = NULL WHERE id = $1 AND hidden_at IS NOT NULL AND $2::int IS NOT NULL'],
        ] as const) {
          secure.post(`/reviews/:id/${action}`, async (request) => {
            const { id } = parse(idParams, request.params);
            const { note } = parse(noteBody, request.body ?? {});
            const { rowCount } = await app.pool.query(sql, [id, adminId(request)]);
            if (!rowCount) throw new AppError(409, 'invalid_transition');
            await logAction(app.pool, adminId(request), action, 'review', id, note);
            return { ok: true };
          });
        }

        // ------------------------------------------------------------
        // الإعدادات والإصدارات
        // ------------------------------------------------------------
        secure.get('/settings', async () => {
          const { rows } = await app.pool.query('SELECT key, value, updated_at AS "updatedAt" FROM settings ORDER BY key');
          return { settings: rows.map((r) => ({ ...r, editable: !READ_ONLY_SETTINGS.has(r.key) })) };
        });

        secure.put('/settings/:key', async (request) => {
          const { key } = parse(z.object({ key: z.string().min(1).max(60) }), request.params);
          const { value } = parse(z.object({ value: z.unknown() }), request.body);
          if (READ_ONLY_SETTINGS.has(key)) throw new AppError(403, 'read_only');
          return withTransaction(app.pool, async (tx) => {
            const { rows } = await tx.query('SELECT value FROM settings WHERE key = $1 FOR UPDATE', [key]);
            if (!rows[0]) throw new AppError(404, 'not_found');
            if (!sameShape(rows[0].value, value)) throw new AppError(400, 'invalid_value');
            await tx.query('UPDATE settings SET value = $2, updated_at = now() WHERE key = $1', [key, JSON.stringify(value)]);
            await logAction(tx, adminId(request), 'update', 'setting', null, `${key}: ${JSON.stringify(rows[0].value)} → ${JSON.stringify(value)}`);
            return { ok: true };
          });
        });

        secure.get('/app-versions', async () => {
          const { rows } = await app.pool.query(
            'SELECT platform, min_version AS "minVersion", latest_version AS "latestVersion" FROM app_versions ORDER BY platform',
          );
          return { versions: rows };
        });

        secure.put('/app-versions/:platform', async (request) => {
          const { platform } = parse(z.object({ platform: z.enum(['android', 'ios', 'web']) }), request.params);
          const body = parse(z.object({ minVersion: z.string().trim(), latestVersion: z.string().trim() }), request.body);
          if (!isValidVersion(body.minVersion) || !isValidVersion(body.latestVersion)) throw new AppError(400, 'invalid_version');
          if (compareVersions(body.minVersion, body.latestVersion) > 0) throw new AppError(400, 'invalid_version');
          await app.pool.query(
            'UPDATE app_versions SET min_version = $2, latest_version = $3, updated_at = now() WHERE platform = $1',
            [platform, body.minVersion, body.latestVersion],
          );
          await logAction(app.pool, adminId(request), 'update', 'app_version', null, `${platform}: ${body.minVersion} / ${body.latestVersion}`);
          return { ok: true };
        });

        secure.get('/actions', async () => {
          const { rows } = await app.pool.query(
            `SELECT x.id, x.action, x.target_type AS "targetType", x.target_id AS "targetId", x.note,
                    x.created_at AS "createdAt", ad.username
             FROM admin_actions x LEFT JOIN admins ad ON ad.id = x.admin_id
             ORDER BY x.id DESC LIMIT 100`,
          );
          return { actions: rows };
        });
      });
    },
    { prefix: '/admin/api' },
  );
}
