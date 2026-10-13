import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import '../widgets/base_map.dart';

/// مركز البصرة؛ تبدأ منه الخريطة إن لم يكن هناك موقع ولا محلات
const _basra = LatLng(30.508, 47.783);

/// المحلات على الخريطة: دبوس لكل محل، والضغط عليه يُظهر بطاقته في الأسفل.
/// تتبع نتائج البحث والتصفية نفسها التي في القائمة.
class ShopsMap extends StatefulWidget {
  const ShopsMap({super.key, required this.shops, this.position});
  final List<ShopSummary> shops;
  final ({double lat, double lng})? position;

  @override
  State<ShopsMap> createState() => _ShopsMapState();
}

class _ShopsMapState extends State<ShopsMap> {
  final _map = MapController();
  bool _ready = false;
  int? _selectedId;

  List<ShopSummary> get _located =>
      widget.shops.where((s) => s.latitude != null && s.longitude != null).toList();

  LatLng? get _me => widget.position == null ? null : LatLng(widget.position!.lat, widget.position!.lng);

  CameraFit? _fitFor(List<ShopSummary> shops) => shops.isEmpty
      ? null
      : CameraFit.coordinates(
          coordinates: [for (final s in shops) LatLng(s.latitude!, s.longitude!)],
          padding: const EdgeInsets.fromLTRB(48, 48, 48, 160),
          maxZoom: 15,
        );

  @override
  void didUpdateWidget(ShopsMap old) {
    super.didUpdateWidget(old);
    final before = old.shops.map((s) => s.id).toList();
    final after = widget.shops.map((s) => s.id).toList();
    if (before.join(',') == after.join(',')) return;
    // نتائج جديدة: تُعرض كلها، ويُلغى اختيار محل لم يعد ضمنها
    if (!after.contains(_selectedId)) _selectedId = null;
    final fit = _fitFor(_located);
    if (_ready && fit != null) _map.fitCamera(fit);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final located = _located;
    final selected = located.where((s) => s.id == _selectedId).firstOrNull;
    final me = _me;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: me ?? _basra,
            initialZoom: me == null ? 12 : 13,
            // بلا موقع: تُعرض المحلات كلها؛ مع الموقع: يبدأ من حول الزبون
            initialCameraFit: me == null ? _fitFor(located) : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () => _ready = true,
            onTap: (_, _) => setState(() => _selectedId = null),
          ),
          children: [
            const BaseMapLayer(),
            if (me != null)
              MarkerLayer(markers: [
                Marker(
                  point: me,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.myLocation,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 4)],
                    ),
                  ),
                ),
              ]),
            MarkerLayer(markers: [
              for (final s in located)
                Marker(
                  point: LatLng(s.latitude!, s.longitude!),
                  width: 48,
                  height: 48,
                  child: _Pin(
                    shop: s,
                    selected: s.id == _selectedId,
                    onTap: () => setState(() => _selectedId = s.id),
                  ),
                ),
            ]),
            const SimpleAttributionWidget(source: Text('OpenFreeMap · OpenMapTiles · OpenStreetMap')),
          ],
        ),
        if (me != null)
          PositionedDirectional(
            top: 12,
            end: 12,
            child: FloatingActionButton.small(
              heroTag: 'my-location',
              tooltip: l.myLocation,
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: () => _map.move(me, 14),
              child: const Icon(Icons.my_location),
            ),
          ),
        if (located.isEmpty)
          PositionedDirectional(
            top: 12,
            start: 12,
            end: me == null ? 12 : 64,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l.noShopsOnMap, style: const TextStyle(color: AppColors.textMuted)),
              ),
            ),
          ),
        if (selected != null)
          PositionedDirectional(
            start: 12,
            end: 12,
            // فوق زر "القائمة" العائم
            bottom: 88,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              color: Colors.transparent,
              child: ShopCard(shop: selected),
            ),
          ),
      ],
    );
  }
}

/// دبوس المحل: دائرة بلون التطبيق، وأكبر وأغمق للمحل المختار
class _Pin extends StatelessWidget {
  const _Pin({required this.shop, required this.selected, required this.onTap});
  final ShopSummary shop;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 44.0 : 34.0;
    return Semantics(
      button: true,
      selected: selected,
      label: shop.name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Icon(Icons.storefront, color: Colors.white, size: selected ? 22 : 17),
          ),
        ),
      ),
    );
  }
}
