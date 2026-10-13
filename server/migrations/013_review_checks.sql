-- ما تحققت منه الإدارة قبل الموافقة على المحل: الاتصال برقم المحل، ومطابقة الموقع، وحقيقية الصور
ALTER TABLE shops ADD COLUMN review_checks jsonb;
