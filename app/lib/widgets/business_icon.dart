import 'package:flutter/material.dart';

/// أيقونة نوع العمل من اسمها المحفوظ في الخادم. الأسماء نفسها في لوحة الإدارة.
/// 'all' لخانة "الكل".
class BusinessIcon extends StatelessWidget {
  const BusinessIcon(this.name, {super.key, this.size = 28, this.color});
  final String name;
  final double size;
  final Color? color;

  static const _material = <String, IconData>{
    'store': Icons.storefront_outlined,
    'scissors': Icons.content_cut,
    'sparkles': Icons.auto_awesome_outlined,
    'stethoscope': Icons.medical_services_outlined,
    'car': Icons.directions_car_outlined,
    'wrench': Icons.build_outlined,
    'spa': Icons.spa_outlined,
    'face': Icons.face_retouching_natural,
    'pets': Icons.pets,
    'fitness': Icons.fitness_center,
    'camera': Icons.photo_camera_outlined,
    'all': Icons.grid_view_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Colors.black;
    // لا توجد أيقونة سن في المجموعة المدمجة، فتُرسم بخط بالسماكة نفسها
    if (name == 'tooth') {
      return SizedBox(width: size, height: size, child: CustomPaint(painter: _ToothPainter(c)));
    }
    return Icon(_material[name] ?? Icons.storefront_outlined, size: size, color: c);
  }
}

class _ToothPainter extends CustomPainter {
  _ToothPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(7 * s, 3 * s)
      ..cubicTo(5 * s, 3 * s, 3.5 * s, 4.6 * s, 3.5 * s, 7 * s)
      ..cubicTo(3.5 * s, 9.5 * s, 4.5 * s, 11 * s, 5 * s, 13.5 * s)
      ..cubicTo(5.5 * s, 16 * s, 5.7 * s, 21 * s, 7.5 * s, 21 * s)
      ..cubicTo(9.3 * s, 21 * s, 9.1 * s, 16 * s, 11 * s, 16 * s)
      ..lineTo(13 * s, 16 * s)
      ..cubicTo(14.9 * s, 16 * s, 14.7 * s, 21 * s, 16.5 * s, 21 * s)
      ..cubicTo(18.3 * s, 21 * s, 18.5 * s, 16 * s, 19 * s, 13.5 * s)
      ..cubicTo(19.5 * s, 11 * s, 20.5 * s, 9.5 * s, 20.5 * s, 7 * s)
      ..cubicTo(20.5 * s, 4.6 * s, 19 * s, 3 * s, 17 * s, 3 * s)
      ..cubicTo(15.3 * s, 3 * s, 14.4 * s, 4 * s, 12 * s, 4 * s)
      ..cubicTo(9.6 * s, 4 * s, 8.7 * s, 3 * s, 7 * s, 3 * s)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ToothPainter old) => old.color != color;
}
