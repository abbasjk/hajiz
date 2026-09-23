import pg from 'pg';

// أعمدة bigint تعود كنصوص افتراضياً؛ المعرّفات عندنا تبقى ضمن حدود Number.
pg.types.setTypeParser(pg.types.builtins.INT8, (v) => Number(v));

export type Pool = pg.Pool;

export function createPool(connectionString: string): Pool {
  return new pg.Pool({ connectionString, max: 10 });
}
