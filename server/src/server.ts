import { buildApp } from './app.js';
import { startScheduler } from './booking/jobs.js';
import { migrate } from './db/migrate.js';
import { seedDemoShop } from './db/demo.js';
import { createPool } from './db/pool.js';
import { loadEnv } from './env.js';
import { createFcmSender } from './notify/sender.js';

const env = loadEnv();
const pool = createPool(env.DATABASE_URL);
// الترحيلات تُطبَّق عند كل تشغيل؛ القفل داخل migrate يمنع تشغيلها من نسختين معاً
const applied = await migrate(pool);
const demoCreated = env.SEED_DEMO ? await seedDemoShop(pool) : false;
// بدون مفتاح Firebase تُحفظ الإشعارات وتظهر داخل التطبيق فقط
const sender = env.FIREBASE_SERVICE_ACCOUNT ? await createFcmSender(env.FIREBASE_SERVICE_ACCOUNT) : undefined;
const app = await buildApp({ pool, logLevel: env.LOG_LEVEL, sender });
const stopJobs = startScheduler(pool, app.log, app.notifier);

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, async () => {
    stopJobs();
    await app.close();
    await pool.end();
    process.exit(0);
  });
}

app.log.info(applied.length ? `Applied migrations: ${applied.join(', ')}` : 'Database is up to date');
if (demoCreated) app.log.info('Demo shop created');
app.log.info(sender ? 'Push notifications: Firebase' : 'Push notifications: not configured (in-app only)');
await app.listen({ port: env.PORT, host: env.HOST });
