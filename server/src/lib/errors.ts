/**
 * أخطاء الخادم تُرسل برمز ثابت فقط، والتطبيق يترجم الرمز من ملف الترجمة
 * (لا نصوص عربية داخل الخادم، حتى تُضاف الكردية دون تعديله).
 */
export class AppError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(code);
  }
}
