-- لكل جنس خدماته فقط: الأنواع المشتركة تصير نسختين، رجالية ونسائية،
-- وتُنقل خدمات الصالونات النسائية إلى النسخة النسائية. حلاقة الأطفال للرجال فقط.
ALTER TABLE service_categories DROP CONSTRAINT IF EXISTS service_categories_name_key;
ALTER TABLE service_categories ADD CONSTRAINT service_categories_name_audience_key UNIQUE (name, audience);

INSERT INTO service_categories (name, icon, sort_order, audience, active)
SELECT name, icon, sort_order, 'women', active FROM service_categories
WHERE audience = 'all' AND icon <> 'kids'
ON CONFLICT (name, audience) DO NOTHING;

UPDATE services sv SET category_id = w.id
FROM service_categories o, service_categories w, shops s, business_types bt
WHERE sv.category_id = o.id AND o.audience = 'all'
  AND w.audience = 'women' AND w.name = o.name
  AND s.id = sv.shop_id AND bt.id = s.business_type_id AND bt.audience = 'women';

UPDATE service_categories SET audience = 'men' WHERE audience = 'all';

-- ترتيب النسائية: قص الشعر أولاً ثم الصبغ والتسريح، ثم التجميل
UPDATE service_categories SET sort_order = CASE icon
  WHEN 'womencut' THEN 101 WHEN 'dye' THEN 102 WHEN 'styling' THEN 103 WHEN 'treatment' THEN 104
  WHEN 'skin' THEN 105 WHEN 'threading' THEN 106 WHEN 'makeup' THEN 107 WHEN 'nails' THEN 108
  WHEN 'bride' THEN 109 WHEN 'lashes' THEN 110 ELSE sort_order END
WHERE audience = 'women';
