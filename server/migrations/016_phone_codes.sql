-- رموز التحقق من رقم الهاتف: تُحفظ بصمتها فقط، وتنتهي خلال عشر دقائق
CREATE TABLE phone_codes (
  id          bigserial PRIMARY KEY,
  phone       text        NOT NULL,
  code_hash   text        NOT NULL,
  ip          text,
  attempts    int         NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz
);
CREATE INDEX phone_codes_phone_idx ON phone_codes (phone, id DESC);
CREATE INDEX phone_codes_created_idx ON phone_codes (created_at);

-- الهاتف الذي أثبت الرقم برمز يصبح موثوقاً تلقائياً
ALTER TABLE devices ADD COLUMN phone_verified_at timestamptz;
