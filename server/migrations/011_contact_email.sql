-- بريد التواصل الذي يظهر في صفحة سياسة الخصوصية؛ يُضبط من لوحة الإدارة
INSERT INTO settings (key, value) VALUES ('contact_email', '""') ON CONFLICT (key) DO NOTHING;
