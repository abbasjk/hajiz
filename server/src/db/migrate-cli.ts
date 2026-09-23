import { loadEnv } from '../env.js';
import { migrate } from './migrate.js';
import { createPool } from './pool.js';

const env = loadEnv();
const pool = createPool(env.DATABASE_URL);
try {
  const applied = await migrate(pool);
  console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Database is up to date');
} finally {
  await pool.end();
}
