-- الإشعارات: لمن تظهر (الزبون أو المحل)، ومفتاح يمنع إرسال التذكير نفسه مرتين
ALTER TABLE notifications ADD COLUMN audience text NOT NULL DEFAULT 'customer'
  CHECK (audience IN ('customer', 'shop'));
ALTER TABLE notifications ADD COLUMN params jsonb NOT NULL DEFAULT '{}';
ALTER TABLE notifications ADD COLUMN dedupe_key text;
CREATE UNIQUE INDEX notifications_dedupe_idx ON notifications (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX notifications_unread_idx ON notifications (user_id, audience) WHERE read_at IS NULL;

-- الإشعارات الاختيارية يستطيع المستخدم إيقافها؛ إشعارات الحجز والإلغاء إجبارية
ALTER TABLE users ADD COLUMN notify_reminders boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN notify_morning_summary boolean NOT NULL DEFAULT true;

-- هل سمح المستخدم بالإشعارات على هذا الجهاز؛ لتذكير صاحب المحل إن عطّلها
ALTER TABLE devices ADD COLUMN push_enabled boolean;

INSERT INTO settings (key, value) VALUES
  ('morning_summary_hour', '8'),
  ('final_deadline_reminder_minutes', '5')
ON CONFLICT (key) DO NOTHING;
