-- صورة حقيقية لكل نوع خدمة تظهر في مربعات الرئيسية بدل الأيقونة؛ ترفعها الإدارة
ALTER TABLE service_categories
  ADD COLUMN photo bytea,
  ADD COLUMN photo_type text,
  ADD COLUMN photo_updated_at timestamptz;
