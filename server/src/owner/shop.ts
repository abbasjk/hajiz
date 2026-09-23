import type { Pool } from '../db/pool.js';
import type { Queryable } from '../booking/db.js';
import { withTransaction } from '../booking/tx.js';
import { loadSettings } from '../booking/settings.js';
import { isLocalDate, toLocalDate } from '../booking/time.js';
import { AppError } from '../lib/errors.js';
import { validatePeriods, type PeriodInput } from './periods.js';

export interface OwnedShop {
  id: number;
  status: 'draft' | 'under_review' | 'approved' | 'rejected' | 'suspended';
  scheduleId: number;
}

/** محل صاحب العمل (محل واحد لكل صاحب عمل)، أو خطأ إذا لم يبدأ طلباً بعد. */
export async function requireShop(db: Queryable, ownerId: number, { lock = false } = {}): Promise<OwnedShop> {
  const { rows } = await db.query(
    `SELECT s.id, s.status, (SELECT id FROM schedules WHERE shop_id = s.id ORDER BY id LIMIT 1) AS "scheduleId"
     FROM shops s WHERE s.owner_id = $1${lock ? ' FOR UPDATE' : ''}`,
    [ownerId],
  );
  if (!rows[0]) throw new AppError(404, 'no_shop');
  return rows[0];
}

/** ما يُعدّل بعد القبول يظهر للزبائن مباشرة؛ الموقوف لا يعدّل شيئاً. */
function requireEditable(shop: OwnedShop) {
  if (shop.status === 'suspended') throw new AppError(403, 'shop_suspended');
}

export async function getOwnerShop(db: Queryable, ownerId: number) {
  const { rows } = await db.query(
    `SELECT s.id, s.name, s.status, s.review_note AS "reviewNote",
            s.business_type_id AS "businessTypeId", s.description, s.phone,
            s.district_id AS "districtId", s.area_id AS "areaId", s.street, s.landmark,
            s.latitude, s.longitude, s.deadline_mode AS "deadlineMode", s.free_cancel_hours AS "freeCancelHours",
            s.min_lead_minutes AS "minLeadMinutes", s.instant_booking AS "instantBooking",
            s.buffer_minutes AS "bufferMinutes", s.plan,
            (SELECT id FROM schedules WHERE shop_id = s.id ORDER BY id LIMIT 1) AS schedule_id
     FROM shops s WHERE s.owner_id = $1`,
    [ownerId],
  );
  const shop = rows[0];
  if (!shop) return null;
  const { schedule_id: scheduleId, ...details } = shop;
  const today = toLocalDate(new Date());
  const [services, hours, temps, photos, closures] = await Promise.all([
    db.query(
      `SELECT id, name, duration_minutes AS "durationMinutes", price_type AS "priceType", price, active
       FROM services WHERE shop_id = $1 ORDER BY id`,
      [shop.id],
    ),
    db.query(
      `SELECT day_of_week AS "dayOfWeek", to_char(start_time, 'HH24:MI') AS "from", to_char(end_time, 'HH24:MI') AS "to"
       FROM weekly_periods WHERE schedule_id = $1 ORDER BY day_of_week, start_time`,
      [scheduleId],
    ),
    db.query(
      `SELECT t.id, t.name, to_char(t.from_date, 'YYYY-MM-DD') AS "fromDate", to_char(t.to_date, 'YYYY-MM-DD') AS "toDate",
              coalesce((SELECT json_agg(json_build_object('dayOfWeek', p.day_of_week,
                         'from', to_char(p.start_time, 'HH24:MI'), 'to', to_char(p.end_time, 'HH24:MI'))
                         ORDER BY p.day_of_week, p.start_time)
                        FROM temporary_schedule_periods p WHERE p.temporary_schedule_id = t.id), '[]') AS periods
       FROM temporary_schedules t WHERE t.schedule_id = $1 AND t.to_date >= $2::date ORDER BY t.from_date`,
      [scheduleId, today],
    ),
    db.query(
      `SELECT id, coalesce(url, '/photos/' || id) AS url FROM shop_photos WHERE shop_id = $1 ORDER BY sort_order, id`,
      [shop.id],
    ),
    db.query(
      `SELECT id, starts_at AS "startsAt", ends_at AS "endsAt", reason FROM closures
       WHERE schedule_id = $1 AND ends_at > now() ORDER BY starts_at`,
      [scheduleId],
    ),
  ]);
  return {
    ...details,
    services: services.rows,
    weeklyHours: hours.rows,
    temporarySchedules: temps.rows,
    photos: photos.rows,
    closures: closures.rows,
  };
}

export interface ShopDetailsInput {
  name?: string;
  businessTypeId?: number | null;
  description?: string | null;
  phone?: string | null;
  districtId?: number | null;
  areaId?: number | null;
  street?: string | null;
  landmark?: string | null;
  latitude?: number | null;
  longitude?: number | null;
}

const DETAIL_COLUMNS: Record<keyof ShopDetailsInput, string> = {
  name: 'name',
  businessTypeId: 'business_type_id',
  description: 'description',
  phone: 'phone',
  districtId: 'district_id',
  areaId: 'area_id',
  street: 'street',
  landmark: 'landmark',
  latitude: 'latitude',
  longitude: 'longitude',
};

/**
 * يحفظ بيانات المحل خطوة بخطوة. أول حفظ يُنشئ المحل بحالة "مسودة" مع جدوله،
 * فيكمله صاحب المحل لاحقاً من حيث توقف.
 */
export async function saveShopDetails(pool: Pool, ownerId: number, input: ShopDetailsInput) {
  return withTransaction(pool, async (tx) => {
    if (input.areaId && input.districtId) {
      const { rowCount } = await tx.query('SELECT 1 FROM areas WHERE id = $1 AND district_id = $2', [input.areaId, input.districtId]);
      if (!rowCount) throw new AppError(400, 'area_not_in_district');
    }
    const existing = await tx.query<{ id: number; status: OwnedShop['status'] }>(
      'SELECT id, status FROM shops WHERE owner_id = $1 FOR UPDATE',
      [ownerId],
    );
    const entries = (Object.keys(DETAIL_COLUMNS) as (keyof ShopDetailsInput)[])
      .filter((k) => input[k] !== undefined)
      .map((k) => [DETAIL_COLUMNS[k], input[k]] as const);

    if (!existing.rows[0]) {
      if (!input.name?.trim()) throw new AppError(400, 'name_required');
      const cols = entries.map(([c]) => c);
      const { rows } = await tx.query(
        `INSERT INTO shops (owner_id, ${cols.join(', ')}) VALUES ($1, ${cols.map((_, i) => `$${i + 2}`).join(', ')})
         RETURNING id`,
        [ownerId, ...entries.map(([, v]) => v)],
      );
      await tx.query('INSERT INTO schedules (shop_id) VALUES ($1)', [rows[0].id]);
      return;
    }
    requireEditable({ ...existing.rows[0], scheduleId: 0 });
    if (entries.length === 0) return;
    try {
      await tx.query(
        `UPDATE shops SET ${entries.map(([c], i) => `${c} = $${i + 2}`).join(', ')}, updated_at = now() WHERE id = $1`,
        [existing.rows[0].id, ...entries.map(([, v]) => v)],
      );
    } catch (err) {
      // المحل المرسل أو المقبول لا يُفرَّغ من حقوله الإجبارية
      if ((err as { code?: string }).code === '23514') throw new AppError(400, 'required_field');
      throw err;
    }
  });
}

/** ما ينقص المحل قبل إرساله للمراجعة؛ القائمة الفارغة تعني أنه جاهز. */
export async function missingForReview(db: Queryable, shopId: number): Promise<string[]> {
  const { rows } = await db.query(
    `SELECT s.name, s.business_type_id, s.district_id, s.area_id, s.latitude,
            (SELECT count(*)::int FROM services WHERE shop_id = s.id AND active) AS services,
            (SELECT count(*)::int FROM weekly_periods wp JOIN schedules sc ON sc.id = wp.schedule_id WHERE sc.shop_id = s.id) AS periods
     FROM shops s WHERE s.id = $1`,
    [shopId],
  );
  const s = rows[0];
  const missing: string[] = [];
  if (!s.business_type_id) missing.push('businessType');
  if (!s.district_id || !s.area_id) missing.push('address');
  if (s.latitude === null) missing.push('location');
  if (s.services === 0) missing.push('services');
  if (s.periods === 0) missing.push('hours');
  return missing;
}

/** فتح المحل بعد مراجعة الإدارة وموافقتها فقط. */
export async function submitForReview(pool: Pool, ownerId: number) {
  return withTransaction(pool, async (tx) => {
    const shop = await requireShop(tx, ownerId, { lock: true });
    if (shop.status !== 'draft' && shop.status !== 'rejected') {
      throw new AppError(409, 'invalid_transition', { status: shop.status });
    }
    const missing = await missingForReview(tx, shop.id);
    if (missing.length) throw new AppError(400, 'incomplete_shop', { missing });
    await tx.query(`UPDATE shops SET status = 'under_review', review_note = NULL, updated_at = now() WHERE id = $1`, [shop.id]);
  });
}

// ============================================================
// الخدمات
// ============================================================

export interface ServiceInput {
  name: string;
  durationMinutes: number;
  priceType: 'fixed' | 'starts_from' | 'after_inspection';
  price: number | null;
  active?: boolean;
}

function checkService(s: ServiceInput) {
  if (!s.name.trim() || s.durationMinutes < 5 || s.durationMinutes > 8 * 60 || s.durationMinutes % 5 !== 0) {
    throw new AppError(400, 'invalid_service');
  }
  const needsPrice = s.priceType !== 'after_inspection';
  if (needsPrice !== (s.price !== null && s.price >= 0)) throw new AppError(400, 'invalid_service');
}

export async function addService(pool: Pool, ownerId: number, input: ServiceInput) {
  checkService(input);
  const shop = await requireShop(pool, ownerId);
  requireEditable(shop);
  const { rows } = await pool.query(
    `INSERT INTO services (shop_id, name, duration_minutes, price_type, price) VALUES ($1, $2, $3, $4, $5) RETURNING id`,
    [shop.id, input.name.trim(), input.durationMinutes, input.priceType, input.priceType === 'after_inspection' ? null : input.price],
  );
  return rows[0].id as number;
}

/** الحجوزات القديمة لا تتأثر: السعر والمدة محفوظان داخل كل حجز. */
export async function updateService(pool: Pool, ownerId: number, serviceId: number, input: ServiceInput) {
  checkService(input);
  const shop = await requireShop(pool, ownerId);
  requireEditable(shop);
  const { rowCount } = await pool.query(
    `UPDATE services SET name = $3, duration_minutes = $4, price_type = $5, price = $6, active = $7
     WHERE id = $1 AND shop_id = $2`,
    [serviceId, shop.id, input.name.trim(), input.durationMinutes, input.priceType,
      input.priceType === 'after_inspection' ? null : input.price, input.active ?? true],
  );
  if (!rowCount) throw new AppError(404, 'service_not_found');
}

// ============================================================
// أوقات العمل والجداول المؤقتة
// ============================================================

/** يستبدل الجدول الأسبوعي كله. لا جدول للاستراحات: الفراغ بين الفترات استراحة. */
export async function setWeeklyHours(pool: Pool, ownerId: number, periods: PeriodInput[]) {
  validatePeriods(periods);
  return withTransaction(pool, async (tx) => {
    const shop = await requireShop(tx, ownerId, { lock: true });
    requireEditable(shop);
    if (periods.length === 0 && shop.status !== 'draft' && shop.status !== 'rejected') {
      throw new AppError(400, 'hours_required');
    }
    await tx.query('DELETE FROM weekly_periods WHERE schedule_id = $1', [shop.scheduleId]);
    for (const p of periods) {
      await tx.query(
        'INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time) VALUES ($1, $2, $3, $4)',
        [shop.scheduleId, p.dayOfWeek, p.from, p.to],
      );
    }
  });
}

export interface TemporaryScheduleInput {
  name: string;
  fromDate: string;
  toDate: string;
  periods: PeriodInput[];
}

/** جدول مؤقت لرمضان والأعياد؛ بعد انتهائه يعود الجدول الأسبوعي تلقائياً. */
export async function addTemporarySchedule(pool: Pool, ownerId: number, input: TemporaryScheduleInput) {
  if (!input.name.trim() || !isLocalDate(input.fromDate) || !isLocalDate(input.toDate) || input.toDate < input.fromDate) {
    throw new AppError(400, 'invalid_temporary_schedule');
  }
  validatePeriods(input.periods);
  return withTransaction(pool, async (tx) => {
    const shop = await requireShop(tx, ownerId, { lock: true });
    requireEditable(shop);
    const overlap = await tx.query(
      'SELECT 1 FROM temporary_schedules WHERE schedule_id = $1 AND from_date <= $3 AND to_date >= $2',
      [shop.scheduleId, input.fromDate, input.toDate],
    );
    if (overlap.rowCount) throw new AppError(409, 'temporary_schedule_overlap');
    const { rows } = await tx.query(
      'INSERT INTO temporary_schedules (schedule_id, name, from_date, to_date) VALUES ($1, $2, $3, $4) RETURNING id',
      [shop.scheduleId, input.name.trim(), input.fromDate, input.toDate],
    );
    for (const p of input.periods) {
      await tx.query(
        `INSERT INTO temporary_schedule_periods (temporary_schedule_id, day_of_week, start_time, end_time)
         VALUES ($1, $2, $3, $4)`,
        [rows[0].id, p.dayOfWeek, p.from, p.to],
      );
    }
    return rows[0].id as number;
  });
}

export async function deleteTemporarySchedule(pool: Pool, ownerId: number, id: number) {
  const shop = await requireShop(pool, ownerId);
  requireEditable(shop);
  const { rowCount } = await pool.query('DELETE FROM temporary_schedules WHERE id = $1 AND schedule_id = $2', [id, shop.scheduleId]);
  if (!rowCount) throw new AppError(404, 'temporary_schedule_not_found');
}

// ============================================================
// إعدادات الحجز
// ============================================================

export interface BookingSettingsInput {
  deadlineMode?: 'fast' | 'normal' | 'flexible';
  freeCancelHours?: number;
  instantBooking?: boolean;
  bufferMinutes?: number;
  minLeadMinutes?: number;
}

export async function updateBookingSettings(pool: Pool, ownerId: number, input: BookingSettingsInput) {
  const shop = await requireShop(pool, ownerId);
  requireEditable(shop);
  const settings = await loadSettings(pool);
  if (input.freeCancelHours !== undefined && ![1, 2, 6, 24].includes(input.freeCancelHours)) {
    throw new AppError(400, 'invalid_settings');
  }
  if (input.bufferMinutes !== undefined && (input.bufferMinutes < 0 || input.bufferMinutes > 120 || input.bufferMinutes % 5)) {
    throw new AppError(400, 'invalid_settings');
  }
  // أقل وقت قبل الحجز: صاحب المحل يستطيع زيادته فقط
  if (input.minLeadMinutes !== undefined && (input.minLeadMinutes < settings.minLeadMinutes || input.minLeadMinutes > 7 * 24 * 60)) {
    throw new AppError(400, 'invalid_settings');
  }
  const cols = {
    deadline_mode: input.deadlineMode,
    free_cancel_hours: input.freeCancelHours,
    instant_booking: input.instantBooking,
    buffer_minutes: input.bufferMinutes,
    min_lead_minutes: input.minLeadMinutes,
  };
  const entries = Object.entries(cols).filter(([, v]) => v !== undefined);
  if (!entries.length) return;
  await pool.query(
    `UPDATE shops SET ${entries.map(([c], i) => `${c} = $${i + 2}`).join(', ')}, updated_at = now() WHERE id = $1`,
    [shop.id, ...entries.map(([, v]) => v)],
  );
}

// ============================================================
// الصور وطلبات المناطق
// ============================================================

const PHOTO_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const MAX_PHOTO_BYTES = 1_500_000;

export async function addPhoto(pool: Pool, ownerId: number, contentType: string, base64: string) {
  if (!PHOTO_TYPES.has(contentType)) throw new AppError(400, 'invalid_photo');
  const data = Buffer.from(base64, 'base64');
  if (data.length === 0 || data.length > MAX_PHOTO_BYTES) throw new AppError(400, 'invalid_photo');
  return withTransaction(pool, async (tx) => {
    const shop = await requireShop(tx, ownerId, { lock: true });
    requireEditable(shop);
    const { rows: [limit] } = await tx.query(`SELECT value FROM settings WHERE key = 'max_shop_photos'`);
    const { rows: [count] } = await tx.query('SELECT count(*)::int AS n, coalesce(max(sort_order), 0) AS last FROM shop_photos WHERE shop_id = $1', [shop.id]);
    if (count.n >= Number(limit?.value ?? 8)) throw new AppError(409, 'too_many_photos');
    const { rows } = await tx.query(
      'INSERT INTO shop_photos (shop_id, data, content_type, sort_order) VALUES ($1, $2, $3, $4) RETURNING id',
      [shop.id, data, contentType, count.last + 1],
    );
    return rows[0].id as number;
  });
}

export async function deletePhoto(pool: Pool, ownerId: number, photoId: number) {
  const shop = await requireShop(pool, ownerId);
  requireEditable(shop);
  const { rowCount } = await pool.query('DELETE FROM shop_photos WHERE id = $1 AND shop_id = $2', [photoId, shop.id]);
  if (!rowCount) throw new AppError(404, 'photo_not_found');
}

/** إذا لم يجد صاحب المحل منطقته، يطلب إضافتها ونضيفها نحن من لوحة الإدارة. */
export async function requestArea(pool: Pool, ownerId: number, districtId: number, name: string) {
  const clean = name.trim();
  if (clean.length < 2 || clean.length > 60) throw new AppError(400, 'invalid_area_name');
  const { rowCount } = await pool.query('SELECT 1 FROM districts WHERE id = $1', [districtId]);
  if (!rowCount) throw new AppError(400, 'invalid_area_name');
  await pool.query('INSERT INTO area_requests (district_id, name, requested_by) VALUES ($1, $2, $3)', [districtId, clean, ownerId]);
}
