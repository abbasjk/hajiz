-- المخطط الأول لقاعدة بيانات تطبيق الحجز.
-- كل الأوقات تُحفظ بالتوقيت العالمي (timestamptz) وتُعرض بتوقيت بغداد.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ============================================================
-- الإدارة: القوائم الجاهزة
-- ============================================================

CREATE TABLE business_types (
  id          serial PRIMARY KEY,
  name        text NOT NULL UNIQUE,
  sort_order  integer NOT NULL DEFAULT 0,
  active      boolean NOT NULL DEFAULT true
);

-- الأقضية
CREATE TABLE districts (
  id          serial PRIMARY KEY,
  name        text NOT NULL UNIQUE,
  sort_order  integer NOT NULL DEFAULT 0,
  active      boolean NOT NULL DEFAULT true
);

-- المناطق، تتغير حسب القضاء
CREATE TABLE areas (
  id           serial PRIMARY KEY,
  district_id  integer NOT NULL REFERENCES districts(id),
  name         text NOT NULL,
  sort_order   integer NOT NULL DEFAULT 0,
  active       boolean NOT NULL DEFAULT true,
  UNIQUE (district_id, name)
);

-- ============================================================
-- المستخدمون
-- لا يوجد حقل "نوع مستخدم": الشخص نفسه قد يكون زبوناً وصاحب محل.
-- ============================================================

CREATE TABLE users (
  id          bigserial PRIMARY KEY,
  phone       text NOT NULL UNIQUE,
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz,
  banned_at   timestamptz
);

CREATE TABLE devices (
  id                    bigserial PRIMARY KEY,
  user_id               bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_identifier     text NOT NULL,
  -- مفتاح الدخول المرتبط بالجهاز، يُحفظ مجزّأً (hash) فقط
  token_hash            text NOT NULL UNIQUE,
  push_token            text,
  first_seen_at         timestamptz NOT NULL DEFAULT now(),
  last_seen_at          timestamptz NOT NULL DEFAULT now(),
  -- صاحب المحل ضغط "تم التأكد بالاتصال"
  verified_by_call_at   timestamptz,
  UNIQUE (user_id, device_identifier)
);

-- طلبات إضافة منطقة من أصحاب المحلات
CREATE TABLE area_requests (
  id           bigserial PRIMARY KEY,
  district_id  integer NOT NULL REFERENCES districts(id),
  name         text NOT NULL,
  requested_by bigint REFERENCES users(id) ON DELETE SET NULL,
  status       text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- المحل
-- ============================================================

CREATE TYPE shop_status AS ENUM ('draft', 'under_review', 'approved', 'rejected', 'suspended');
CREATE TYPE deadline_mode AS ENUM ('fast', 'normal', 'flexible');

CREATE TABLE shops (
  id                        bigserial PRIMARY KEY,
  -- محل واحد لكل صاحب عمل
  owner_id                  bigint NOT NULL UNIQUE REFERENCES users(id),
  name                      text NOT NULL,
  business_type_id          integer REFERENCES business_types(id),
  description               text,
  phone                     text,
  district_id               integer REFERENCES districts(id),
  area_id                   integer REFERENCES areas(id),
  street                    text,
  landmark                  text,
  latitude                  double precision,
  longitude                 double precision,
  status                    shop_status NOT NULL DEFAULT 'draft',
  deadline_mode             deadline_mode NOT NULL DEFAULT 'normal',
  free_cancel_hours         integer NOT NULL DEFAULT 2
                            CHECK (free_cancel_hours IN (1, 2, 6, 24)),
  -- أقل وقت قبل الحجز، صاحب المحل يستطيع زيادته فقط (الحد الأدنى من الإعدادات العامة)
  min_lead_minutes          integer NOT NULL DEFAULT 180 CHECK (min_lead_minutes >= 0),
  instant_booking           boolean NOT NULL DEFAULT false,
  buffer_minutes            integer NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
  plan                      text NOT NULL DEFAULT 'free',
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CHECK ((latitude IS NULL) = (longitude IS NULL)),
  -- عند الإرسال للمراجعة يجب أن تكتمل الحقول الإجبارية
  CHECK (status = 'draft' OR (
    business_type_id IS NOT NULL AND district_id IS NOT NULL
    AND area_id IS NOT NULL AND latitude IS NOT NULL
  ))
);

CREATE INDEX shops_status_idx ON shops (status);
CREATE INDEX shops_area_idx ON shops (area_id);

CREATE TABLE shop_photos (
  id          bigserial PRIMARY KEY,
  shop_id     bigint NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  url         text NOT NULL,
  sort_order  integer NOT NULL DEFAULT 0
);

CREATE TYPE price_type AS ENUM ('fixed', 'starts_from', 'after_inspection');

CREATE TABLE services (
  id                bigserial PRIMARY KEY,
  shop_id           bigint NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name              text NOT NULL,
  duration_minutes  integer NOT NULL CHECK (duration_minutes > 0),
  price_type        price_type NOT NULL DEFAULT 'fixed',
  -- بالدينار العراقي، فارغ عند "يُحدد بعد المعاينة"
  price             integer CHECK (price IS NULL OR price >= 0),
  active            boolean NOT NULL DEFAULT true,
  CHECK ((price_type = 'after_inspection') = (price IS NULL))
);

-- ============================================================
-- الجدول
-- المواعيد مربوطة بجدول تابع للمحل لا بالمحل مباشرة،
-- حتى يمكن إضافة عدة عاملين لاحقاً.
-- ============================================================

CREATE TABLE schedules (
  id       bigserial PRIMARY KEY,
  shop_id  bigint NOT NULL REFERENCES shops(id) ON DELETE CASCADE
);

-- فترات العمل الأسبوعية. اليوم قد يحوي عدة فترات، والفراغ بينها استراحة.
-- day_of_week: 0 = الأحد ... 6 = السبت.
-- إذا كان end_time <= start_time فالفترة تنتهي في اليوم التالي (العمل بعد منتصف الليل).
CREATE TABLE weekly_periods (
  id           bigserial PRIMARY KEY,
  schedule_id  bigint NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  day_of_week  smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time   time NOT NULL,
  end_time     time NOT NULL,
  CHECK (start_time <> end_time)
);

CREATE INDEX weekly_periods_schedule_idx ON weekly_periods (schedule_id, day_of_week);

-- جدول مؤقت لفترة محددة (رمضان، الأعياد)، يعود بعدها الجدول العادي تلقائياً
CREATE TABLE temporary_schedules (
  id           bigserial PRIMARY KEY,
  schedule_id  bigint NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  name         text NOT NULL,
  from_date    date NOT NULL,
  to_date      date NOT NULL,
  CHECK (to_date >= from_date)
);

CREATE TABLE temporary_schedule_periods (
  id                      bigserial PRIMARY KEY,
  temporary_schedule_id   bigint NOT NULL REFERENCES temporary_schedules(id) ON DELETE CASCADE,
  day_of_week             smallint NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time              time NOT NULL,
  end_time                time NOT NULL,
  CHECK (start_time <> end_time)
);

CREATE TABLE closures (
  id           bigserial PRIMARY KEY,
  schedule_id  bigint NOT NULL REFERENCES schedules(id) ON DELETE CASCADE,
  starts_at    timestamptz NOT NULL,
  ends_at      timestamptz NOT NULL,
  reason       text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

CREATE INDEX closures_schedule_idx ON closures (schedule_id, starts_at);

-- ============================================================
-- الحجوزات
-- ============================================================

CREATE TYPE booking_status AS ENUM (
  'pending_shop',            -- بانتظار المحل
  'pending_customer',        -- بانتظار رد الزبون على التعديل
  'confirmed',               -- مؤكد
  'rejected',                -- مرفوض مع سبب
  'cancelled_by_customer',   -- ملغى من الزبون
  'cancelled_by_shop',       -- ملغى من المحل
  'expired',                 -- منتهي المهلة
  'completed',               -- مكتمل
  'no_show'                  -- لم يحضر
);

CREATE TABLE bookings (
  id                   bigserial PRIMARY KEY,
  customer_id          bigint NOT NULL REFERENCES users(id),
  shop_id              bigint NOT NULL REFERENCES shops(id),
  schedule_id          bigint NOT NULL REFERENCES schedules(id),
  -- الجهاز الذي أُرسل منه الطلب (لتنبيه "رقم مستخدم من جهاز جديد")
  device_id            bigint REFERENCES devices(id) ON DELETE SET NULL,
  starts_at            timestamptz NOT NULL,
  ends_at              timestamptz NOT NULL,
  status               booking_status NOT NULL DEFAULT 'pending_shop',
  customer_note        text,
  is_instant           boolean NOT NULL DEFAULT false,
  -- انتهاء مهلة الرد الحالية (لصاحب المحل أو للزبون حسب الحالة)
  response_deadline    timestamptz,
  -- رسالة صاحب المحل القصيرة مع الأوقات المقترحة
  modification_message text,
  -- سبب الإلغاء أو الرفض من قائمة قصيرة
  cancel_reason        text,
  cancelled_by         text CHECK (cancelled_by IS NULL OR cancelled_by IN ('customer', 'shop', 'system')),
  cancelled_late       boolean,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  -- المهلة لا تتجاوز وقت الموعد نفسه
  CHECK (response_deadline IS NULL OR response_deadline <= starts_at),
  -- قاعدة البيانات نفسها تمنع تداخل حجزين نشطين في الجدول نفسه.
  -- الحجز المعلق يشغل الوقت، وهو القفل المؤقت.
  EXCLUDE USING gist (
    schedule_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (status IN ('pending_shop', 'pending_customer', 'confirmed'))
);

CREATE INDEX bookings_customer_idx ON bookings (customer_id, starts_at DESC);
CREATE INDEX bookings_shop_idx ON bookings (shop_id, starts_at);
-- للمهمة التلقائية التي تلغي الطلبات منتهية المهلة كل دقيقة
CREATE INDEX bookings_deadline_idx ON bookings (response_deadline)
  WHERE status IN ('pending_shop', 'pending_customer');

-- السعر والمدة يُحفظان داخل الحجز، فلا تتغير الحجوزات القديمة عند تغيير الأسعار
CREATE TABLE booking_services (
  id                bigserial PRIMARY KEY,
  booking_id        bigint NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  service_id        bigint REFERENCES services(id) ON DELETE SET NULL,
  service_name      text NOT NULL,
  duration_minutes  integer NOT NULL CHECK (duration_minutes > 0),
  price_type        price_type NOT NULL,
  price             integer
);

-- الأوقات المقترحة لا تُقفل: من يسبق يأخذ
CREATE TABLE proposed_times (
  id          bigserial PRIMARY KEY,
  booking_id  bigint NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  CHECK (ends_at > starts_at)
);

CREATE TABLE booking_status_history (
  id           bigserial PRIMARY KEY,
  booking_id   bigint NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  from_status  booking_status,
  to_status    booking_status NOT NULL,
  actor        text NOT NULL CHECK (actor IN ('customer', 'shop', 'system', 'admin')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX booking_status_history_booking_idx ON booking_status_history (booking_id);

-- ============================================================
-- الالتزام والتقييم
-- أحداث الالتزام مربوطة برقم الهاتف لا بالمستخدم،
-- فتبقى بعد حذف الحساب ولا يعود الزبون بسجل نظيف.
-- ============================================================

CREATE TYPE commitment_event_type AS ENUM ('late_cancel', 'no_show');

CREATE TABLE commitment_events (
  id           bigserial PRIMARY KEY,
  phone        text NOT NULL,
  type         commitment_event_type NOT NULL,
  shop_id      bigint REFERENCES shops(id) ON DELETE SET NULL,
  booking_id   bigint REFERENCES bookings(id) ON DELETE SET NULL,
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX commitment_events_phone_idx ON commitment_events (phone, occurred_at DESC);

CREATE TABLE appeals (
  id           bigserial PRIMARY KEY,
  event_id     bigint NOT NULL REFERENCES commitment_events(id) ON DELETE CASCADE,
  text         text NOT NULL,
  status       text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'accepted', 'rejected')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz
);

-- التقييمات فقط لمن أكمل حجزاً فعلياً (يُتحقق من حالة الحجز في الخادم)
CREATE TABLE reviews (
  id          bigserial PRIMARY KEY,
  booking_id  bigint NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  stars       smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- الإدارة
-- ============================================================

-- حسابات لوحة الإدارة منفصلة عن المستخدمين
CREATE TABLE admins (
  id             serial PRIMARY KEY,
  username       text NOT NULL UNIQUE,
  password_hash  text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  disabled_at    timestamptz
);

-- المهل وكل القيم المتغيرة، تُجلب من الخادم فلا يحتاج تغييرها تحديثاً للتطبيق
CREATE TABLE settings (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app_versions (
  platform             text PRIMARY KEY CHECK (platform IN ('android', 'ios', 'web')),
  min_version          text NOT NULL,
  latest_version       text NOT NULL,
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        text NOT NULL,
  booking_id  bigint REFERENCES bookings(id) ON DELETE CASCADE,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

-- منع الإرسال المكرر: كل طلب يغيّر شيئاً يحمل مفتاحاً فريداً من التطبيق
CREATE TABLE idempotency_keys (
  key            text NOT NULL,
  user_id        bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  response_code  integer NOT NULL,
  response_body  jsonb NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, key)
);
