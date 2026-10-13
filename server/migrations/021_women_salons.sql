-- التطبيق صار «صالون»: صالونات رجالية ونسائية، ولكل نوع خدمة جمهوره
ALTER TABLE business_types ADD COLUMN audience text NOT NULL DEFAULT 'men' CHECK (audience IN ('men', 'women'));
INSERT INTO business_types (name, icon, sort_order, audience) VALUES ('صالون نسائي', 'sparkles', 2, 'women')
ON CONFLICT (name) DO UPDATE SET active = true, audience = 'women';

ALTER TABLE service_categories ADD COLUMN audience text NOT NULL DEFAULT 'all' CHECK (audience IN ('men', 'women', 'all'));
UPDATE service_categories SET audience = 'men' WHERE icon IN ('haircut', 'beard', 'groom', 'razor');

ALTER TABLE service_categories DROP CONSTRAINT service_categories_icon_check;
ALTER TABLE service_categories ADD CONSTRAINT service_categories_icon_check CHECK (icon IN (
  'haircut', 'beard', 'dye', 'kids', 'skin', 'groom', 'treatment', 'threading', 'styling', 'razor',
  'womencut', 'makeup', 'nails', 'bride', 'lashes'));

INSERT INTO service_categories (name, icon, sort_order, audience) VALUES
  ('قص الشعر', 'womencut', 11, 'women'),
  ('المكياج', 'makeup', 12, 'women'),
  ('الأظافر', 'nails', 13, 'women'),
  ('تجهيز العروس', 'bride', 14, 'women'),
  ('الرموش والحواجب', 'lashes', 15, 'women')
ON CONFLICT (name) DO NOTHING;
