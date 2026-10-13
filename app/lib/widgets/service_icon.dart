import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// أيقونة نوع الخدمة: رسمة بنفسجية بلا خلفية بلمسة برتقالية، على طريقة شعار التطبيق
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

/// أيقونة الرجال أو النساء ('men' أو 'women') بلون واحد يمكن تغييره
class GenderIcon extends StatelessWidget {
  const GenderIcon(this.who, {super.key, this.size = 20, required this.color});
  final String who;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/gender_icons/${who == 'women' ? 'women' : 'men'}.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
