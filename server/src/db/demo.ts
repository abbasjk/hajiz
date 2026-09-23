import type { Pool } from './pool.js';
import { withTransaction } from '../booking/tx.js';

const DEMO_OWNER_PHONE = '07000000000';

/**
 * محل تجريبي لتجربة تطبيق الزبون قبل بناء واجهة صاحب المحل.
 * يُنشأ مرة واحدة فقط عند SEED_DEMO=true، ويعمل السبت إلى الخميس، والجمعة عطلة.
 */
export async function seedDemoShop(pool: Pool): Promise<boolean> {
  return withTransaction(pool, async (tx) => {
    const exists = await tx.query('SELECT 1 FROM users WHERE phone = $1', [DEMO_OWNER_PHONE]);
    if (exists.rowCount) return false;

    const { rows: [owner] } = await tx.query(
      `INSERT INTO users (phone, name) VALUES ($1, 'صاحب المحل التجريبي') RETURNING id`,
      [DEMO_OWNER_PHONE],
    );
    const { rows: [district] } = await tx.query(`SELECT id FROM districts WHERE name = 'البصرة'`);
    const { rows: [area] } = await tx.query(
      `INSERT INTO areas (district_id, name) VALUES ($1, 'منطقة تجريبية')
       ON CONFLICT (district_id, name) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
      [district.id],
    );
    const { rows: [type] } = await tx.query(`SELECT id FROM business_types WHERE name = 'حلاقة رجالية'`);
    const { rows: [shop] } = await tx.query(
      `INSERT INTO shops (owner_id, name, business_type_id, description, phone, district_id, area_id,
                          landmark, latitude, longitude, status)
       VALUES ($1, 'صالون تجريبي', $2, 'محل تجريبي لاختبار التطبيق، الحجوزات فيه ليست حقيقية.', $3, $4, $5,
               'نقطة تجريبية', 30.5085, 47.7804, 'approved')
       RETURNING id`,
      [owner.id, type.id, DEMO_OWNER_PHONE, district.id, area.id],
    );
    const { rows: [schedule] } = await tx.query('INSERT INTO schedules (shop_id) VALUES ($1) RETURNING id', [shop.id]);
    // السبت (6) إلى الخميس (4): صباحاً ومساءً، والفراغ بينهما استراحة
    for (const day of [6, 0, 1, 2, 3, 4]) {
      await tx.query(
        `INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time)
         VALUES ($1, $2, '09:00', '13:00'), ($1, $2, '16:00', '22:00')`,
        [schedule.id, day],
      );
    }
    await tx.query(
      `INSERT INTO services (shop_id, name, duration_minutes, price_type, price) VALUES
         ($1, 'حلاقة شعر', 30, 'fixed', 10000),
         ($1, 'تهذيب لحية', 15, 'fixed', 5000),
         ($1, 'حلاقة أطفال', 20, 'fixed', 7000),
         ($1, 'تنظيف بشرة', 45, 'starts_from', 15000)`,
      [shop.id],
    );
    return true;
  });
}
