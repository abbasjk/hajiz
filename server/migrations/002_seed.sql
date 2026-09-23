-- القيم الابتدائية. كلها قابلة للتعديل لاحقاً من لوحة الإدارة.

-- أقضية محافظة البصرة
INSERT INTO districts (name, sort_order) VALUES
  ('البصرة', 1),
  ('الزبير', 2),
  ('أبو الخصيب', 3),
  ('شط العرب', 4),
  ('القرنة', 5),
  ('المدينة', 6),
  ('الفاو', 7);

-- أنواع الأعمال الأولية
INSERT INTO business_types (name, sort_order) VALUES
  ('حلاقة رجالية', 1),
  ('صالون نسائي', 2),
  ('عيادة', 3),
  ('عيادة أسنان', 4),
  ('ورشة سيارات', 5);

-- مهلة الرد حسب قرب الموعد، بالدقائق.
-- same_day_under_6h: بعد 3 إلى 6 ساعات
-- same_day: بعد 6 ساعات، في اليوم نفسه
-- tomorrow: غداً
-- within_week: بعد عدة أيام
-- week_or_more: بعد أسبوع أو أكثر
INSERT INTO settings (key, value) VALUES
  ('shop_deadline_modes', '{
    "fast":     {"same_day_under_6h": 10, "same_day": 15, "tomorrow": 30,  "within_week": 120, "week_or_more": 360},
    "normal":   {"same_day_under_6h": 15, "same_day": 30, "tomorrow": 60,  "within_week": 240, "week_or_more": 720},
    "flexible": {"same_day_under_6h": 30, "same_day": 60, "tomorrow": 180, "within_week": 720, "week_or_more": 1440}
  }'),
  -- مهلة الزبون ثابتة من طرفنا للعدالة بين كل المحلات
  ('customer_deadline', '{"same_day_under_6h": 15, "same_day": 30, "tomorrow": 60, "within_week": 240, "week_or_more": 720}'),
  ('min_lead_minutes', '180'),
  ('slot_step_minutes', '15'),
  ('auto_complete_after_minutes', '180'),
  ('free_cancel_hours_options', '[1, 2, 6, 24]'),
  ('free_cancel_hours_default', '2'),
  ('max_pending_requests_per_customer', '2'),
  ('no_show_penalty', '{"count": 3, "window_days": 90}'),
  ('reminder_before_appointment_minutes', '60'),
  ('display_timezone', '"Asia/Baghdad"');

INSERT INTO app_versions (platform, min_version, latest_version) VALUES
  ('android', '0.1.0', '0.1.0'),
  ('ios', '0.1.0', '0.1.0'),
  ('web', '0.1.0', '0.1.0');
