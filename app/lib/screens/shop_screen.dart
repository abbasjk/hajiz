import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../util/links.dart';
import '../widgets/common.dart';
import '../widgets/location_preview.dart';
import 'booking_services_screen.dart';

// أدوات الاتصال والخرائط انتقلت إلى util/links.dart، وتبقى متاحة لمن يستورد هذه الشاشة
export '../util/links.dart' show callPhone, openInMaps, openWhatsApp;

/// صفحة المحل كما في التصميم: معرض صور، أزرار سريعة، ثم ثلاث تبويبات
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.shopId});
  final int shopId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ShopDetails? _shop;
  Object? _error;
  int _tab = 0;
  int _photo = 0;
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final shop = await AppScope.of(context).api.shop(widget.shopId);
      if (mounted) setState(() => _shop = shop);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _book(ShopDetails shop) {
    final initial = [for (final s in shop.services) if (_selected.contains(s.id)) s];
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingServicesScreen(shop: shop, initial: initial)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shop = _shop;
    return Scaffold(
      appBar: AppBar(title: Text(l.providerDetails, style: AppText.title)),
      body: shop == null ? LoadState(error: _error, onRetry: _load) : _body(l, shop),
      bottomNavigationBar: shop == null || shop.services.isEmpty
          ? null
          : BottomActionBar(
              child: FilledButton(
                onPressed: () => _book(shop),
                child: Text(_selected.isEmpty ? l.bookAppointment : l.bookSelected(_selected.length)),
              ),
            ),
    );
  }

  Widget _body(AppLocalizations l, ShopDetails shop) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _gallery(l, shop),
        const SizedBox(height: 14),
        Text(shop.name, style: AppText.headline),
        const SizedBox(height: 6),
        _meta(l, shop),
        if (shop.committed || shop.instantBooking) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (shop.committed) _badge(Icons.verified_outlined, l.committedBadge),
            if (shop.instantBooking) _badge(Icons.bolt, l.instantBadge),
          ]),
        ],
        const SizedBox(height: 16),
        _actions(l, shop),
        const SizedBox(height: 16),
        _tabs(l),
        const SizedBox(height: 16),
        ...switch (_tab) {
          0 => _servicesTab(l, shop),
          1 => _aboutTab(l, shop),
          _ => _reviewsTab(l, shop),
        },
      ],
    );
  }

  // ——— المعرض مع شارة مفتوح/مغلق ونقاط الصفحات ———
  Widget _gallery(AppLocalizations l, ShopDetails shop) {
    final client = AppScope.of(context).client;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: SizedBox(
        height: 216,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (shop.photos.isEmpty)
              Container(
                color: AppColors.primary,
                alignment: Alignment.center,
                child: const Icon(Icons.storefront, size: 64, color: AppColors.primaryLight),
              )
            else
              PageView(
                onPageChanged: (i) => setState(() => _photo = i),
                children: [
                  for (final url in shop.photos)
                    Image.network(client.absoluteUrl(url), fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(color: AppColors.primary)),
                ],
              ),
            PositionedDirectional(
              top: 0,
              end: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: shop.openNow ? const Color(0xFF27AE60) : AppColors.textMuted,
                  borderRadius: const BorderRadiusDirectional.only(
                    topEnd: Radius.circular(AppRadius.base),
                    bottomStart: Radius.circular(AppRadius.base),
                  ),
                ),
                child: Text(shop.openNow ? l.openNow : l.closedNow,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            if (shop.photos.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < shop.photos.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _photo ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _photo ? const Color(0xFF9368E9) : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meta(AppLocalizations l, ShopDetails shop) {
    final place = [shop.district, shop.area].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (place.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on, size: 16, color: AppColors.primaryMuted),
            const SizedBox(width: 4),
            Text(place, style: AppText.body),
          ]),
        if (shop.rating != null && shop.ratingCount > 0)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, size: 18, color: AppColors.star),
            const SizedBox(width: 4),
            Text('${shop.rating!.toStringAsFixed(1)} (${shop.ratingCount})', style: AppText.body),
          ]),
        if (shop.businessType != null) Text(shop.businessType!, style: AppText.body),
      ],
    );
  }

  // ——— الأزرار السريعة: الخريطة، اتصال، واتساب ———
  Widget _actions(AppLocalizations l, ShopDetails shop) {
    final items = <(IconData, String, VoidCallback)>[
      if (shop.latitude != null && shop.longitude != null)
        (Icons.map_outlined, l.mapsShort, () => openInMaps(shop.latitude!, shop.longitude!, shop.name)),
      if (shop.phone != null) ...[
        (Icons.call_outlined, l.call, () => callPhone(shop.phone!)),
        (Icons.chat_outlined, l.whatsapp, () => openWhatsApp(shop.phone!)),
      ],
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (icon, label, onTap) in items)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.base),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: AppColors.primary, size: 26),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primary)),
              ]),
            ),
          ),
      ],
    );
  }

  // ——— شريط التبويبات ———
  Widget _tabs(AppLocalizations l) {
    final labels = [l.tabServices, l.tabAbout, l.tabReviews];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.base)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == _tab ? Colors.white : null,
                    border: i == _tab ? Border.all(color: AppColors.primary, width: 1.5) : null,
                    borderRadius: BorderRadius.circular(7.25),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == _tab ? FontWeight.w600 : FontWeight.w500,
                      color: i == _tab ? AppColors.primary : AppColors.primaryMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ——— الخدمات ———
  List<Widget> _servicesTab(AppLocalizations l, ShopDetails shop) => [
        Text(l.servicesOf(shop.name), style: AppText.headline),
        const SizedBox(height: 8),
        if (shop.services.isEmpty) Text(l.noServices, style: AppText.body),
        for (final (i, s) in shop.services.indexed) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                      const SizedBox(height: 2),
                      Text(l.minutes(s.durationMinutes), style: AppText.body),
                    ],
                  ),
                ),
                Text(formatPrice(l, s), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text)),
                const SizedBox(width: 12),
                _addButton(l, s),
              ],
            ),
          ),
        ],
      ];

  Widget _addButton(AppLocalizations l, Service s) {
    final on = _selected.contains(s.id);
    return Tooltip(
      message: on ? l.removeService : l.pickService,
      child: Material(
        color: on ? AppColors.accent : AppColors.primary,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => on ? _selected.remove(s.id) : _selected.add(s.id)),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(on ? Icons.check : Icons.add, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  // ——— عن المحل ———
  List<Widget> _aboutTab(AppLocalizations l, ShopDetails shop) {
    final address = [shop.district, shop.area, shop.street, shop.landmark].whereType<String>().where((s) => s.isNotEmpty);
    return [
      if (shop.description != null && shop.description!.isNotEmpty) ...[
        Text(shop.description!, style: AppText.body.copyWith(height: 1.7)),
        const SizedBox(height: 20),
      ],
      Text(l.shopHours, style: AppText.headline),
      const SizedBox(height: 8),
      for (final t in shop.temporarySchedules)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l.temporarySchedule(t.name, t.fromDate, t.toDate),
              style: const TextStyle(fontSize: 13, color: AppColors.warning)),
        ),
      // الأسبوع في العراق يبدأ السبت
      for (final day in const [6, 0, 1, 2, 3, 4, 5]) _hoursRow(l, day, shop.weeklyHours),
      if (address.isNotEmpty || shop.latitude != null) ...[
        const SizedBox(height: 20),
        Text(l.shopLocation, style: AppText.headline),
        const SizedBox(height: 8),
        if (address.isNotEmpty) Text(address.join('، '), style: AppText.body.copyWith(height: 1.6)),
        if (shop.latitude != null && shop.longitude != null) ...[
          const SizedBox(height: 10),
          LocationPreview(latitude: shop.latitude!, longitude: shop.longitude!, label: shop.name),
        ],
      ],
    ];
  }

  Widget _hoursRow(AppLocalizations l, int day, List<WorkingPeriod> hours) {
    final periods = hours.where((h) => h.dayOfWeek == day).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(dayName(l, day), style: AppText.body)),
          Expanded(
            child: Text(
              periods.isEmpty
                  ? l.dayOff
                  : periods.map((p) => '${formatClock(l, p.from)} – ${formatClock(l, p.to)}').join('   '),
              style: TextStyle(fontSize: 14, color: periods.isEmpty ? AppColors.textDisabled : AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  // ——— التقييمات ———
  List<Widget> _reviewsTab(AppLocalizations l, ShopDetails shop) => [
        if (shop.reviews.isEmpty) Text(l.noReviewsYet, style: AppText.body),
        for (final (i, r) in shop.reviews.indexed) ...[
          if (i > 0) const Divider(height: 28, color: AppColors.border),
          Text(r.customerName ?? l.anonymousCustomer,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 4),
          Row(children: [
            StarRow(stars: r.stars, size: 18),
            const SizedBox(width: 6),
            Text('(${r.stars}.0)', style: const TextStyle(fontSize: 14, color: AppColors.primary)),
          ]),
          if (r.comment != null) ...[
            const SizedBox(height: 6),
            Text(r.comment!, style: AppText.body.copyWith(height: 1.6)),
          ],
        ],
      ];

  Widget _badge(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
        ]),
      );
}
