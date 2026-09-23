import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Pool } from '../src/db/pool.js';
import { freshDatabase } from './helpers.js';

let pool: Pool;
let customerId: number;
let shopId: number;
let scheduleId: number;

beforeAll(async () => {
  pool = await freshDatabase();
  const owner = await pool.query(`INSERT INTO users (phone, name) VALUES ('07700000001', 'علي') RETURNING id`);
  const customer = await pool.query(`INSERT INTO users (phone, name) VALUES ('07700000002', 'حسن') RETURNING id`);
  customerId = customer.rows[0].id;
  const shop = await pool.query(`INSERT INTO shops (owner_id, name) VALUES ($1, 'صالون النخيل') RETURNING id`, [
    owner.rows[0].id,
  ]);
  shopId = shop.rows[0].id;
  const schedule = await pool.query(`INSERT INTO schedules (shop_id) VALUES ($1) RETURNING id`, [shopId]);
  scheduleId = schedule.rows[0].id;
});

beforeEach(async () => {
  await pool.query('DELETE FROM bookings');
});

afterAll(async () => {
  await pool.end();
});

function book(startsAt: string, endsAt: string, status = 'pending_shop') {
  return pool.query(
    `INSERT INTO bookings (customer_id, shop_id, schedule_id, starts_at, ends_at, status)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [customerId, shopId, scheduleId, startsAt, endsAt, status],
  );
}

describe('booking overlap constraint', () => {
  it('rejects two active bookings that overlap on the same schedule', async () => {
    await book('2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z', 'confirmed');
    await expect(book('2026-10-01T09:15:00Z', '2026-10-01T09:45:00Z')).rejects.toMatchObject({
      code: '23P01', // exclusion_violation
    });
  });

  it('allows back-to-back bookings', async () => {
    await book('2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z', 'confirmed');
    await expect(book('2026-10-01T09:30:00Z', '2026-10-01T10:00:00Z')).resolves.toBeDefined();
  });

  it('frees the time once a booking is cancelled or expired', async () => {
    await book('2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z', 'expired');
    await book('2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z', 'cancelled_by_customer');
    await expect(book('2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z')).resolves.toBeDefined();
  });

  it('does not let the response deadline pass the appointment time', async () => {
    await expect(
      pool.query(
        `INSERT INTO bookings (customer_id, shop_id, schedule_id, starts_at, ends_at, response_deadline)
         VALUES ($1, $2, $3, '2026-10-01T09:00:00Z', '2026-10-01T09:30:00Z', '2026-10-01T09:05:00Z')`,
        [customerId, shopId, scheduleId],
      ),
    ).rejects.toMatchObject({ code: '23514' }); // check_violation
  });
});

describe('shops', () => {
  it('cannot leave draft without the required address fields', async () => {
    await expect(pool.query(`UPDATE shops SET status = 'under_review' WHERE id = $1`, [shopId])).rejects.toMatchObject({
      code: '23514',
    });
  });

  it('allows only one shop per owner', async () => {
    const { rows } = await pool.query('SELECT owner_id FROM shops WHERE id = $1', [shopId]);
    await expect(
      pool.query(`INSERT INTO shops (owner_id, name) VALUES ($1, 'فرع ثاني')`, [rows[0].owner_id]),
    ).rejects.toMatchObject({ code: '23505' });
  });
});

describe('commitment events', () => {
  it('survive deleting the user because they are keyed by phone', async () => {
    const user = await pool.query(`INSERT INTO users (phone, name) VALUES ('07700000003', 'زيد') RETURNING phone`);
    await pool.query(`INSERT INTO commitment_events (phone, type, shop_id) VALUES ($1, 'no_show', $2)`, [
      user.rows[0].phone,
      shopId,
    ]);
    await pool.query(`DELETE FROM users WHERE phone = '07700000003'`);
    const { rowCount } = await pool.query(`SELECT 1 FROM commitment_events WHERE phone = '07700000003'`);
    expect(rowCount).toBe(1);
  });
});
