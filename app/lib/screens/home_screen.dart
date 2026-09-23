import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'notifications_screen.dart';
import 'shop_screen.dart';

/// الرئيسية: أنواع الأعمال مع المحلات القريبة، والبحث بالاسم أو النوع أو المنطقة.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ServerConfig? _config;
  List<ShopSummary>? _shops;
  Object? _error;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
          );
      if (mounted && id == _requestId) setState(() => _shops = shops);
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e);
    }
  }

  void _onQuery(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _set(VoidCallback change) {
    setState(change);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: Text(l.appName), actions: const [NotificationsBell(audience: 'customer'), SizedBox(width: 4)]),
      body: config == null
          ? LoadState(error: _error, onRetry: _start)
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _searchAndFilters(l, config)),
                  ..._results(l),
                ],
              ),
            ),
    );
  }

  Widget _searchAndFilters(AppLocalizations l, ServerConfig config) {
    final areas = config.areas.where((a) => a.districtId == _districtId).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            onChanged: _onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: l.searchHint, prefixIcon: const Icon(Icons.search)),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _typeChip(l.allTypes, null),
              for (final t in config.businessTypes) _typeChip(t.name, t.id),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: _dropdown<int?>(
                  value: _districtId,
                  items: {null: l.allDistricts, for (final d in config.districts) d.id: d.name},
                  onChanged: (v) => _set(() {
                    _districtId = v;
                    _areaId = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown<int?>(
                  value: _areaId,
                  items: {null: l.allAreas, for (final a in areas) a.id: a.name},
                  onChanged: areas.isEmpty ? null : (v) => _set(() => _areaId = v),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              if (_position != null) ButtonSegment(value: 'distance', label: Text(l.sortDistance)),
              ButtonSegment(value: 'soonest', label: Text(l.sortSoonest)),
              ButtonSegment(value: 'name', label: Text(l.sortName)),
            ],
            selected: {_sort},
            onSelectionChanged: (s) => _set(() {
              _sort = s.first;
              _sortChosen = true;
            }),
          ),
        ),
        if (_locationDenied)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l.locationDenied, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
      ],
    );
  }

  Widget _typeChip(String label, int? id) {
    final selected = _typeId == id;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primarySoft,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        onSelected: (_) => _set(() => _typeId = id),
      ),
    );
  }

  Widget _dropdown<T>({required T value, required Map<T, String> items, ValueChanged<T?>? onChanged}) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      items: [
        for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  List<Widget> _results(AppLocalizations l) {
    final shops = _shops;
    if (shops == null || (_error != null && shops.isEmpty)) {
      return [SliverFillRemaining(hasScrollBody: false, child: LoadState(error: _error, onRetry: _load))];
    }
    if (shops.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text(l.noShops, style: const TextStyle(color: AppColors.textMuted))),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        sliver: SliverList.separated(
          itemCount: shops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => ShopCard(shop: shops[i]),
        ),
      ),
    ];
  }
}

class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop});
  final ShopSummary shop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final place = [shop.businessType, shop.area ?? shop.district].whereType<String>().join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId: shop.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: shop.coverPhoto != null
                    ? Image.network(AppScope.of(context).client.absoluteUrl(shop.coverPhoto!), fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.storefront, color: AppColors.primary))
                    : const Icon(Icons.storefront, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (place.isNotEmpty)
                      Text(place, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (shop.distanceKm != null) _meta(l.distanceKm(shop.distanceKm!.toStringAsFixed(1))),
                        if (shop.nextAvailable != null)
                          _meta(l.nextAvailable('${formatDayShort(l, shop.nextAvailable!)} ${formatTime(l, shop.nextAvailable!)}')),
                        if (shop.committed) _badge(l.committedBadge),
                        if (shop.instantBooking) _badge(l.instantBadge),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(String text) => Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textMuted));

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
      );
}
