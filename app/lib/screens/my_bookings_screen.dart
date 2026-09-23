import 'package:flutter/material.dart';

import '../api/hajiz_api.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_detail_screen.dart';

/// حجوزاتي: قيد الانتظار، مؤكدة، سابقة؛ مع العداد التنازلي لأي طلب ينتظر رداً.
/// تبقى ظاهرة من آخر تحميل عند انقطاع الاتصال، مع وقت آخر تحديث.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => MyBookingsScreenState();
}

class MyBookingsScreenState extends State<MyBookingsScreen> {
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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.tabMyBookings),
          bottom: TabBar(
            labelColor: AppColors.primary,
            indicatorColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [Tab(text: l.pendingTab), Tab(text: l.confirmedTab), Tab(text: l.pastTab)],
          ),
        ),
        body: !registered
            ? Center(child: Text(l.notRegisteredYet, style: const TextStyle(color: AppColors.textMuted)))
            : bookings == null
                ? LoadState(error: _error, onRetry: refresh)
                : Column(
                    children: [
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
                            _list(l, bookings.where((b) => b.status.isPending).toList()
                              ..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
                            _list(l, bookings.where((b) => b.status == BookingStatus.confirmed).toList()
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
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _card(l, items[i]),
            ),
    );
  }

  Widget _card(AppLocalizations l, Booking b) {
    final client = AppScope.of(context).client;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: b.id, initial: b)));
          refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(b.shop.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                  StatusChip(status: b.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(formatAppointment(l, b.startsAt)),
              Text(b.services.map((s) => s.name).join('، '), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              if (b.status.isPending && b.responseDeadline != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(b.status == BookingStatus.pendingShop ? l.shopRespondsIn : l.deadlineIn,
                        style: const TextStyle(fontSize: 13, color: AppColors.warning)),
                    const SizedBox(width: 6),
                    Countdown(
                      until: b.responseDeadline!,
                      now: () => client.serverNow,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning),
                      onDone: refresh,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
