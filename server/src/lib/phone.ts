const ARABIC_DIGITS = '٠١٢٣٤٥٦٧٨٩';
const PERSIAN_DIGITS = '۰۱۲۳۴۵۶۷۸۹';

/** يحوّل الأرقام العربية والفارسية إلى غربية؛ التطبيق كله يستخدم الأرقام الغربية. */
export function toWesternDigits(value: string): string {
  return value.replace(/[٠-٩۰-۹]/g, (d) => {
    const i = ARABIC_DIGITS.indexOf(d);
    return String(i >= 0 ? i : PERSIAN_DIGITS.indexOf(d));
  });
}

/**
 * رقم موبايل عراقي بصيغة موحدة 07XXXXXXXXX، أو null إذا لم يكن صالحاً.
 * يقبل 0770..., 770..., +964770..., 00964770... مع مسافات أو شرطات.
 */
export function normalizeIraqiPhone(input: string): string | null {
  const digits = toWesternDigits(input).replace(/[\s\-().]/g, '');
  const m = /^(?:\+964|00964|964)?0?(7\d{9})$/.exec(digits);
  return m ? `0${m[1]}` : null;
}
