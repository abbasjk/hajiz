import type { FastifyBaseLogger } from 'fastify';
import type { Queryable } from '../booking/db.js';
import { AUDIENCE, OPTIONAL, renderText, URGENT, type NotificationType, type TextParams } from './texts.js';
import type { PushSender } from './sender.js';

export interface NotifyInput {
  userId: number;
  type: NotificationType;
  bookingId?: number;
  params: TextParams;
  /** يمنع إرسال التذكير نفسه مرتين */
  dedupeKey?: string;
}

/**
 * يحفظ الإشعار (يظهر داخل التطبيق مع علامة غير مقروء) ويرسله لأجهزة المستخدم.
 * إشعارات المحل تصل للأجهزة الموثوقة فقط؛ إشعارات الزبون أيضاً للجهاز الذي أُرسل منه الحجز.
 * أي خطأ هنا لا يُفشل العملية الأصلية.
 */
export class Notifier {
  constructor(
    private readonly db: Queryable,
    private readonly sender: PushSender,
    private readonly log?: FastifyBaseLogger,
  ) {}

  async notify(n: NotifyInput): Promise<boolean> {
    try {
      const optional = OPTIONAL[n.type];
      if (optional) {
        const { rows } = await this.db.query(
          'SELECT notify_reminders, notify_morning_summary FROM users WHERE id = $1',
          [n.userId],
        );
        const u = rows[0];
        if (!u) return false;
        if (optional === 'reminders' && !u.notify_reminders) return false;
        if (optional === 'morningSummary' && !u.notify_morning_summary) return false;
      }
      const audience = AUDIENCE[n.type];
      const inserted = await this.db.query(
        `INSERT INTO notifications (user_id, type, booking_id, audience, params, dedupe_key)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING
         RETURNING id`,
        [n.userId, n.type, n.bookingId ?? null, audience, JSON.stringify(n.params), n.dedupeKey ?? null],
      );
      if (!inserted.rowCount) return false;

      const { rows: devices } = await this.db.query<{ id: number; push_token: string }>(
        `SELECT d.id, d.push_token FROM devices d
         WHERE d.user_id = $1 AND d.push_token IS NOT NULL
           AND (d.verified_by_call_at IS NOT NULL
                OR d.id = (SELECT min(id) FROM devices WHERE user_id = $1)
                OR ($3 = 'customer' AND d.id = (SELECT device_id FROM bookings WHERE id = $2)))`,
        [n.userId, n.bookingId ?? 0, audience],
      );
      if (devices.length === 0) return true;

      const { title, body } = renderText(n.type, n.params);
      const { invalidTokens } = await this.sender.send(devices.map((d) => d.push_token), {
        title,
        body,
        urgent: URGENT.has(n.type),
        data: { type: n.type, audience, bookingId: n.bookingId ? String(n.bookingId) : '' },
      });
      if (invalidTokens.length) {
        await this.db.query('UPDATE devices SET push_token = NULL WHERE push_token = ANY($1::text[])', [invalidTokens]);
      }
      return true;
    } catch (err) {
      this.log?.error(err, 'notify failed');
      return false;
    }
  }
}
