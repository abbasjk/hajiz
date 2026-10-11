-- طلب توثيق هاتف جديد من التطبيق (غيّر هاتفه أو أعاد تثبيت التطبيق)؛ الإدارة تتصل بالرقم ثم توثّق
ALTER TABLE devices ADD COLUMN trust_requested_at timestamptz;
ALTER TABLE devices ADD COLUMN trust_request_note text;
CREATE INDEX devices_trust_requested_idx ON devices (trust_requested_at) WHERE trust_requested_at IS NOT NULL;
