-- طلبات حذف الحساب من صفحة الموقع (لمن لا يستطيع فتح التطبيق).
-- لا رمز تحقق، فالإدارة تتأكد بالاتصال بالرقم قبل التنفيذ.
CREATE TABLE deletion_requests (
  id               bigserial PRIMARY KEY,
  phone            text NOT NULL,
  name             text,
  note             text,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'rejected')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  resolved_at      timestamptz,
  resolved_by      integer REFERENCES admins(id) ON DELETE SET NULL,
  resolution_note  text
);

-- طلب واحد قائم لكل رقم؛ تكرار الإرسال لا يُنشئ طلبات جديدة
CREATE UNIQUE INDEX deletion_requests_pending_phone ON deletion_requests (phone) WHERE status = 'pending';

