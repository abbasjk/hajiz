-- التطبيق صار للحلاقة وحدها: كل المحلات حلاقة رجالية، وتُحذف أنواع العمل الأخرى
UPDATE shops SET business_type_id = (SELECT id FROM business_types WHERE name = 'حلاقة رجالية')
WHERE business_type_id IS DISTINCT FROM (SELECT id FROM business_types WHERE name = 'حلاقة رجالية');
DELETE FROM business_types WHERE name <> 'حلاقة رجالية';
