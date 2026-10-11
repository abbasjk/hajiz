-- لوحة الإدارة: جلسات الدخول، ومن راجع المحل ومتى، وسجل إجراءات الإدارة

-- جلسة دخول للوحة: الخادم يحفظ بصمة المفتاح فقط
CREATE TABLE admin_sessions (
  token_hash  text PRIMARY KEY,
  admin_id    integer NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);

CREATE INDEX admin_sessions_admin_idx ON admin_sessions (admin_id);

ALTER TABLE shops ADD COLUMN reviewed_at timestamptz;
ALTER TABLE shops ADD COLUMN reviewed_by integer REFERENCES admins(id) ON DELETE SET NULL;
-- وقت إرسال الطلب للمراجعة: الأقدم يُراجع أولاً
ALTER TABLE shops ADD COLUMN submitted_at timestamptz;

ALTER TABLE area_requests ADD COLUMN resolved_at timestamptz;

-- كل ما تفعله الإدارة يُسجّل: من، ماذا، على أي عنصر، ومتى
CREATE TABLE admin_actions (
  id           bigserial PRIMARY KEY,
  admin_id     integer REFERENCES admins(id) ON DELETE SET NULL,
  action       text NOT NULL,
  target_type  text NOT NULL,
  target_id    bigint,
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX admin_actions_target_idx ON admin_actions (target_type, target_id, created_at DESC);
