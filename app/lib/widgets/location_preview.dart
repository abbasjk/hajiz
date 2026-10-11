import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/app_localizations.dart';
import '../theme/colors.dart';
import '../util/links.dart';

/// خريطة صغيرة ثابتة عليها دبوس المحل؛ الضغط عليها يفتح الاتجاهات في تطبيق الخرائط.
/// في البصرة كثير من العناوين بلا أسماء شوارع، فالدبوس أوضح من العنوان المكتوب.
class LocationPreview extends StatelessWidget {
  const LocationPreview({super.key, required this.latitude, required this.longitude, required this.label, this.height = 160});
  final double latitude;
  final double longitude;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final point = LatLng(latitude, longitude);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: Stack(children: [
            // للعرض فقط: لا سحب ولا تكبير داخل الصفحة حتى لا يتعارض مع تمرير الصفحة
            IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 16,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'iq.hajiz.hajiz'),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, size: 40, color: AppColors.primary),
                    ),
                  ]),
                ],
              ),
            ),
            // حقوق الخريطة مطلوبة؛ سطر صغير بدل شريط الحقوق الكامل الذي لا يتسع في خريطة صغيرة
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: AppColors.surface.withValues(alpha: 0.85),
                child: const Text('© OpenStreetMap', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: Semantics(
                  button: true,
                  label: l.getDirections,
                  child: InkWell(onTap: () => openInMaps(latitude, longitude, label)),
                ),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        onPressed: () => openInMaps(latitude, longitude, label),
        icon: const Icon(Icons.directions_outlined),
        label: Text(l.getDirections),
      ),
    ]);
  }
}
