import type { Pool } from '../src/db/pool.js';

/** وقت محلي في بغداد (UTC+3) كوقت عالمي: local('2026-10-05', '09:00'). */
export function local(date: string, time: string): Date {
  return new Date(`${date}T${time}:00+03:00`);
}

// الاثنين 5 تشرين الأول 2026 هو يوم العمل المرجعي في الاختبارات
export const MONDAY = '2026-10-05';
export const TUESDAY = '2026-10-06';

let phoneCounter = 0;

export async function createUser(pool: Pool, name = 'زبون') {
  const phone = `0770${String(++phoneCounter).padStart(7, '0')}`;
  const { rows } = await pool.query('INSERT INTO users (phone, name) VALUES ($1, $2) RETURNING id', [phone, name]);
  const userId: number = rows[0].id;
  const deviceId = await addDevice(pool, userId);
  return { userId, deviceId, phone };
}

export async function addDevice(pool: Pool, userId: number): Promise<number> {
  const tag = `${userId}-${Math.random().toString(36).slice(2)}`;
  const { rows } = await pool.query(
    `INSERT INTO devices (user_id, device_identifier, token_hash) VALUES ($1, $2, $3) RETURNING id`,
    [userId, `device-${tag}`, `hash-${tag}`],
  );
  return rows[0].id;
}

export interface ShopFixture {
  shopId: number;
  ownerId: number;
  scheduleId: number;
  haircut: number; // 30 دقيقة
  beard: number; // 15 دقيقة
}

/**
 * محل مقبول، يعمل الاثنين 09:00–12:00 و 16:00–20:00 (الفراغ بينهما استراحة).
 * minLead = 0 حتى تتحكم الاختبارات بالحد الأدنى من الإعدادات العامة وحدها.
 */
export async function createShop(pool: Pool, options: Partial<{
  instantBooking: boolean;
  bufferMinutes: number;
  minLeadMinutes: number;
  deadlineMode: 'fast' | 'normal' | 'flexible';
  freeCancelHours: number;
}> = {}): Promise<ShopFixture> {
  const owner = await createUser(pool, 'صاحب محل');
  const { rows: [area] } = await pool.query(
    `INSERT INTO areas (district_id, name) VALUES ((SELECT min(id) FROM districts), $1) RETURNING id, district_id`,
    [`منطقة ${owner.userId}`],
  );
  const { rows: [shop] } = await pool.query(
    `INSERT INTO shops (owner_id, name, business_type_id, district_id, area_id, latitude, longitude, status,
                        instant_booking, buffer_minutes, min_lead_minutes, deadline_mode, free_cancel_hours)
     VALUES ($1, 'صالون', (SELECT min(id) FROM business_types), $2, $3, 30.5, 47.8, 'approved', $4, $5, $6, $7, $8)
     RETURNING id`,
    [owner.userId, area.district_id, area.id, options.instantBooking ?? false, options.bufferMinutes ?? 0,
      options.minLeadMinutes ?? 0, options.deadlineMode ?? 'normal', options.freeCancelHours ?? 2],
  );
  const { rows: [schedule] } = await pool.query('INSERT INTO schedules (shop_id) VALUES ($1) RETURNING id', [shop.id]);
  await pool.query(
    `INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time)
     VALUES ($1, 1, '09:00', '12:00'), ($1, 1, '16:00', '20:00')`,
    [schedule.id],
  );
  const { rows: services } = await pool.query(
    `INSERT INTO services (shop_id, name, duration_minutes, price_type, price)
     VALUES ($1, 'حلاقة', 30, 'fixed', 10000), ($1, 'لحية', 15, 'fixed', 5000) RETURNING id`,
    [shop.id],
  );
  return {
    shopId: shop.id,
    ownerId: owner.userId,
    scheduleId: schedule.id,
    haircut: services[0].id,
    beard: services[1].id,
  };
}

export async function resetBookings(pool: Pool) {
  await pool.query('TRUNCATE bookings, commitment_events RESTART IDENTITY CASCADE');
}
