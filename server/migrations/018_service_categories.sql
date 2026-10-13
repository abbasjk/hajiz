-- أنواع الخدمات في رئيسية الزبون (حلاقة الشعر، تهذيب اللحية، الصبغ...)؛
-- يختار صاحب المحل نوع كل خدمة، والزبون يصفّي المحلات بالنوع
CREATE TABLE service_categories (
  id          serial PRIMARY KEY,
  name        text    NOT NULL UNIQUE,
  icon        text    NOT NULL CHECK (icon IN ('haircut', 'beard', 'dye', 'kids', 'skin', 'groom', 'treatment', 'threading', 'styling', 'razor')),
  sort_order  int     NOT NULL DEFAULT 0,
  active      boolean NOT NULL DEFAULT true
);

INSERT INTO service_categories (name, icon, sort_order) VALUES
  ('حلاقة الشعر', 'haircut', 1),
  ('تهذيب اللحية', 'beard', 2),
  ('صبغ الشعر', 'dye', 3),
  ('حلاقة الأطفال', 'kids', 4),
  ('تنظيف البشرة', 'skin', 5),
  ('حلاقة العريس', 'groom', 6),
  ('علاج الشعر', 'treatment', 7),
  ('الخيط والشمع', 'threading', 8),
  ('تسريح', 'styling', 9),
  ('الحلاقة بالموس', 'razor', 10);

ALTER TABLE services ADD COLUMN category_id int REFERENCES service_categories (id) ON DELETE SET NULL;
CREATE INDEX services_category_idx ON services (category_id) WHERE active;

-- الخدمات الموجودة: نوع تقريبي من اسمها (الأدق أولاً)، ويستطيع صاحب المحل تغييره
WITH rules (icon, pattern, rank) AS (VALUES
  ('razor', '%موس%', 1), ('groom', '%عريس%', 2), ('kids', '%طفل%', 3), ('kids', '%اطفال%', 3), ('kids', '%أطفال%', 3),
  ('dye', '%صبغ%', 4), ('threading', '%خيط%', 5), ('threading', '%شمع%', 5), ('threading', '%واكس%', 5),
  ('skin', '%بشر%', 6), ('skin', '%ماسك%', 6), ('skin', '%تنظيف%', 6),
  ('treatment', '%علاج%', 7), ('treatment', '%حمام%', 7), ('treatment', '%زيت%', 7), ('treatment', '%كيراتين%', 7), ('treatment', '%بروتين%', 7),
  ('styling', '%تسريح%', 8), ('styling', '%سشوار%', 8), ('styling', '%استشوار%', 8),
  ('beard', '%لحي%', 9), ('beard', '%ذقن%', 9),
  ('haircut', '%حلاق%', 10), ('haircut', '%قص%', 10), ('haircut', '%شعر%', 10)
), best AS (
  SELECT DISTINCT ON (s.id) s.id, c.id AS category_id
  FROM services s JOIN rules r ON s.name LIKE r.pattern JOIN service_categories c ON c.icon = r.icon
  ORDER BY s.id, r.rank
)
UPDATE services s SET category_id = best.category_id FROM best WHERE best.id = s.id;
