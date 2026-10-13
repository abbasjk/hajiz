import type { FastifyRequest } from 'fastify';

/**
 * عنوان الزائر: خلف وكيل المنصة يضيف الوكيل عنوان الزائر في آخر الترويسة،
 * فنأخذ الأخير لا الأول (الأول يستطيع الزائر تزويره).
 */
export function clientIp(request: FastifyRequest): string {
  const header = request.headers['x-forwarded-for'];
  const value = Array.isArray(header) ? header.join(',') : header;
  const last = value?.split(',').map((x) => x.trim()).filter(Boolean).pop();
  return last || request.ip;
}
