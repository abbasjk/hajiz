import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { LoginLimiter } from '../admin/auth.js';
import { AppError } from '../lib/errors.js';
import { normalizeIraqiPhone } from '../lib/phone.js';

const PAGE_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../public/delete-account.html');

const requestBody = z.object({
  phone: z.string().max(30),
  name: z.string().trim().max(60).optional(),
  note: z.string().trim().max(500).optional(),
  // حقل مخفي؛ البرامج الآلية تملؤه والإنسان لا يراه
  website: z.string().max(200).optional(),
});

/**
 * صفحة عامة لطلب حذف الحساب دون فتح التطبيق (يطلبها متجر التطبيقات).
 * الرد واحد دائماً سواء وُجد الحساب أم لا، فلا تكشف الصفحة من لديه حساب.
 */
export async function deletePageRoutes(app: FastifyInstance) {
  // خمسة طلبات في الساعة لكل عنوان، ومئة للجميع، حتى لا تُغرق القائمة
  const perIp = new LoginLimiter(5, 60 * 60_000);
  const global = new LoginLimiter(100, 60 * 60_000);

  app.get('/delete-account', async (_request, reply) => {
    const html = await readFile(PAGE_PATH, 'utf8');
    return reply
      .header('content-type', 'text/html; charset=utf-8')
      .header('cache-control', 'no-cache')
      .header('x-frame-options', 'DENY')
      .send(html);
  });

  app.post('/delete-account', async (request) => {
    const r = requestBody.safeParse(request.body);
    if (!r.success) throw new AppError(400, 'invalid_request');
    const body = r.data;
    if (perIp.blocked(request.ip) || global.blocked('all')) throw new AppError(429, 'too_many_attempts');
    perIp.fail(request.ip);
    global.fail('all');
    if (body.website) return { ok: true };
    const phone = normalizeIraqiPhone(body.phone);
    if (!phone) throw new AppError(400, 'invalid_phone');
    await app.pool.query(
      `INSERT INTO deletion_requests (phone, name, note) VALUES ($1, $2, $3)
       ON CONFLICT (phone) WHERE status = 'pending'
       DO UPDATE SET name = coalesce(EXCLUDED.name, deletion_requests.name), note = coalesce(EXCLUDED.note, deletion_requests.note)`,
      [phone, body.name || null, body.note || null],
    );
    return { ok: true };
  });
}
