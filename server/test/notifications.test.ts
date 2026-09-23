import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { hashToken } from '../src/auth/tokens.js';
import { acceptBooking, createBooking, proposeTimes } from '../src/booking/bookings.js';
import { runMinuteJobs } from '../src/booking/jobs.js';
import { addDays, toLocalDate } from '../src/booking/time.js';
import type { Pool } from '../src/db/pool.js';
import { Notifier } from '../src/notify/notifier.js';
import type { PushMessage, PushSender } from '../src/notify/sender.js';
import { formatWhen, renderText } from '../src/notify/texts.js';
import { addDevice, createShop, createUser, local, MONDAY, resetBookings, type ShopFixture } from './fixtures.js';
import { appHeaders, freshDatabase } from './helpers.js';

class FakeSender implements PushSender {
  sent: { tokens: string[]; message: PushMessage }[] = [];
  invalid = new Set<string>();
  async send(tokens: string[], message: PushMessage) {
    this.sent.push({ tokens, message });
    return { invalidTokens: tokens.filter((t) => this.invalid.has(t)) };
  }
  types = () => this.sent.map((s) => s.message.data.type);
}

let pool: Pool;
let app: FastifyInstance;
let sender: FakeSender;
let shop: ShopFixture;
let customer: { userId: number; deviceId: number; token: string };
let ownerToken: string;
let keyCounter = 0;

/** جهاز بمفتاح دخول معروف ومفتاح إشعارات */
async function withToken(userId: number, deviceId: number, token: string) {
  await pool.query('UPDATE devices SET token_hash = $1, push_token = $2 WHERE id = $3', [hashToken(token), `push-${token}`, deviceId]);
  return token;
}

function call(method: 'GET' | 'POST' | 'PUT', url: string, token: string, body?: unknown) {
  return app.inject({
    method,
    url,
    headers: { ...appHeaders, authorization: `Bearer ${token}`, 'idempotency-key': `notify-${Date.now()}-${++keyCounter}` },
    payload: body as object | undefined,
  });
}

beforeAll(async () => {
  pool = await freshDatabase();
  sender = new FakeSender();
  app = await buildApp({ pool, logLevel: 'silent', sender });
  shop = await createShop(pool);
  await pool.query('DELETE FROM weekly_periods WHERE schedule_id = $1', [shop.scheduleId]);
  for (let d = 0; d < 7; d++) {
    await pool.query(
      `INSERT INTO weekly_periods (schedule_id, day_of_week, start_time, end_time) VALUES ($1, $2, '09:00', '21:00')`,
      [shop.scheduleId, d],
    );
  }
  const { rows } = await pool.query('SELECT min(id) AS id FROM devices WHERE user_id = $1', [shop.ownerId]);
  ownerToken = await withToken(shop.ownerId, rows[0].id, 'owner-token');
  const c = await createUser(pool, 'حسن');
  customer = { ...c, token: await withToken(c.userId, c.deviceId, 'customer-token') };
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

beforeEach(async () => {
  await resetBookings(pool);
  await pool.query('DELETE FROM notifications');
  sender.sent = [];
});

describe('texts', () => {
  it('formats the time in Baghdad with a 12-hour clock', () => {
    expect(formatWhen(local(MONDAY, '16:30').toISOString())).toBe('الإثنين 5 تشرين الأول · 4:30 م');
    expect(formatWhen(local(MONDAY, '00:15').toISOString())).toBe('الإثنين 5 تشرين الأول · 12:15 ص');
  });

  it('uses Arabic number agreement for durations', () => {
    expect(renderText('new_request', { customer: 'حسن', startsAt: local(MONDAY, '10:00').toISOString(), minutes: 60 }).body)
      .toBe('حسن يطلب موعداً الإثنين 5 تشرين الأول · 10:00 ص. رُدّ خلال ساعة واحدة.');
    expect(renderText('deadline_final', { customer: 'حسن', minutes: 5 }).body).toBe('بقي 5 دقائق فقط على طلب حسن.');
    expect(renderText('morning_summary', { count: 2 }).body).toBe('عندك حجزان اليوم.');
  });
});

describe('booking events over the API', () => {
  const tomorrowNoon = () => new Date(`${addDays(toLocalDate(new Date()), 1)}T12:00:00+03:00`).toISOString();

  it('tells the shop about a new request and the customer about the answer', async () => {
    const res = await call('POST', '/v1/bookings', customer.token, { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrowNoon() });
    expect(res.statusCode).toBe(200);
    const bookingId = res.json().booking.id;
    expect(sender.sent).toHaveLength(1);
    expect(sender.sent[0]!.tokens).toEqual(['push-owner-token']);
    expect(sender.sent[0]!.message).toMatchObject({ title: 'طلب حجز جديد', urgent: true, data: { type: 'new_request', audience: 'shop', bookingId: String(bookingId) } });
    expect(sender.sent[0]!.message.body).toContain('حسن يطلب موعداً');

    // إعادة الطلب نفسه (المفتاح نفسه) لا ترسل إشعاراً ثانياً
    expect((await call('POST', `/v1/owner/bookings/${bookingId}/accept`, ownerToken)).statusCode).toBe(200);
    expect(sender.types()).toEqual(['new_request', 'accepted']);
    expect(sender.sent[1]!.tokens).toEqual(['push-customer-token']);
    expect(sender.sent[1]!.message.body).toContain('صالون');

    await call('POST', `/v1/bookings/${bookingId}/cancel`, customer.token);
    expect(sender.types()).toEqual(['new_request', 'accepted', 'customer_cancelled']);
  });

  it('does not send twice when the app retries with the same key', async () => {
    const headers = { ...appHeaders, authorization: `Bearer ${customer.token}`, 'idempotency-key': 'same-key-123' };
    const payload = { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrowNoon() };
    await app.inject({ method: 'POST', url: '/v1/bookings', headers, payload });
    await app.inject({ method: 'POST', url: '/v1/bookings', headers, payload });
    expect(sender.types()).toEqual(['new_request']);
  });

  it('notifies about proposals and the customer choice', async () => {
    const res = await call('POST', '/v1/bookings', customer.token, { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrowNoon() });
    const bookingId = res.json().booking.id;
    const alt = new Date(Date.parse(tomorrowNoon()) + 2 * 3600_000).toISOString();
    expect((await call('POST', `/v1/owner/bookings/${bookingId}/propose`, ownerToken, { times: [alt] })).statusCode).toBe(200);
    const proposal = sender.sent.at(-1)!.message;
    expect(proposal.data.type).toBe('proposal');
    expect(proposal.body).toMatch(/اختر خلال/);

    const view = await call('GET', `/v1/bookings/${bookingId}`, customer.token);
    const proposedTimeId = view.json().booking.proposedTimes[0].id;
    await call('POST', `/v1/bookings/${bookingId}/choose`, customer.token, { proposedTimeId });
    expect(sender.types()).toEqual(['new_request', 'proposal', 'customer_chose']);
  });

  it('forgets tokens that no longer work', async () => {
    sender.invalid.add('push-owner-token');
    await call('POST', '/v1/bookings', customer.token, { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrowNoon() });
    const { rows } = await pool.query('SELECT push_token FROM devices WHERE token_hash = $1', [hashToken(ownerToken)]);
    expect(rows[0].push_token).toBeNull();
    sender.invalid.clear();
    await call('PUT', '/v1/me/push-token', ownerToken, { token: 'push-owner-token', enabled: true });
  });

  it('never pushes shop notifications to an untrusted device of the owner', async () => {
    const other = await addDevice(pool, shop.ownerId);
    await withToken(shop.ownerId, other, 'owner-second-phone');
    await call('POST', '/v1/bookings', customer.token, { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrowNoon() });
    expect(sender.sent[0]!.tokens).toEqual(['push-owner-token']);
    expect((await call('GET', '/v1/me/notifications?audience=shop', 'owner-second-phone')).statusCode).toBe(403);
    await pool.query('DELETE FROM devices WHERE id = $1', [other]);
  });
});

describe('in-app list and settings', () => {
  it('lists notifications with rendered text and marks them read', async () => {
    const tomorrow = new Date(`${addDays(toLocalDate(new Date()), 1)}T12:00:00+03:00`).toISOString();
    await call('POST', '/v1/bookings', customer.token, { shopId: shop.shopId, serviceIds: [shop.haircut], startsAt: tomorrow });

    let list = (await call('GET', '/v1/me/notifications?audience=shop', ownerToken)).json();
    expect(list.unreadCount).toBe(1);
    expect(list.notifications[0]).toMatchObject({ type: 'new_request', title: 'طلب حجز جديد', read: false });
    // إشعارات المحل منفصلة عن إشعاراته كزبون
    expect((await call('GET', '/v1/me/notifications', ownerToken)).json().notifications).toHaveLength(0);

    await call('POST', '/v1/me/notifications/read', ownerToken, { audience: 'shop' });
    list = (await call('GET', '/v1/me/notifications?audience=shop', ownerToken)).json();
    expect(list.unreadCount).toBe(0);
    expect(list.notifications[0].read).toBe(true);
  });

  it('turns reminders off but keeps the important notifications', async () => {
    const res = await call('PUT', '/v1/me/notification-settings', ownerToken, { reminders: false });
    expect(res.json()).toEqual({ reminders: false, morningSummary: true });
    const notifier = new Notifier(pool, sender);
    expect(await notifier.notify({ userId: shop.ownerId, type: 'deadline_half', params: { customer: 'x', minutes: 10 } })).toBe(false);
    expect(await notifier.notify({ userId: shop.ownerId, type: 'new_request', params: { customer: 'x', minutes: 10 } })).toBe(true);
    await call('PUT', '/v1/me/notification-settings', ownerToken, { reminders: true });
  });
});

describe('reminder jobs', () => {
  // المحل يرد خلال 60 دقيقة على طلب لموعد الغد (الجدول العادي)
  const created = local(MONDAY, '10:00');
  const book = () =>
    createBooking(pool, {
      customerId: customer.userId,
      deviceId: customer.deviceId,
      shopId: shop.shopId,
      serviceIds: [shop.haircut],
      startsAt: local('2026-10-06', '12:00'),
      now: created,
    });
  const at = (minutes: number) => new Date(created.getTime() + minutes * 60_000);
  const jobs = (now: Date) => runMinuteJobs(pool, now, app.notifier);

  it('reminds the shop at half the deadline and five minutes before, once each', async () => {
    await book();
    await jobs(at(20));
    expect(sender.types()).toEqual([]);
    await jobs(at(30));
    await jobs(at(31));
    expect(sender.types()).toEqual(['deadline_half']);
    expect(sender.sent[0]!.message.body).toBe('بقي 30 دقيقة على طلب حسن، وبعدها يُلغى تلقائياً.');
    await jobs(at(55));
    await jobs(at(56));
    expect(sender.types()).toEqual(['deadline_half', 'deadline_final']);
    expect(sender.sent[1]!.message.urgent).toBe(true);
  });

  it('tells the customer when the shop did not answer in time', async () => {
    await book();
    const { expired } = await jobs(at(61));
    expect(expired).toHaveLength(1);
    expect(sender.types().at(-1)).toBe('expired_shop');
    expect(sender.sent.at(-1)!.tokens).toEqual(['push-customer-token']);
  });

  it('reminds the customer to choose a proposed time, and says when it expired', async () => {
    const b = await book();
    await proposeTimes(pool, { bookingId: b.id, ownerId: shop.ownerId, now: at(5), times: [local('2026-10-06', '15:00')] });
    const { rows } = await pool.query('SELECT response_deadline FROM bookings WHERE id = $1', [b.id]);
    const window = (rows[0].response_deadline.getTime() - at(5).getTime()) / 60_000;
    await jobs(new Date(at(5).getTime() + (window / 2) * 60_000));
    expect(sender.types()).toEqual(['proposal_half']);
    await jobs(new Date(rows[0].response_deadline.getTime() + 60_000));
    expect(sender.types()).toEqual(['proposal_half', 'expired_customer']);
  });

  it('reminds the customer an hour before the appointment', async () => {
    const b = await book();
    await acceptBooking(pool, { bookingId: b.id, ownerId: shop.ownerId, now: at(10) });
    // ملخص الصباح لصاحب المحل يصل أيضاً في هذه الساعات
    const reminders = () => sender.sent.filter((s) => s.message.data.type === 'appointment_reminder');
    await jobs(local('2026-10-06', '10:30'));
    expect(reminders()).toHaveLength(0);
    await jobs(local('2026-10-06', '11:00'));
    await jobs(local('2026-10-06', '11:05'));
    expect(reminders()).toHaveLength(1);
    expect(reminders()[0]!.message.title).toBe('موعدك بعد ساعة');
    expect(reminders()[0]!.tokens).toEqual(['push-customer-token']);
  });

  it('sends the owner a morning summary of today once', async () => {
    const b = await book();
    await acceptBooking(pool, { bookingId: b.id, ownerId: shop.ownerId, now: at(10) });
    await jobs(local('2026-10-06', '07:59'));
    expect(sender.types()).toEqual([]);
    await jobs(local('2026-10-06', '08:00'));
    await jobs(local('2026-10-06', '08:01'));
    expect(sender.types()).toEqual(['morning_summary']);
    expect(sender.sent[0]!.message.body).toBe('عندك حجز واحد اليوم.');
  });
});
