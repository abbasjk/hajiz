import type { FastifyBaseLogger } from 'fastify';

export interface PushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
  urgent: boolean;
}

export interface PushSender {
  /** يعيد المفاتيح التي لم تعد صالحة (حُذف التطبيق مثلاً) لتُمسح من قاعدة البيانات */
  send(tokens: string[], message: PushMessage): Promise<{ invalidTokens: string[] }>;
}

/** قبل إعداد Firebase: الإشعار يُحفظ ويظهر داخل التطبيق، ويُسجَّل هنا بدل إرساله */
export class LogSender implements PushSender {
  constructor(private readonly log?: FastifyBaseLogger) {}

  async send(tokens: string[], message: PushMessage) {
    this.log?.info({ tokens: tokens.length, title: message.title }, 'push (not configured)');
    return { invalidTokens: [] };
  }
}

/**
 * Firebase Cloud Messaging. المفتاح من متغير FIREBASE_SERVICE_ACCOUNT في Railway
 * (نص JSON كما يُحمَّل من Firebase، أو نفسه مرمّزاً بـ base64).
 */
export async function createFcmSender(serviceAccount: string, log?: FastifyBaseLogger): Promise<PushSender> {
  const { initializeApp, cert } = await import('firebase-admin/app');
  const { getMessaging } = await import('firebase-admin/messaging');
  const json = serviceAccount.trim().startsWith('{')
    ? serviceAccount
    : Buffer.from(serviceAccount, 'base64').toString('utf8');
  const app = initializeApp({ credential: cert(JSON.parse(json)) }, 'hajiz');
  const messaging = getMessaging(app);
  const INVALID = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

  return {
    async send(tokens, message) {
      if (tokens.length === 0) return { invalidTokens: [] };
      const res = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: message.title, body: message.body },
        data: message.data,
        android: {
          priority: message.urgent ? 'high' : 'normal',
          // قناة "الحجوزات" في التطبيق بأهمية عالية وصوت
          notification: { channelId: 'bookings', sound: 'default' },
        },
        apns: { payload: { aps: { sound: 'default' } } },
      });
      const invalidTokens = res.responses
        .map((r, i) => (!r.success && r.error && INVALID.has(r.error.code) ? tokens[i]! : null))
        .filter((t): t is string => t !== null);
      if (res.failureCount > invalidTokens.length) log?.warn({ failures: res.failureCount }, 'push failures');
      return { invalidTokens };
    },
  };
}
