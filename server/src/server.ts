import { buildApp } from './app.js';
import { migrate } from './db/migrate.js';
import { createPool } from './db/pool.js';
import { loadEnv } from './env.js';

const env = loadEnv();
const pool = createPool(env.DATABASE_URL);
// الترحيلات تُطبَّق عند كل تشغيل؛ القفل داخل migrate يمنع تشغيلها من نسختين معاً
const applied = await migrate(pool);
const app = await buildApp({ pool, logLevel: env.LOG_LEVEL });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
}

app.log.info(applied.length ? `Applied migrations: ${applied.join(', ')}` : 'Database is up to date');
await app.listen({ port: env.PORT, host: env.HOST });
