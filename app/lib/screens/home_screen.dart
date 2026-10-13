import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_detail_screen.dart';
import 'notifications_screen.dart';
import 'shop_screen.dart';
import 'shops_map.dart';

/// الرئيسية كما في ملف التصميم: الترحيب، والبحث مع زر التصفية، وموعدك القادم،
/// ثم الأقرب إليك، ومختارة لك، ومحل مميز، والبحث على الخريطة.
/// عند البحث أو التصفية تتحول إلى قائمة نتائج.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ServerConfig? _config;
  List<ShopSummary>? _shops;
  Object? _error;
  Booking? _upcoming;

  int? _typeId;
  int? _districtId;
  int? _areaId;
  String _query = '';
  String _sort = 'name';
  bool _sortChosen = false;
  ({double lat, double lng})? _position;
  bool _locationDenied = false;
  Timer? _debounce;
  int _requestId = 0;
  bool _showAll = false;

  /// عرض المحلات على الخريطة بدل القائمة، بنفس البحث والتصفية
  bool _mapView = false;
  final _search = TextEditingController();

  /// أقسام الرئيسية أم قائمة نتائج
  bool get _filtering => _query.trim().isNotEmpty || _typeId != null || _districtId != null || _areaId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final services = AppScope.of(context);
    try {
      final config = await services.config();
      if (!mounted) return;
      setState(() => _config = config);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    // القائمة تظهر فوراً، ثم تُرتب حسب القرب عندما يصل الموقع
    unawaited(_load());
    unawaited(_loadUpcoming());
    unawaited(_locate());
  }

  /// الموقع لترتيب المحلات حسب القرب؛ إذا رُفض يبقى الترتيب حسب الاسم
  Future<void> _locate() async {
    final position = await AppScope.of(context).locate();
    if (!mounted) return;
    if (position == null) return setState(() => _locationDenied = true);
    _position = position;
    if (_sortChosen) return setState(() {});
    _set(() => _sort = 'distance');
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() => _error = null);
    try {
      final shops = await AppScope.of(context).api.shops(
            businessTypeId: _typeId,
            districtId: _districtId,
            areaId: _areaId,
            query: _query,
            lat: _position?.lat,
            lng: _position?.lng,
            sort: _sort,
            // الخريطة تعرض محلات أكثر من القائمة
            limit: _mapView ? 200 : null,
          );
      if (mounted && id == _requestId) setState(() => _shops = shops);
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e);
    }
  }

  /// أقرب حجز قائم للزبون، يظهر في بطاقة "موعدك القادم"
  Future<void> _loadUpcoming() async {
    final services = AppScope.of(context);
    if (!services.session.isRegistered) return;
    try {
      final now = services.client.serverNow;
      final list = (await services.api.myBookings()).bookings.where((b) =>
          (b.status == BookingStatus.confirmed || b.status.isPending) && b.startsAt.isAfter(now)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      if (mounted) setState(() => _upcoming = list.firstOrNull);
    } catch (_) {
      // البطاقة اختيارية؛ دون اتصال لا تظهر
    }
  }

  Future<void> _refresh() => Future.wait([_load(), _loadUpcoming()]);

  void _onQuery(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  // ============================================================
  // التصفية: نوع العمل، القضاء والمنطقة، الترتيب
  // ============================================================

  Future<void> _openFilters() async {
    final l = AppLocalizations.of(context);
    final config = _config!;
    var typeId = _typeId;
    var districtId = _districtId;
    var areaId = _areaId;
    var sort = _sort;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final areas = config.areas.where((a) => a.districtId == districtId).toList();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(l.filtersTitle, style: AppText.headline)),
                  TextButton(
                    onPressed: () => setSheet(() {
                      typeId = null;
                      districtId = null;
                      areaId = null;
                    }),
                    child: Text(l.clearFilters),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(l.businessTypeLabel, style: AppText.title),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (id, name) in [(null, l.allTypes), for (final t in config.businessTypes) (t.id, t.name)])
                    ChoiceChip(
                      label: Text(name),
                      selected: typeId == id,
                      side: BorderSide(color: typeId == id ? AppColors.primary : AppColors.border),
                      onSelected: (_) => setSheet(() => typeId = id),
                    ),
                ]),
                const SizedBox(height: 16),
                Text(l.districtLabel, style: AppText.title),
                const SizedBox(height: 8),
                _dropdown<int?>(
                  value: districtId,
                  items: {null: l.allDistricts, for (final d in config.districts) d.id: d.name},
                  onChanged: (v) => setSheet(() {
                    districtId = v;
                    areaId = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(l.areaLabel, style: AppText.title),
                const SizedBox(height: 8),
                _dropdown<int?>(
                  key: ValueKey(districtId),
                  value: areaId,
                  items: {null: l.allAreas, for (final a in areas) a.id: a.name},
                  onChanged: areas.isEmpty ? null : (v) => setSheet(() => areaId = v),
                ),
                const SizedBox(height: 16),
                Text(l.sortByLabel, style: AppText.title),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    if (_position != null) ButtonSegment(value: 'distance', label: Text(l.sortDistance)),
                    ButtonSegment(value: 'soonest', label: Text(l.sortSoonest)),
                    ButtonSegment(value: 'name', label: Text(l.sortName)),
                  ],
                  selected: {sort},
                  onSelectionChanged: (s) => setSheet(() => sort = s.first),
                ),
                if (_locationDenied) ...[
                  const SizedBox(height: 8),
                  Text(l.locationDenied, style: AppText.caption),
                ],
                const SizedBox(height: 20),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.showResults)),
              ]),
            ),
          );
        },
      ),
    );
    if (apply != true) return;
    _set(() {
      _typeId = typeId;
      _districtId = districtId;
      _areaId = areaId;
      if (sort != _sort) _sortChosen = true;
      _sort = sort;
      _showAll = false;
    });
  }

  Widget _dropdown<T>({Key? key, required T value, required Map<T, String> items, ValueChanged<T?>? onChanged}) {
    return DropdownButtonFormField<T>(
      key: key,
      initialValue: value,
      isExpanded: true,
      items: [
        for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  // ============================================================
  // الواجهة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = _config;
    return Scaffold(
      // على الخريطة فقط: زر عائم للعودة إلى القائمة. في القائمة قسم "البحث على الخريطة" يفتحها
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: config == null || !_mapView
          ? null
          : FloatingActionButton.extended(
              heroTag: 'map-toggle',
              onPressed: () => _set(() => _mapView = false),
              icon: const Icon(Icons.view_list_outlined),
              label: Text(l.showList),
            ),
      body: SafeArea(
        bottom: false,
        child: config == null
            ? LoadState(error: _error, onRetry: _start)
            : _mapView
            ? Column(
                children: [
                  _header(l, config),
                  Expanded(
                    child: _shops == null
                        ? LoadState(error: _error, onRetry: _load)
                        : ShopsMap(shops: _shops!, position: _position),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    _header(l, config),
                    ..._content(l),
                  ],
                ),
              ),
      ),
    );
  }

  /// الموقع والإشعارات، ثم الترحيب، ثم البحث وزر التصفية
  Widget _header(AppLocalizations l, ServerConfig config) {
    final user = AppScope.of(context).session.user;
    final place = config.areas.where((a) => a.id == _areaId).firstOrNull?.name ??
        config.districts.where((d) => d.id == _districtId).firstOrNull?.name ??
        (_position != null ? l.nearYou : l.allAreas);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InkWell(
            onTap: _openFilters,
            borderRadius: BorderRadius.circular(AppRadius.base),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on, size: 18, color: AppColors.locationPin),
                const SizedBox(width: 4),
                Text(place, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text)),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.primaryBright),
              ]),
            ),
          ),
          const Spacer(),
          const NotificationsBell(audience: 'customer'),
        ]),
        if (!_mapView) ...[
          const SizedBox(height: 8),
          if (user != null) ...[
            Text(l.hello, style: const TextStyle(fontSize: 13, color: AppColors.text)),
            Text(user.name, style: AppText.headline),
          ] else
            Text(l.welcomeGuest, style: AppText.headline),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _search,
                onChanged: (v) {
                  setState(() => _showAll = false);
                  _onQuery(v);
                },
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: l.searchHint,
                  hintStyle: const TextStyle(fontSize: 14, color: AppColors.primaryMuted),
                  fillColor: AppColors.searchFill,
                  contentPadding: EdgeInsets.zero,
                  prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // زر التصفية: مربع بنفسجي 44، ونقطة برتقالية إن كانت هناك تصفية مفعّلة
          SizedBox(
            width: 44,
            height: 44,
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.base),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.base),
                onTap: _openFilters,
                child: Stack(alignment: Alignment.center, children: [
                  Icon(Icons.tune, color: Colors.white, semanticLabel: l.filtersTitle),
                  if (_typeId != null || _districtId != null || _areaId != null)
                    const PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: CircleAvatar(radius: 4, backgroundColor: AppColors.accent),
                    ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  List<Widget> _content(AppLocalizations l) {
    final shops = _shops;
    if (shops == null || (_error != null && shops.isEmpty)) {
      return [Padding(padding: const EdgeInsets.only(top: 80), child: LoadState(error: _error, onRetry: _load))];
    }
    if (_filtering) return _results(l, shops);
    return [
      if (_upcoming != null) _upcomingCard(l, _upcoming!),
      ..._nearest(l, shops),
      ..._picked(l, shops),
      ..._featured(l, shops),
      if (shops.any((s) => s.latitude != null)) ..._mapSearch(l, shops),
    ];
  }

  Widget _sectionTitle(String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
        child: Row(children: [
          Expanded(child: Text(text, style: AppText.headline)),
          ?trailing,
        ]),
      );

  // ---------------- نتائج البحث والتصفية ----------------

  List<Widget> _results(AppLocalizations l, List<ShopSummary> shops) {
    if (shops.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(child: Text(l.noShops, style: AppText.body)),
        ),
      ];
    }
    return [
      _sectionTitle(l.searchResultsCount(shops.length)),
      for (final s in shops)
        Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: ProviderRow(shop: s)),
    ];
  }

  // ---------------- موعدك القادم ----------------

  Widget _upcomingCard(AppLocalizations l, Booking b) {
    final client = AppScope.of(context).client;
    final photo = _shops?.where((s) => s.id == b.shop.id).firstOrNull?.coverPhoto;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.upcomingAppointment,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.sectionLabel)),
        const SizedBox(height: 14),
        Material(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: b.id, initial: b)));
              _loadUpcoming();
            },
            child: SizedBox(
              height: 100,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Container(
                    width: 59,
                    height: 59,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white),
                      color: AppColors.primaryBright,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: photo != null
                        ? Image.network(client.absoluteUrl(photo), fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(Icons.storefront, color: Colors.white))
                        : const Icon(Icons.storefront, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.services.map((s) => s.name).join('، '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
                      Text(l.withShop(b.shop.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: AppColors.onPrimaryMuted)),
                      const SizedBox(height: 4),
                      Text(formatAppointment(l, b.startsAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: Colors.white, letterSpacing: 0.5)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Align(
                    alignment: const Alignment(0, -0.45),
                    child: Container(
                      height: 27,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13.5)),
                      child: Text(l.viewLabel,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------- الأقرب إليك ----------------

  List<Widget> _nearest(AppLocalizations l, List<ShopSummary> shops) {
    if (shops.isEmpty) {
      return [
        _sectionTitle(_sort == 'distance' ? l.nearestProviders : l.allShopsTitle),
        Padding(padding: const EdgeInsets.all(18), child: Center(child: Text(l.noShops, style: AppText.body))),
      ];
    }
    final visible = _showAll ? shops : shops.take(3).toList();
    return [
      _sectionTitle(_sort == 'distance' ? l.nearestProviders : l.allShopsTitle),
      for (final s in visible)
        Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 16), child: ProviderRow(shop: s)),
      if (shops.length > 3)
        Center(
          child: SizedBox(
            width: 152,
            height: 46,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                textStyle: const TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w700),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_showAll ? l.seeLess : l.seeMore),
                const SizedBox(width: 8),
                Icon(_showAll ? Icons.expand_less : Icons.open_in_new, size: 20),
              ]),
            ),
          ),
        ),
    ];
  }

  // ---------------- مختارة لك: الأعلى تقييماً ----------------

  List<Widget> _picked(AppLocalizations l, List<ShopSummary> shops) {
    final rated = shops.where((s) => s.rating != null && s.ratingCount > 0).toList()
      ..sort((a, b) => b.rating!.compareTo(a.rating!) != 0 ? b.rating!.compareTo(a.rating!) : b.ratingCount.compareTo(a.ratingCount));
    if (rated.isEmpty) return const [];
    return [
      _sectionTitle(l.pickedForYou),
      SizedBox(
        height: 164,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: rated.take(8).length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => _PickedCard(shop: rated[i]),
        ),
      ),
    ];
  }

  // ---------------- محل مميز: تختاره الإدارة ----------------

  List<Widget> _featured(AppLocalizations l, List<ShopSummary> shops) {
    final shop = shops.where((s) => s.featured).firstOrNull;
    if (shop == null) return const [];
    final client = AppScope.of(context).client;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId: shop.id)));
    return [
      _sectionTitle(l.featuredProvider),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(AppRadius.base),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.base),
              child: SizedBox(
                height: 216,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  ShopImage(url: shop.coverPhoto == null ? null : client.absoluteUrl(shop.coverPhoto!), iconSize: 48),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: DetailsButton(onPressed: open, height: 40, fontSize: 14, padding: 22),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Text(shop.name, style: AppText.title),
            const SizedBox(height: 6),
            ShopMeta(shop: shop),
          ]),
        ),
      ),
    ];
  }

  // ---------------- البحث على الخريطة ----------------

  List<Widget> _mapSearch(AppLocalizations l, List<ShopSummary> shops) {
    final located = shops.where((s) => s.latitude != null && s.longitude != null).toList();
    final center = _position != null
        ? LatLng(_position!.lat, _position!.lng)
        : LatLng(located.first.latitude!, located.first.longitude!);
    return [
      _sectionTitle(l.mapSearch),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.base),
          child: SizedBox(
            height: 220,
            child: Stack(children: [
              IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(initialCenter: center, initialZoom: 12, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'iq.hajiz.hajiz'),
                    MarkerLayer(markers: [
                      for (final s in located)
                        Marker(
                          point: LatLng(s.latitude!, s.longitude!),
                          width: 26,
                          height: 26,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.storefront, size: 13, color: Colors.white),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
              PositionedDirectional(
                end: 12,
                bottom: 12,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontFamily: appFont, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _set(() => _mapView = true),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(l.findHere),
                ),
              ),
              PositionedDirectional(
                start: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: AppColors.surface.withValues(alpha: 0.85),
                  child: const Text('© OpenStreetMap', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ];
  }
}

// ============================================================
// قطع مشتركة بين الرئيسية والخريطة
// ============================================================

/// صورة المحل، أو شكل بنفسجي بأيقونة إن لم تكن له صورة
class ShopImage extends StatelessWidget {
  const ShopImage({super.key, this.url, this.iconSize = 32});
  final String? url;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Icon(Icons.storefront, size: iconSize, color: AppColors.primaryLight),
    );
    if (url == null) return placeholder;
    return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
  }
}

/// زر "تفاصيل المحل": بنفسجي بزاويتين متقابلتين كما في التصميم
class DetailsButton extends StatelessWidget {
  const DetailsButton({super.key, required this.onPressed, this.height = 30, this.fontSize = 13, this.padding = 14});
  final VoidCallback onPressed;
  final double height;
  final double fontSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadiusDirectional.only(topEnd: Radius.circular(8), bottomStart: Radius.circular(8));
    return DecoratedBox(
      decoration: const BoxDecoration(boxShadow: AppShadows.card),
      child: Material(
        color: AppColors.primary,
        shape: const RoundedRectangleBorder(borderRadius: radius),
        child: InkWell(
          customBorder: const RoundedRectangleBorder(borderRadius: radius),
          onTap: onPressed,
          // بعرض النص فقط، لا يتمدد على عرض الصف
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Center(
                widthFactor: 1,
                child: Text(AppLocalizations.of(context).providerDetails,
                    style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// العنوان والمسافة، ثم التقييم وشارات المحل
class ShopMeta extends StatelessWidget {
  const ShopMeta({super.key, required this.shop, this.compact = false});
  final ShopSummary shop;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final place = [shop.area, shop.district].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    final distance = shop.distanceKm == null ? '' : ' (${l.distanceKm(shop.distanceKm!.toStringAsFixed(1))})';
    const muted = TextStyle(fontSize: 14, color: AppColors.primaryMuted);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (place.isNotEmpty || distance.isNotEmpty)
        Row(children: [
          const Icon(Icons.location_on, size: 16, color: AppColors.primaryMuted),
          const SizedBox(width: 4),
          Flexible(child: Text('$place$distance', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
        ]),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.primaryMuted),
          const SizedBox(width: 4),
          Text(
            shop.rating != null && shop.ratingCount > 0
                ? '${shop.rating!.toStringAsFixed(1)} (${shop.ratingCount})'
                : l.newShop,
            style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ]),
        if (!compact && shop.committed) _badge(l.committedBadge),
        if (!compact && shop.instantBooking) _badge(l.instantBadge),
      ]),
      if (!compact && shop.nextAvailable != null) ...[
        const SizedBox(height: 4),
        Text(l.nextAvailable('${formatDayShort(l, shop.nextAvailable!)} ${formatTime(l, shop.nextAvailable!)}'),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ],
    ]);
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
      );
}

/// صف المحل كما في "الأقرب إليك": صورة 100، الاسم والعنوان والتقييم، وزر التفاصيل
class ProviderRow extends StatelessWidget {
  const ProviderRow({super.key, required this.shop});
  final ShopSummary shop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = AppScope.of(context).client;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId: shop.id)));
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.base),
            child: SizedBox(
              width: 100,
              height: 100,
              child: ShopImage(url: shop.coverPhoto == null ? null : client.absoluteUrl(shop.coverPhoto!)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.title.copyWith(height: 1.3)),
              if (shop.matchedService != null)
                Text('${shop.matchedService!.name} · ${formatPrice(l, shop.matchedService!)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryBright)),
              const SizedBox(height: 4),
              ShopMeta(shop: shop),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: DetailsButton(onPressed: open)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// بطاقة "مختارة لك": صورة بزوايا دائرية كبيرة ونوع العمل عليها، والاسم والتقييم والعنوان
class _PickedCard extends StatelessWidget {
  const _PickedCard({required this.shop});
  final ShopSummary shop;

  @override
  Widget build(BuildContext context) {
    final client = AppScope.of(context).client;
    void open() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId: shop.id)));
    final place = [shop.area, shop.district].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    return Container(
      width: 268,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.cardFill, borderRadius: BorderRadius.circular(25), boxShadow: AppShadows.card),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(25),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: SizedBox(
                  width: 130,
                  child: Stack(fit: StackFit.expand, children: [
                    ShopImage(url: shop.coverPhoto == null ? null : client.absoluteUrl(shop.coverPhoto!)),
                    if (shop.businessType != null)
                      PositionedDirectional(
                        start: 12,
                        bottom: 8,
                        child: Container(
                          height: 27,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.tag, borderRadius: BorderRadius.circular(8)),
                          child: Text(shop.businessType!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white)),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 10),
                  Text(shop.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                    const SizedBox(width: 2),
                    Text(shop.rating!.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
                  ]),
                  if (place.isNotEmpty)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.location_on, size: 12, color: AppColors.inkMuted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(place, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: AppColors.inkMuted)),
                      ),
                    ]),
                  const Spacer(),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: DetailsButton(onPressed: open, height: 28, fontSize: 11, padding: 10),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// بطاقة المحل على الخريطة: صف المحل داخل بطاقة بيضاء
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop});
  final ShopSummary shop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: ProviderRow(shop: shop)),
    );
  }
}
