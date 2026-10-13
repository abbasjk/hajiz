import 'package:flutter/material.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// طبقة الخريطة الأساسية من خدمة خرائط مجانية مفتوحة: بلا مفتاح ولا حدود، ومسموحة تجارياً.
/// الخرائط بصيغة متجهة؛ النمط يُحمَّل مرة واحدة ويُحفظ لبقية الخرائط في التطبيق.
/// إذا تعذر التحميل (دون اتصال) تبقى الخريطة بلا خلفية وتظهر الدبابيس فوقها.
class BaseMapLayer extends StatefulWidget {
  const BaseMapLayer({super.key});

  static const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// سطر الحقوق المطلوب، مختصراً ليتسع في الخرائط الصغيرة
  static const attribution = '© OpenFreeMap © OpenMapTiles © OpenStreetMap';

  static Style? _cache;
  static Future<Style>? _loading;

  @override
  State<BaseMapLayer> createState() => _BaseMapLayerState();
}

class _BaseMapLayerState extends State<BaseMapLayer> {
  Style? _style = BaseMapLayer._cache;

  @override
  void initState() {
    super.initState();
    if (_style == null) _load();
  }

  Future<void> _load() async {
    try {
      final style = await (BaseMapLayer._loading ??= StyleReader(uri: BaseMapLayer.styleUrl).read());
      BaseMapLayer._cache = style;
      if (mounted) setState(() => _style = style);
    } catch (_) {
      // تُعاد المحاولة عند فتح خريطة لاحقاً
      BaseMapLayer._loading = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style == null) return const SizedBox.shrink();
    return VectorTileLayer(
      tileProviders: style.providers,
      theme: style.theme,
      sprites: style.sprites,
      maximumZoom: 20,
      tileOffset: TileOffset.mapbox,
      layerMode: VectorTileLayerMode.vector,
    );
  }
}
