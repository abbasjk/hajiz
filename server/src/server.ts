import { buildApp } from './app.js';
import { createPool } from './db/pool.js';
import { loadEnv } from './env.js';

const env = loadEnv();
const pool = createPool(env.DATABASE_URL);
const app = await buildApp({ pool, logLevel: env.LOG_LEVEL });

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
}

await app.listen({ port: env.PORT, host: env.HOST });
