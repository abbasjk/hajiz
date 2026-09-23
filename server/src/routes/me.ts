import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authOf, requireAuth } from '../auth/hook.js';
import { AppError } from '../lib/errors.js';
import { renderText, type NotificationType, type TextParams } from '../notify/texts.js';

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const r = schema.safeParse(value);
  if (!r.success) throw new AppError(400, 'invalid_request');
  return r.data;
}

const audienceQuery = z.object({ audience: z.enum(['customer', 'shop']).default('customer') });

/** إشعارات المستخدم ومفتاح الإرسال لجهازه وتفضيلاته */
export async function meRoutes(app: FastifyInstance) {
  app.addHook('onRequest', requireAuth(app.pool));

  // التطبيق يرسل مفتاح FCM عند كل تشغيل؛ enabled=false إذا أوقف المستخدم الإشعارات من إعدادات الهاتف
  app.put('/me/push-token', async (request) => {
    const body = parse(z.object({ token: z.string().min(1).max(4096).nullable(), enabled: z.boolean() }), request.body);
    const { deviceId } = authOf(request);
    // المفتاح نفسه لا يبقى على جهازين (تسجيل رقم آخر على الهاتف نفسه)
    if (body.token) await app.pool.query('UPDATE devices SET push_token = NULL WHERE push_token = $1 AND id <> $2', [body.token, deviceId]);
    await app.pool.query('UPDATE devices SET push_token = $1, push_enabled = $2 WHERE id = $3', [body.token, body.enabled, deviceId]);
    return { ok: true };
  });

  // الجهاز غير الموثوق يرى إشعارات حجوزاته هو فقط، ولا يرى إشعارات المحل
  const visible = `n.user_id = $1 AND n.audience = $2
    AND ($3::boolean OR EXISTS (SELECT 1 FROM bookings b WHERE b.id = n.booking_id AND b.device_id = $4))`;

  app.get('/me/notifications', async (request) => {
    const { audience } = parse(audienceQuery, request.query);
    const auth = authOf(request);
    if (audience === 'shop' && !auth.trusted) throw new AppError(403, 'untrusted_device');
    const args = [auth.userId, audience, auth.trusted, auth.deviceId];
    const { rows } = await app.pool.query(
      `SELECT n.id, n.type, n.booking_id, n.params, n.read_at, n.created_at FROM notifications n
       WHERE ${visible} ORDER BY n.created_at DESC, n.id DESC LIMIT 50`,
      args,
    );
    const unread = await app.pool.query(`SELECT count(*)::int AS n FROM notifications n WHERE ${visible} AND n.read_at IS NULL`, args);
    return {
      notifications: rows.map((r) => ({
        id: Number(r.id),
        type: r.type,
        bookingId: r.booking_id === null ? null : Number(r.booking_id),
        ...renderText(r.type as NotificationType, r.params as TextParams),
        read: r.read_at !== null,
        createdAt: r.created_at.toISOString(),
      })),
      unreadCount: unread.rows[0].n,
      serverTime: new Date().toISOString(),
    };
  });

  app.post('/me/notifications/read', async (request) => {
    const { audience } = parse(audienceQuery, request.body ?? {});
    const auth = authOf(request);
    if (audience === 'shop' && !auth.trusted) throw new AppError(403, 'untrusted_device');
    await app.pool.query(`UPDATE notifications n SET read_at = now() WHERE ${visible} AND n.read_at IS NULL`, [
      auth.userId,
      audience,
      auth.trusted,
      auth.deviceId,
    ]);
    return { ok: true };
  });

  const settingsView = async (userId: number) => {
    const { rows } = await app.pool.query('SELECT notify_reminders, notify_morning_summary FROM users WHERE id = $1', [userId]);
    return { reminders: rows[0].notify_reminders as boolean, morningSummary: rows[0].notify_morning_summary as boolean };
  };

  app.get('/me/notification-settings', async (request) => settingsView(authOf(request).userId));

  // الإشعارات المهمة (الطلبات والردود والإلغاء) لا تُوقف؛ التذكيرات والملخص فقط
  app.put('/me/notification-settings', async (request) => {
    const body = parse(z.object({ reminders: z.boolean().optional(), morningSummary: z.boolean().optional() }), request.body);
    const { userId } = authOf(request);
    await app.pool.query(
      `UPDATE users SET notify_reminders = coalesce($2, notify_reminders),
                        notify_morning_summary = coalesce($3, notify_morning_summary) WHERE id = $1`,
      [userId, body.reminders ?? null, body.morningSummary ?? null],
    );
    return settingsView(userId);
  });
}
