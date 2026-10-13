import 'package:flutter/material.dart';

import 'colors.dart';

/// الخط العربي المقابل لخط التصميم
const appFont = 'Vazirmatn';

/// أحجام الخطوط من ملف التصميم: عنوان 18، عنوان فرعي 16، نص 14، تعليق 12
class AppText {
  const AppText._();

  static const headline = TextStyle(fontFamily: appFont, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text);
  static const title = TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text);
  static const subtitle = TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text);
  static const body = TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMuted);
  static const caption = TextStyle(fontFamily: appFont, fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textDisabled);
}

/// الزوايا من ملف التصميم
class AppRadius {
  const AppRadius._();

  /// الأزرار والبطاقات والحقول
  static const base = 8.0;
  /// أزرار الأوقات
  static const chip = 10.0;
  /// بطاقات الأيام
  static const day = 13.0;
  /// بطاقة الموعد القادم
  static const hero = 25.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surface,
    error: AppColors.danger,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base));
  OutlineInputBorder inputBorder([Color color = Colors.transparent, double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.base),
        borderSide: color == Colors.transparent ? BorderSide.none : BorderSide(color: color, width: width),
      );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: appFont,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      titleLarge: AppText.headline,
      titleMedium: AppText.title,
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
      bodyLarge: TextStyle(fontSize: 16, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 14, color: AppColors.text),
      bodySmall: TextStyle(fontSize: 12, color: AppColors.textMuted),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: AppText.headline,
    ),
    // الزر الأساسي: ارتفاع 54، زاوية 8، نص 16 عريض
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primaryLight,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(80, 54),
        shape: shape,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
        shape: shape,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    // حقل البحث في التصميم: رمادي فاتح بلا حدود، زاوية 8
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.fill,
      hintStyle: AppText.body.copyWith(color: AppColors.textDisabled),
      border: inputBorder(),
      enabledBorder: inputBorder(),
      focusedBorder: inputBorder(AppColors.primary, 1.5),
      errorBorder: inputBorder(AppColors.danger),
      focusedErrorBorder: inputBorder(AppColors.danger, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    // البطاقات: بيضاء بظل خفيف، زاوية 8
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: AppColors.shadow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
    ),
    // أزرار الأوقات وأنواع النشاط: بيضاء بحد رمادي، والمختار بنفسجي بنص أبيض
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary,
      disabledColor: AppColors.fill,
      labelStyle: const TextStyle(fontFamily: appFont, fontSize: 14, color: AppColors.text),
      secondaryLabelStyle: const TextStyle(fontFamily: appFont, fontSize: 14, color: Colors.white),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip)),
      showCheckmark: false,
    ),
    // التبويبات بشكل كبسولة على خلفية بنفسجية فاتحة، كتبويب "حجوزات نشطة / السابقة"
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.surface : AppColors.primarySoft,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.text : AppColors.textMuted,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.primarySoft, width: 3)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    ),
    // الشريط السفلي: أبيض، الأيقونة المختارة بنفسجية والباقي رمادي
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 8,
      shadowColor: AppColors.shadow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textDisabled),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: appFont,
          fontSize: 14,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textDisabled,
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.borderStrong,
    )),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.text,
      contentTextStyle: const TextStyle(fontFamily: appFont, fontSize: 14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: AppText.headline,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dividerColor: AppColors.border,
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
  );
}
