# تطبيق حجز (Flutter)

تطبيق الزبون: التصفح، الحجز بثلاث خطوات، حجوزاتي، والرد على اقتراح المحل.

- كل النصوص في `lib/l10n/app_ar.arb`؛ الكردية تُضاف بملف `app_ckb.arb` بالمفاتيح نفسها.
- الألوان في `lib/theme/colors.dart` فقط.
- الخط IBM Plex Sans Arabic مضمّن في `assets/fonts` ويدعم الحروف الكردية.
- الأوقات تُعرض بتوقيت بغداد بنظام 12 ساعة وأرقام غربية، والعداد يُحسب بتوقيت الخادم.

## التشغيل

```sh
flutter pub get
flutter test
flutter run                                         # يتصل بخادم Railway
flutter run --dart-define=API_URL=http://10.0.2.2:3000   # خادم محلي من محاكي أندرويد
```

## نسخة أندرويد التجريبية

كل دفع إلى GitHub يبني ملف APK في مسار العمل `app` (GitHub Actions)،
ويُحمَّل من صفحة التشغيل تحت **Artifacts** باسم `hajiz-android-apk`.
