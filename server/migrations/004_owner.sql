-- صور المحل تُحفظ في قاعدة البيانات نفسها (مصغّرة من التطبيق) حتى لا نحتاج خدمة تخزين منفصلة الآن
ALTER TABLE shop_photos ADD COLUMN data bytea;
ALTER TABLE shop_photos ADD COLUMN content_type text;
ALTER TABLE shop_photos ALTER COLUMN url DROP NOT NULL;
ALTER TABLE shop_photos ADD CONSTRAINT shop_photos_source CHECK (url IS NOT NULL OR data IS NOT NULL);

-- ملاحظة الإدارة عند رفض طلب فتح المحل، تظهر لصاحبه ليعدّل ويعيد الإرسال
ALTER TABLE shops ADD COLUMN review_note text;

-- حد أقصى لصور المحل
INSERT INTO settings (key, value) VALUES ('max_shop_photos', '8') ON CONFLICT (key) DO NOTHING;
