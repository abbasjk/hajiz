-- "محل مميز" في رئيسية الزبون: تختاره الإدارة
ALTER TABLE shops ADD COLUMN featured_at timestamptz;
CREATE INDEX shops_featured_idx ON shops (featured_at DESC) WHERE featured_at IS NOT NULL;
