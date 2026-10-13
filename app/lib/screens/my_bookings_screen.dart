import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/hajiz_api.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/refresh_on_push.dart';
import 'booking_detail_screen.dart';
import 'home_screen.dart' show ShopImage;

/// حجوزاتي: قيد الانتظار، مؤكدة، سابقة؛ مع العداد التنازلي لأي طلب ينتظر رداً.
/// تبقى ظاهرة من آخر تحميل عند انقطاع الاتصال، مع وقت آخر تحديث.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => MyBookingsScreenState();
}

class MyBookingsScreenState extends State<MyBookingsScreen> with RefreshOnPush {
  List<Booking>? _bookings;
  DateTime? _updatedAt;
  bool _fromCache = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cached = AppScope.of(context).session.cachedBookings;
      if (cached != null) {
        setState(() {
          _bookings = HajizApi.parseBookings(cached.json);
          _updatedAt = cached.at;
          _fromCache = true;
        });
      }
      refresh();
    });
  }

  @override
  void onPush() => refresh();

  Future<void> refresh() async {
    final services = AppScope.of(context);
    if (!services.session.isRegistered) return setState(() {});
    try {
      final r = await services.api.myBookings();
      await services.session.cacheBookings(r.raw);
      if (mounted) {
        setState(() {
          _bookings = r.bookings;
          _updatedAt = DateTime.now();
          _fromCache = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final registered = AppScope.of(context).session.isRegistered;
    final bookings = _bookings;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.tabMyBookings, style: AppText.headline.copyWith(color: Colors.white)),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: !registered
            ? Center(child: Text(l.notRegisteredYet, style: const TextStyle(color: AppColors.textMuted)))
            : bookings == null
                ? LoadState(error: _error, onRetry: refresh)
                : Column(
                    children: [
                      // مفتاح "الحالية / السابقة" كما في التصميم
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(24)),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppShadows.card,
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: AppColors.text,
                          unselectedLabelColor: AppColors.textMuted,
                          labelStyle: const TextStyle(fontFamily: appFont, fontSize: 16, fontWeight: FontWeight.w500),
                          tabs: [Tab(height: 40, text: l.activeTab), Tab(height: 40, text: l.pastTab)],
                        ),
                      ),
                      if (_fromCache || _error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l.lastUpdated('${formatDayShort(l, _updatedAt!)} ${formatTime(l, _updatedAt!)}'),
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _list(l, bookings.where((b) => b.status.isPending || b.status == BookingStatus.confirmed).toList()
                              ..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
                            _list(l, bookings.where((b) => !b.status.isPending && b.status != BookingStatus.confirmed).toList()),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _list(AppLocalizations l, List<Booking> items) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: items.isEmpty
          ? ListView(children: [
              const SizedBox(height: 120),
              Center(child: Text(l.noBookings, style: const TextStyle(color: AppColors.textMuted))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) => _card(l, items[i]),
            ),
    );
  }

  Widget _card(AppLocalizations l, Booking b) {
    final client = AppScope.of(context).client;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.base),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.base),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: b.id, initial: b)));
            refresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.base),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: ShopImage(url: b.shop.coverPhoto == null ? null : client.absoluteUrl(b.shop.coverPhoto!)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title),
                          const SizedBox(height: 4),
                          Text(formatAppointment(l, b.startsAt), style: const TextStyle(fontSize: 14, color: AppColors.inkMuted)),
                          const SizedBox(height: 2),
                          Text(b.services.map((s) => s.name).join('، '),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(status: b.status),
                  ],
                ),
                if (b.status.isPending && b.responseDeadline != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.base)),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b.status == BookingStatus.pendingShop ? l.shopRespondsIn : l.deadlineIn,
                              style: const TextStyle(fontSize: 13, color: AppColors.text)),
                        ),
                        Countdown(
                          until: b.responseDeadline!,
                          now: () => client.serverNow,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkMuted),
                          onDone: refresh,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
