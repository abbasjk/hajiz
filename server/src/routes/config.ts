import type { FastifyInstance } from 'fastify';

export async function configRoutes(app: FastifyInstance) {
  /**
   * الإعدادات من الخادم: المهل، حد الإلغاء، أنواع الأعمال، الأقضية والمناطق.
   * يجلبها التطبيق عند التشغيل فلا يحتاج تغييرها تحديثاً.
   * serverTime يسمح للتطبيق بحساب العداد بتوقيت الخادم لا ساعة الهاتف.
   */
  app.get('/config', async () => {
    const [settings, businessTypes, districts, areas, versions, categories] = await Promise.all([
      app.pool.query<{ key: string; value: unknown }>('SELECT key, value FROM settings ORDER BY key'),
      app.pool.query('SELECT id, name, icon FROM business_types WHERE active ORDER BY sort_order, id'),
      app.pool.query('SELECT id, name FROM districts WHERE active ORDER BY sort_order, id'),
      app.pool.query(
        `SELECT id, district_id AS "districtId", name FROM areas
         WHERE active ORDER BY district_id, sort_order, name`,
      ),
      app.pool.query(
        `SELECT platform, min_version AS "minVersion", latest_version AS "latestVersion"
         FROM app_versions ORDER BY platform`,
      ),
      app.pool.query(
        `SELECT id, name, icon, CASE WHEN photo IS NOT NULL
                THEN '/category-photos/' || id || '?v=' || extract(epoch FROM photo_updated_at)::bigint END AS photo
         FROM service_categories WHERE active ORDER BY sort_order, id`,
      ),
    ]);
    return {
      serverTime: new Date().toISOString(),
      settings: Object.fromEntries(settings.rows.map((r) => [r.key, r.value])),
      businessTypes: businessTypes.rows,
      serviceCategories: categories.rows,
      districts: districts.rows,
      areas: areas.rows,
      appVersions: versions.rows,
      // التطبيق يطلب رمز تحقق قبل التسجيل حين تكون خدمة الرموز مُعدّة
      phoneVerification: app.codeSender !== null,
    };
  });
}
