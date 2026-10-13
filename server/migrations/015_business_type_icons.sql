-- أيقونة لكل نوع عمل تظهر في رئيسية الزبون؛ تختارها الإدارة من مجموعة ثابتة يعرفها التطبيق
ALTER TABLE business_types ADD COLUMN icon text NOT NULL DEFAULT 'store'
  CHECK (icon IN ('store', 'scissors', 'sparkles', 'stethoscope', 'tooth', 'car', 'wrench', 'spa', 'face', 'pets', 'fitness', 'camera'));

UPDATE business_types SET icon = 'scissors' WHERE name = 'حلاقة رجالية';
UPDATE business_types SET icon = 'sparkles' WHERE name = 'صالون نسائي';
UPDATE business_types SET icon = 'stethoscope' WHERE name = 'عيادة';
UPDATE business_types SET icon = 'tooth' WHERE name = 'عيادة أسنان';
UPDATE business_types SET icon = 'car' WHERE name = 'ورشة سيارات';
