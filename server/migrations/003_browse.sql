-- مؤشر التزام المحل: يظهر بعد عدد معين من الحجوزات وبصيغة إيجابية فقط
INSERT INTO settings (key, value) VALUES
  ('shop_commitment_badge', '{"min_bookings": 20, "max_shop_cancel_rate": 0.05}')
ON CONFLICT (key) DO NOTHING;

CREATE INDEX IF NOT EXISTS shops_business_type_idx ON shops (business_type_id) WHERE status = 'approved';
CREATE INDEX IF NOT EXISTS bookings_shop_status_idx ON bookings (shop_id, status);
