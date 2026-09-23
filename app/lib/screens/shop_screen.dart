import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_services_screen.dart';

/// "افتح في الخرائط": ينتقل لتطبيق الخرائط في الهاتف
Future<void> openInMaps(double lat, double lng, String label) async {
  final Uri uri;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label)})');
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    uri = Uri.https('maps.apple.com', '/', {'q': label, 'll': '$lat,$lng'});
  } else {
    uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) => launchUrl(Uri(scheme: 'tel', path: phone));

/// واتساب يحتاج الرقم الدولي: 07701234567 → 9647701234567
Future<void> openWhatsApp(String phone) =>
    launchUrl(Uri.https('wa.me', '/964${phone.replaceFirst(RegExp('^0'), '')}'), mode: LaunchMode.externalApplication);

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.shopId});
  final int shopId;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ShopDetails? _shop;
  Object? _error;

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shop = _shop;
    return Scaffold(
      appBar: AppBar(title: Text(shop?.name ?? '')),
      body: shop == null ? LoadState(error: _error, onRetry: _load) : _body(l, shop),
      bottomNavigationBar: shop == null || shop.services.isEmpty
          ? null
          : BottomActionBar(
              child: FilledButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => BookingServicesScreen(shop: shop))),
                child: Text(l.bookAppointment),
              ),
            ),
    );
  }

  Widget _body(AppLocalizations l, ShopDetails shop) {
    final address = [shop.district, shop.area, shop.street, shop.landmark].whereType<String>().where((s) => s.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (shop.photos.isNotEmpty)
          SizedBox(
            height: 200,
            child: PageView(
              children: [
                for (final url in shop.photos)
                  Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: AppColors.primarySoft)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shop.businessType != null)
                Text(shop.businessType!, style: const TextStyle(color: AppColors.textMuted)),
              if (shop.committed || shop.instantBooking) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  if (shop.committed) _badge(Icons.verified_outlined, l.committedBadge),
                  if (shop.instantBooking) _badge(Icons.bolt, l.instantBadge),
                ]),
              ],
              if (shop.description != null && shop.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(shop.description!, style: const TextStyle(height: 1.6)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (shop.phone != null) ...[
                    OutlinedButton.icon(onPressed: () => callPhone(shop.phone!), icon: const Icon(Icons.call_outlined), label: Text(l.call)),
                    OutlinedButton.icon(onPressed: () => openWhatsApp(shop.phone!), icon: const Icon(Icons.chat_outlined), label: Text(l.whatsapp)),
                  ],
                  if (shop.latitude != null && shop.longitude != null)
                    OutlinedButton.icon(
                      onPressed: () => openInMaps(shop.latitude!, shop.longitude!, shop.name),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l.openInMaps),
                    ),
                ],
              ),
            ],
          ),
        ),
        _section(l.shopServices, [
          if (shop.services.isEmpty) Text(l.noServices, style: const TextStyle(color: AppColors.textMuted)),
          for (final s in shop.services)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(l.minutes(s.durationMinutes), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Text(formatPrice(l, s), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ]),
        _section(l.shopHours, [
          for (final t in shop.temporarySchedules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.temporarySchedule(t.name, t.fromDate, t.toDate),
                  style: const TextStyle(fontSize: 13, color: AppColors.warning)),
            ),
          // الأسبوع في العراق يبدأ السبت
          for (final day in const [6, 0, 1, 2, 3, 4, 5]) _hoursRow(l, day, shop.weeklyHours),
        ]),
        if (address.isNotEmpty) _section(l.shopLocation, [Text(address.join('، '))]),
      ],
    );
  }

  Widget _hoursRow(AppLocalizations l, int day, List<WorkingPeriod> hours) {
    final periods = hours.where((h) => h.dayOfWeek == day).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(dayName(l, day), style: const TextStyle(color: AppColors.textMuted))),
          Expanded(
            child: Text(
              periods.isEmpty
                  ? l.dayOff
                  : periods.map((p) => '${formatClock(l, p.from)} – ${formatClock(l, p.to)}').join('   '),
              style: TextStyle(color: periods.isEmpty ? AppColors.textDisabled : AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _badge(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.primaryDark),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
        ]),
      );
}
