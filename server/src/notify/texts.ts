/**
 * نصوص الإشعارات. ملف ترجمة مستقل للخادم (الإشعار يُعرض والتطبيق مغلق فيكتبه الخادم)؛
 * الكردية تُضاف بكتالوج بالمفاتيح نفسها مع حقل لغة للمستخدم.
 */
import { BAGHDAD_OFFSET_MINUTES } from '../booking/time.js';

export type NotificationType =
  // لصاحب المحل
  | 'new_request'
  | 'new_instant_booking'
  | 'customer_chose'
  | 'customer_declined'
  | 'customer_cancelled'
  | 'deadline_half'
  | 'deadline_final'
  | 'morning_summary'
  // للزبون
  | 'accepted'
  | 'rejected'
  | 'proposal'
  | 'proposal_half'
  | 'proposal_final'
  | 'expired_shop'
  | 'expired_customer'
  | 'shop_cancelled'
  | 'closure_proposal'
  | 'appointment_reminder';

export const AUDIENCE: Record<NotificationType, 'customer' | 'shop'> = {
  new_request: 'shop',
  new_instant_booking: 'shop',
  customer_chose: 'shop',
  customer_declined: 'shop',
  customer_cancelled: 'shop',
  deadline_half: 'shop',
  deadline_final: 'shop',
  morning_summary: 'shop',
  accepted: 'customer',
  rejected: 'customer',
  proposal: 'customer',
  proposal_half: 'customer',
  proposal_final: 'customer',
  expired_shop: 'customer',
  expired_customer: 'customer',
  shop_cancelled: 'customer',
  closure_proposal: 'customer',
  appointment_reminder: 'customer',
};

/** الاختيارية تُوقف من الإعدادات؛ كل ما عداها إجباري لا يُوقف */
export const OPTIONAL: Partial<Record<NotificationType, 'reminders' | 'morningSummary'>> = {
  deadline_half: 'reminders',
  deadline_final: 'reminders',
  proposal_half: 'reminders',
  proposal_final: 'reminders',
  appointment_reminder: 'reminders',
  morning_summary: 'morningSummary',
};

/** العاجلة تصل بأولوية عالية وصوت، لأن مهلتها قصيرة */
export const URGENT = new Set<NotificationType>([
  'new_request', 'deadline_final', 'proposal', 'proposal_final', 'closure_proposal', 'customer_chose',
]);

export interface TextParams {
  shop?: string;
  customer?: string;
  startsAt?: string; // ISO
  minutes?: number;
  count?: number;
}

const MONTHS = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
const DAYS = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/** الخميس 24 أيلول · 10:00 ص، بتوقيت بغداد وأرقام غربية */
export function formatWhen(iso: string): string {
  const d = new Date(Date.parse(iso) + BAGHDAD_OFFSET_MINUTES * 60_000);
  const h = d.getUTCHours();
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  const min = String(d.getUTCMinutes()).padStart(2, '0');
  return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} · ${hour12}:${min} ${h < 12 ? 'ص' : 'م'}`;
}

function duration(minutes = 0): string {
  if (minutes >= 60 && minutes % 60 === 0) {
    const h = minutes / 60;
    return h === 1 ? 'ساعة واحدة' : h === 2 ? 'ساعتين' : h <= 10 ? `${h} ساعات` : `${h} ساعة`;
  }
  return minutes === 1 ? 'دقيقة' : minutes === 2 ? 'دقيقتين' : minutes <= 10 ? `${minutes} دقائق` : `${minutes} دقيقة`;
}

export function renderText(type: NotificationType, p: TextParams): { title: string; body: string } {
  const when = p.startsAt ? formatWhen(p.startsAt) : '';
  switch (type) {
    case 'new_request':
      return { title: 'طلب حجز جديد', body: `${p.customer} يطلب موعداً ${when}. رُدّ خلال ${duration(p.minutes)}.` };
    case 'new_instant_booking':
      return { title: 'حجز جديد مؤكد', body: `${p.customer} حجز موعداً ${when}.` };
    case 'customer_chose':
      return { title: 'الزبون اختار وقتاً', body: `${p.customer} أكّد الموعد ${when}.` };
    case 'customer_declined':
      return { title: 'الزبون رفض الأوقات المقترحة', body: `${p.customer} رفض الاقتراح، وأُلغي الحجز.` };
    case 'customer_cancelled':
      return { title: 'ألغى الزبون حجزه', body: `${p.customer} ألغى موعد ${when}.` };
    case 'deadline_half':
      return { title: 'طلب ينتظر ردك', body: `بقي ${duration(p.minutes)} على طلب ${p.customer}، وبعدها يُلغى تلقائياً.` };
    case 'deadline_final':
      return { title: 'مهلة الرد تنتهي الآن', body: `بقي ${duration(p.minutes)} فقط على طلب ${p.customer}.` };
    case 'morning_summary':
      return { title: 'حجوزات اليوم', body: p.count === 1 ? 'عندك حجز واحد اليوم.' : p.count === 2 ? 'عندك حجزان اليوم.' : `عندك ${p.count} حجوزات اليوم.` };
    case 'accepted':
      return { title: 'تم قبول حجزك', body: `موعدك في ${p.shop} ${when}.` };
    case 'rejected':
      return { title: 'لم يُقبل طلبك', body: `${p.shop} لم يقبل الطلب. جرّب وقتاً آخر.` };
    case 'proposal':
      return { title: 'المحل اقترح وقتاً آخر', body: `${p.shop} اقترح أوقاتاً بديلة. اختر خلال ${duration(p.minutes)}.` };
    case 'proposal_half':
      return { title: 'اختر وقتك', body: `بقي ${duration(p.minutes)} لتختار أحد الأوقات التي اقترحها ${p.shop}.` };
    case 'proposal_final':
      return { title: 'مهلتك تنتهي الآن', body: `بقي ${duration(p.minutes)} فقط لتختار وقتاً من ${p.shop}.` };
    case 'expired_shop':
      return { title: 'لم يرد المحل في الوقت المحدد', body: `أُلغي طلبك في ${p.shop}. جرّب وقتاً آخر.` };
    case 'expired_customer':
      return { title: 'انتهت مهلة الاختيار', body: `أُلغي حجزك في ${p.shop} لأنك لم تختر وقتاً.` };
    case 'shop_cancelled':
      return { title: 'ألغى المحل حجزك', body: `${p.shop} ألغى موعد ${when}. نعتذر عن ذلك.` };
    case 'closure_proposal':
      return { title: 'المحل مغلق وقت موعدك', body: `${p.shop} أُغلق طارئاً. اختر أحد الأوقات البديلة خلال ${duration(p.minutes)}.` };
    case 'appointment_reminder':
      return { title: 'موعدك بعد ساعة', body: `موعدك في ${p.shop} ${when}.` };
  }
}
