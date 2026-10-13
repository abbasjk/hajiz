import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),
  // true: يُنشئ محلاً تجريبياً مرة واحدة لتجربة تطبيق الزبون
  SEED_DEMO: z.enum(['true', 'false']).default('false').transform((v) => v === 'true'),
  // مفتاح حساب الخدمة من Firebase (JSON أو base64)؛ يُوضع في Railway فقط
  FIREBASE_SERVICE_ACCOUNT: z.string().min(1).optional(),
  // مفتاح خدمة رموز التحقق (رمز إلى الواتساب ثم الرسالة القصيرة)؛ بدونه لا يُطلب رمز عند التسجيل
  OTPIQ_API_KEY: z.string().min(1).optional(),
  OTPIQ_PROVIDER: z.enum(['auto', 'whatsapp-sms', 'sms', 'whatsapp', 'telegram-sms', 'whatsapp-telegram-sms']).default('whatsapp-sms'),
  // أول حساب للوحة الإدارة: يُنشأ عند التشغيل إذا لم يوجد أي حساب، ثم يُحذف المتغير من المنصة
  // يُتحقق منهما في bootstrapAdmin: قيمة خاطئة هنا لا توقف الخادم
  ADMIN_INITIAL_USERNAME: z.string().optional(),
  ADMIN_INITIAL_PASSWORD: z.string().optional(),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export type Env = z.infer<typeof schema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = schema.safeParse(source);
  if (!parsed.success) {
    const fields = parsed.error.issues.map((i) => i.path.join('.')).join(', ');
    throw new Error(`Invalid environment variables: ${fields}`);
  }
  return parsed.data;
}
