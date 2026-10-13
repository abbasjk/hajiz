-- بريد التواصل الذي طلبه صاحب التطبيق؛ لا يغيّر قيمة ضُبطت من لوحة الإدارة
UPDATE settings SET value = '"admin@tawdheef-iq.com"'::jsonb, updated_at = now()
WHERE key = 'contact_email' AND value = '""'::jsonb;
