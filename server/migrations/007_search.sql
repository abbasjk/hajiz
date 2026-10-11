-- البحث: يشمل أسماء الخدمات، مع توحيد الحروف العربية حتى لا يضيع الزبون بسبب طريقة الكتابة

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- توحيد النص للبحث:
--   أ إ آ ٱ ← ا ، ى ← ي ، ة ← ه ، ؤ ← و ، ئ ← ي
--   حروف لوحة المفاتيح الكردية والفارسية: ی ← ي ، ک ← ك ، ە ← ه
--   حذف التشكيل والتطويل
CREATE FUNCTION ar_norm(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(
           translate(lower(coalesce(p, '')), 'أإآٱىةؤئیکە', 'اااايهوييكه'),
           '[ً-ْـ]', '', 'g');
$$;

-- فهارس تسرّع البحث بجزء من الاسم ("زيت" تجد "تبديل زيت")
CREATE INDEX shops_name_search_idx ON shops USING gin (ar_norm(name) gin_trgm_ops);
CREATE INDEX services_name_search_idx ON services USING gin (ar_norm(name) gin_trgm_ops);
