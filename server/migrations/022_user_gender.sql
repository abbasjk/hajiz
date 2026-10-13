-- الجنس عند التسجيل: يحدد أي صالونات تظهر أولاً (رجالية أو نسائية)
ALTER TABLE users ADD COLUMN gender text CHECK (gender IN ('male', 'female'));
