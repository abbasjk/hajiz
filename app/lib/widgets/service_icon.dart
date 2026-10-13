import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// أيقونة نوع الخدمة: رسمة بيضاء داخل دائرة بنفسجية بلمسة برتقالية، على طريقة شعار التطبيق
class ServiceIcon extends StatelessWidget {
  const ServiceIcon(this.icon, {super.key, this.size = 32});
  final String icon;
  final double size;

  static const known = {
    'haircut', 'beard', 'dye', 'kids', 'skin', 'groom', 'treatment', 'threading', 'styling', 'razor',
    'womencut', 'makeup', 'nails', 'bride', 'lashes',
  };

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/service_icons/${known.contains(icon) ? icon : 'haircut'}.svg',
        width: size,
        height: size,
      );
}
