import 'package:flutter/material.dart';

/// الألوان مركزية هنا فقط، تمهيداً لإضافة الوضع الليلي لاحقاً بسهولة.
/// القيم مأخوذة من متغيرات ملف التصميم (الأسماء الأصلية في التعليقات).
class AppColors {
  const AppColors._();

  // اللون الأساسي — Primary Brand
  static const primary = Color(0xFF363062); // Primary Brand/900
  static const primaryDark = Color(0xFF363062);
  static const primaryMuted = Color(0xFF8683A1); // Primary Brand/500
  static const primaryLight = Color(0xFFC3C1D0); // Primary Brand/200
  static const primarySoft = Color(0xFFEDEFFB); // Primary Brand/50
  /// لون الأزرار الثانوية والروابط في بعض الشاشات — main
  static const primaryBright = Color(0xFF5F60B9);

  // اللون الثانوي: شريط مراحل الحجز والتنبيهات — Secondary/900
  static const accent = Color(0xFFF99417);

  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  /// خلفية حقول البحث والقطع الرمادية الفاتحة
  static const fill = Color(0xFFF4F4F5);

  static const text = Color(0xFF111827); // Cool Gray/900
  static const textMuted = Color(0xFF6B7280); // Cool Gray/500
  static const textDisabled = Color(0xFF94A3B8); // Blue Gray/400
  static const border = Color(0xFFE5E7EB);
  static const borderStrong = Color(0xFFCBD5E1); // Blue Gray/300
  static const track = Color(0xFFEDEFFB);
  static const disabledFill = Color(0xFFF4F4F5);

  static const warningSoft = Color(0xFFFEF3E2);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const success = Color(0xFF16A34A);

  static const star = Color(0xFFFACC15); // Yellow/400

  // ألوان خاصة بالرئيسية في ملف التصميم
  static const searchFill = Color(0xFFEBF0F5); // Blue Gray/100
  static const cardFill = Color(0xFFF5F4F8);
  static const tag = Color(0xFF234F68);
  static const ink = Color(0xFF252B5C);
  static const inkMuted = Color(0xFF53587A);
  static const sectionLabel = Color(0xFF2A2A37);
  static const onPrimaryMuted = Color(0xFF8D8DA6);
  static const locationPin = Color(0xFFFFBD00);
  static const myLocation = Color(0xFF2563EB);

  /// ظل البطاقات — Box S: إزاحة 2، تمويه 6
  static const shadow = Color(0x141C2731);
}

/// الظلال كما في ملف التصميم
class AppShadows {
  const AppShadows._();

  /// Box S
  static const card = [BoxShadow(color: AppColors.shadow, offset: Offset(0, 2), blurRadius: 6)];

  /// 06 dp: ثلاث طبقات للعناصر العائمة
  static const raised = [
    BoxShadow(color: Color(0x33000000), offset: Offset(0, 3), blurRadius: 5),
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 1), blurRadius: 18),
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 6), blurRadius: 10),
  ];
}
