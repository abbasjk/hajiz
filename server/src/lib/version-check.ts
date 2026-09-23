import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Pool } from '../db/pool.js';
import { AppError } from './errors.js';
import { compareVersions, isValidVersion } from './version.js';

const PLATFORMS = new Set(['android', 'ios', 'web']);
const CACHE_MS = 60_000;

/**
 * إجبار التحديث: كل طلب يحمل X-App-Platform و X-App-Version،
 * وإذا كانت النسخة أقدم من أقل إصدار مسموح يُرفض الطلب برمز 426.
 */
export function versionCheck(pool: Pool) {
  let cache: { at: number; min: Map<string, string> } | undefined;

  async function minVersions(): Promise<Map<string, string>> {
    if (cache && Date.now() - cache.at < CACHE_MS) return cache.min;
    const { rows } = await pool.query<{ platform: string; min_version: string }>(
      'SELECT platform, min_version FROM app_versions',
    );
    cache = { at: Date.now(), min: new Map(rows.map((r) => [r.platform, r.min_version])) };
    return cache.min;
  }

  return async (request: FastifyRequest, _reply: FastifyReply) => {
    const platform = request.headers['x-app-platform'];
    const version = request.headers['x-app-version'];
    if (typeof platform !== 'string' || !PLATFORMS.has(platform)
      || typeof version !== 'string' || !isValidVersion(version)) {
      throw new AppError(400, 'app_version_required');
    }
    const min = (await minVersions()).get(platform);
    if (min && compareVersions(version, min) < 0) {
      throw new AppError(426, 'update_required', { minVersion: min });
    }
  };
}
