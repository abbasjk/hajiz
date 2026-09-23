import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { loadShop, slotsForDate } from '../booking/availability.js';
import { loadSettings } from '../booking/settings.js';
import { addDays, toLocalDate } from '../booking/time.js';
import { AppError } from '../lib/errors.js';

const listQuery = z.object({
  businessTypeId: z.coerce.number().int().positive().optional(),
  districtId: z.coerce.number().int().positive().optional(),
  areaId: z.coerce.number().int().positive().optional(),
  q: z.string().trim().max(60).optional(),
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
  sort: z.enum(['name', 'distance', 'soonest']).default('name'),
});

const LIST_LIMIT = 50;
const SOONEST_DAYS = 7;

// شارة "ملتزم بمواعيده": عدد كافٍ من الحجوزات المنتهية ونسبة إلغاء قليلة من المحل
const COMMITTED_SQL = `(
  SELECT count(*) FILTER (WHERE b.status = 'completed') >= ($1::jsonb->>'min_bookings')::int
     AND count(*) FILTER (WHERE b.status = 'cancelled_by_shop')::float
         <= ($1::jsonb->>'max_shop_cancel_rate')::float
            * greatest(count(*) FILTER (WHERE b.status IN ('completed', 'cancelled_by_shop')), 1)
  FROM bookings b WHERE b.shop_id = s.id
)`;

async function badgeSetting(app: FastifyInstance): Promise<string> {
  const { rows } = await app.pool.query(`SELECT value FROM settings WHERE key = 'shop_commitment_badge'`);
  return JSON.stringify(rows[0]?.value ?? { min_bookings: 20, max_shop_cancel_rate: 0.05 });
}

export async function shopRoutes(app: FastifyInstance) {
  /** البحث بالاسم أو النوع أو المنطقة، مع ترتيب حسب القرب أو أقرب موعد متاح. */
  app.get('/shops', async (request) => {
    const parsed = listQuery.safeParse(request.query);
    if (!parsed.success) throw new AppError(400, 'invalid_request');
    const f = parsed.data;
    const hasLocation = f.lat !== undefined && f.lng !== undefined;
    if (f.sort === 'distance' && !hasLocation) throw new AppError(400, 'location_required');

    const params: unknown[] = [await badgeSetting(app)];
    const where = [`s.status = 'approved'`];
    const add = (sql: string, value: unknown) => {
      params.push(value);
      where.push(sql.replace('?', `$${params.length}`));
    };
    if (f.businessTypeId) add('s.business_type_id = ?', f.businessTypeId);
    if (f.districtId) add('s.district_id = ?', f.districtId);
    if (f.areaId) add('s.area_id = ?', f.areaId);
    if (f.q) add(`s.name ILIKE '%' || ? || '%'`, f.q.replace(/[%_\\]/g, (c) => `\\${c}`));

    let distance = 'NULL::float';
    if (hasLocation) {
      params.push(f.lat, f.lng);
      const la = `$${params.length - 1}`;
      const ln = `$${params.length}`;
      // المسافة بالكيلومتر (هافرساين) من إحداثيات المحل
      distance = `(6371 * 2 * asin(sqrt(
        power(sin(radians(s.latitude - ${la}) / 2), 2)
        + cos(radians(${la})) * cos(radians(s.latitude)) * power(sin(radians(s.longitude - ${ln}) / 2), 2))))`;
    }
    const order = f.sort === 'distance' ? 'distance_km ASC' : 's.name ASC';

    const { rows } = await app.pool.query(
      `SELECT s.id, s.name, s.business_type_id AS "businessTypeId", bt.name AS "businessType",
              s.district_id AS "districtId", d.name AS district, s.area_id AS "areaId", a.name AS area,
              s.landmark, s.latitude, s.longitude, s.instant_booking AS "instantBooking",
              ${distance} AS distance_km,
              (SELECT coalesce(url, '/photos/' || id) FROM shop_photos p WHERE p.shop_id = s.id ORDER BY sort_order, id LIMIT 1) AS "coverPhoto",
              ${COMMITTED_SQL} AS committed,
              (SELECT min(duration_minutes) FROM services sv WHERE sv.shop_id = s.id AND sv.active) AS min_duration
       FROM shops s
       LEFT JOIN business_types bt ON bt.id = s.business_type_id
       LEFT JOIN districts d ON d.id = s.district_id
       LEFT JOIN areas a ON a.id = s.area_id
       WHERE ${where.join(' AND ')}
       ORDER BY ${order}
       LIMIT ${LIST_LIMIT}`,
      params,
    );

    const shops = rows.map(({ distance_km, min_duration, ...r }) => ({
      ...r,
      distanceKm: distance_km === null ? null : Math.round(distance_km * 10) / 10,
      nextAvailable: null as string | null,
      _minDuration: min_duration as number | null,
    }));

    if (f.sort === 'soonest') {
      const now = new Date();
      const settings = await loadSettings(app.pool);
      const today = toLocalDate(now);
      for (const shop of shops) {
        if (!shop._minDuration) continue;
        const s = await loadShop(app.pool, shop.id);
        for (let i = 0; i < SOONEST_DAYS && !shop.nextAvailable; i++) {
          const slots = await slotsForDate(app.pool, {
            shop: s, durationMinutes: shop._minDuration, date: addDays(today, i), now, settings,
          });
          if (slots[0]) shop.nextAvailable = slots[0].toISOString();
        }
      }
      // المحلات بلا موعد قريب في آخر القائمة
      shops.sort((a, b) => (a.nextAvailable ?? '9999').localeCompare(b.nextAvailable ?? '9999'));
    }
    return { shops: shops.map(({ _minDuration, ...s }) => s) };
  });

  /** صفحة المحل: الصور، الخدمات والأسعار، الموقع، أوقات العمل، مؤشر الالتزام. */
  app.get('/shops/:shopId', async (request) => {
    const p = z.object({ shopId: z.coerce.number().int().positive() }).safeParse(request.params);
    if (!p.success) throw new AppError(400, 'invalid_request');
    const { rows } = await app.pool.query(
      `SELECT s.id, s.name, s.description, s.phone, bt.name AS "businessType",
              d.name AS district, a.name AS area, s.street, s.landmark, s.latitude, s.longitude,
              s.instant_booking AS "instantBooking", s.deadline_mode AS "deadlineMode",
              s.free_cancel_hours AS "freeCancelHours", ${COMMITTED_SQL} AS committed,
              (SELECT id FROM schedules WHERE shop_id = s.id ORDER BY id LIMIT 1) AS schedule_id
       FROM shops s
       LEFT JOIN business_types bt ON bt.id = s.business_type_id
       LEFT JOIN districts d ON d.id = s.district_id
       LEFT JOIN areas a ON a.id = s.area_id
       WHERE s.id = $2 AND s.status = 'approved'`,
      [await badgeSetting(app), p.data.shopId],
    );
    const shop = rows[0];
    if (!shop) throw new AppError(404, 'shop_not_found');
    const { schedule_id: scheduleId, ...details } = shop;

    const [photos, services, hours, temporary] = await Promise.all([
      app.pool.query(
        `SELECT coalesce(url, '/photos/' || id) AS url FROM shop_photos WHERE shop_id = $1 ORDER BY sort_order, id`,
        [shop.id],
      ),
      app.pool.query(
        `SELECT id, name, duration_minutes AS "durationMinutes", price_type AS "priceType", price
         FROM services WHERE shop_id = $1 AND active ORDER BY id`,
        [shop.id],
      ),
      app.pool.query(
        `SELECT day_of_week AS "dayOfWeek", to_char(start_time, 'HH24:MI') AS "from", to_char(end_time, 'HH24:MI') AS "to"
         FROM weekly_periods WHERE schedule_id = $1 ORDER BY day_of_week, start_time`,
        [scheduleId],
      ),
      app.pool.query(
        `SELECT name, to_char(from_date, 'YYYY-MM-DD') AS "fromDate", to_char(to_date, 'YYYY-MM-DD') AS "toDate"
         FROM temporary_schedules WHERE schedule_id = $1 AND to_date >= $2::date ORDER BY from_date LIMIT 3`,
        [scheduleId, toLocalDate(new Date())],
      ),
    ]);
    return {
      shop: {
        ...details,
        photos: photos.rows.map((r) => r.url),
        services: services.rows,
        weeklyHours: hours.rows,
        temporarySchedules: temporary.rows,
      },
    };
  });
}
