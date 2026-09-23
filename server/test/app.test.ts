import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { migrate } from '../src/db/migrate.js';
import type { Pool } from '../src/db/pool.js';
import { appHeaders, freshDatabase } from './helpers.js';

let pool: Pool;
let app: FastifyInstance;

beforeAll(async () => {
  pool = await freshDatabase();
  app = await buildApp({ pool, logLevel: 'silent' });
});

afterAll(async () => {
  await app.close();
  await pool.end();
});

describe('migrations', () => {
  it('are not re-applied on a second run', async () => {
    expect(await migrate(pool)).toEqual([]);
  });
});

describe('GET /health', () => {
  it('reports the database as reachable', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok' });
  });
});

describe('version check', () => {
  it('rejects requests without app version headers', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/config' });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ error: { code: 'app_version_required' } });
  });

  it('forces an update when the version is below the minimum', async () => {
    await pool.query(`UPDATE app_versions SET min_version = '0.2.0' WHERE platform = 'ios'`);
    const fresh = await buildApp({ pool, logLevel: 'silent' });
    const res = await fresh.inject({
      method: 'GET',
      url: '/v1/config',
      headers: { 'x-app-platform': 'ios', 'x-app-version': '0.1.9' },
    });
    await fresh.close();
    expect(res.statusCode).toBe(426);
    expect(res.json()).toEqual({ error: { code: 'update_required', minVersion: '0.2.0' } });
  });
});

describe('GET /v1/config', () => {
  it('returns server-driven settings and lists', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/config', headers: appHeaders });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(Date.parse(body.serverTime)).not.toBeNaN();
    expect(body.districts).toHaveLength(7);
    expect(body.districts[0]).toEqual({ id: expect.any(Number), name: 'البصرة' });
    expect(body.settings.min_lead_minutes).toBe(180);
    expect(body.settings.shop_deadline_modes.normal).toEqual({
      same_day_under_6h: 15, same_day: 30, tomorrow: 60, within_week: 240, week_or_more: 720,
    });
  });
});

describe('unknown routes', () => {
  it('return a translatable error code', async () => {
    const res = await app.inject({ method: 'GET', url: '/nope' });
    expect(res.statusCode).toBe(404);
    expect(res.json()).toEqual({ error: { code: 'not_found' } });
  });
});
