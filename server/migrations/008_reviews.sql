-- التقييمات: مرتبطة بالمحل مباشرة لتسريع حساب المتوسط، والإدارة تستطيع إخفاء المسيء منها

ALTER TABLE reviews ADD COLUMN shop_id bigint REFERENCES shops(id) ON DELETE CASCADE;
UPDATE reviews r SET shop_id = b.shop_id FROM bookings b WHERE b.id = r.booking_id;
ALTER TABLE reviews ALTER COLUMN shop_id SET NOT NULL;

ALTER TABLE reviews ADD COLUMN hidden_at timestamptz;
ALTER TABLE reviews ADD COLUMN hidden_by integer REFERENCES admins(id) ON DELETE SET NULL;

CREATE INDEX reviews_shop_idx ON reviews (shop_id, created_at DESC) WHERE hidden_at IS NULL;

-- التقييم متاح لهذه المدة بعد انتهاء الموعد المكتمل
INSERT INTO settings (key, value) VALUES ('review_window_days', '14') ON CONFLICT (key) DO NOTHING;
