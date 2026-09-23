import type pg from 'pg';

/** Pool أو اتصال داخل معاملة؛ دوال المحرك تعمل مع الاثنين. */
export type Queryable = Pick<pg.Pool | pg.PoolClient, 'query'>;
