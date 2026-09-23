import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../register_screen.dart';
import 'manage_screens.dart';
import 'owner_booking_screen.dart';
import 'setup_wizard.dart';

/// تبويب "محلي": الشخص نفسه قد يكون زبوناً وصاحب محل.
/// يعرض طلب فتح المحل أو حالته، ولوحة المحل بعد القبول.
class OwnerTab extends StatefulWidget {
  const OwnerTab({super.key});

  @override
  State<OwnerTab> createState() => OwnerTabState();
}

class OwnerTabState extends State<OwnerTab> {
  OwnerShopState? _state;
  ServerConfig? _config;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  Future<void> refresh() async {
    final services = AppScope.of(context);
    if (!services.session.isRegistered) return setState(() {});
    try {
      // الإعدادات والقوائم تُجلب من جديد: المناطق المضافة حديثاً تظهر دون إعادة تشغيل التطبيق
      final results = await Future.wait([services.owner.shop(), services.config(refresh: true)]);
      if (!mounted) return;
      setState(() {
        _state = results[0] as OwnerShopState;
        _config = results[1] as ServerConfig;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openWizard() async {
    final result = await Navigator.of(context).push<OwnerShopState>(
      MaterialPageRoute(builder: (_) => SetupWizard(initial: _state!, config: _config!)),
    );
    if (result != null && mounted) setState(() => _state = result);
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final registered = AppScope.of(context).session.isRegistered;
    if (!registered) {
      return Scaffold(
        appBar: AppBar(title: Text(l.yourShop)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _intro(l),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: RegisterForm(onRegistered: refresh))),
        ]),
      );
    }
    final error = _error;
    if (error is ApiException && error.code == 'untrusted_device') {
      return Scaffold(
        appBar: AppBar(title: Text(l.yourShop)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.phonelink_lock_outlined, color: AppColors.warning, size: 32),
                const SizedBox(height: 8),
                Text(l.untrustedDeviceTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(l.untrustedDeviceBody, style: const TextStyle(height: 1.6, color: AppColors.textMuted)),
              ]),
            ),
          ),
        ]),
      );
    }
    final state = _state;
    if (state == null) {
      return Scaffold(appBar: AppBar(title: Text(l.yourShop)), body: LoadState(error: _error, onRetry: refresh));
    }
    final shop = state.shop;
    return Scaffold(
      appBar: AppBar(title: Text(shop?.name ?? l.yourShop)),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (shop == null || shop.status == ShopStatus.draft) ...[
            _intro(l),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _openWizard,
              child: Text(shop == null ? l.startApplication : l.continueApplication),
            ),
          ] else if (shop.status == ShopStatus.approved)
            _approvedCard(l)
          else
            _statusCard(l, shop),
          if (shop != null && shop.status == ShopStatus.underReview) ...[
            const SizedBox(height: 16),
            ManageMenu(shop: shop, config: _config!, onShopChanged: (s) => setState(() => _state = s), calendar: false),
          ],
        ]),
      ),
    );
  }

  Widget _approvedCard(AppLocalizations l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [Icon(Icons.check_circle_outline, color: AppColors.primary)]),
            const SizedBox(height: 8),
            Text(l.shopApprovedTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                AppScope.of(context).switchMode(AppMode.shop);
              },
              icon: const Icon(Icons.swap_horiz),
              label: Text(l.switchToShop),
            ),
          ]),
        ),
      );

  Widget _intro(AppLocalizations l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.storefront_outlined, size: 48, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(l.openShopTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(l.openShopBody, style: const TextStyle(color: AppColors.textMuted, height: 1.6)),
      ]);

  Widget _statusCard(AppLocalizations l, OwnerShop shop) {
    final (icon, title, body, color) = switch (shop.status) {
      ShopStatus.underReview => (Icons.hourglass_top, l.underReviewTitle, l.underReviewBody, AppColors.warning),
      ShopStatus.rejected => (Icons.error_outline, l.rejectedTitle, l.rejectedBody, AppColors.danger),
      _ => (Icons.block, l.suspendedTitle, l.suspendedBody, AppColors.danger),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          ]),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.6)),
          if (shop.reviewNote != null) ...[
            const SizedBox(height: 8),
            Text(l.reviewNote(shop.reviewNote!), style: const TextStyle(color: AppColors.textMuted)),
          ],
          if (shop.status == ShopStatus.rejected) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: _openWizard, child: Text(l.editApplication)),
          ],
        ]),
      ),
    );
  }
}

/// لوحة المحل: طلبات تنتظر الرد مع العداد وزر قبول سريع، ثم حجوزات اليوم.
/// تتحدث كل 30 ثانية ما دامت ظاهرة (الإشعارات تأتي في المرحلة 5).
class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key, required this.shop, required this.config, required this.onShopChanged});
  final OwnerShop shop;
  final ServerConfig config;
  final ValueChanged<OwnerShopState> onShopChanged;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  List<OwnerBooking>? _pending;
  List<OwnerBooking>? _today;
  Object? _error;
  Timer? _poll;
  final _accepting = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await AppScope.of(context).owner.dashboard();
      if (mounted) {
        setState(() {
          _pending = d.pending;
          _today = d.today;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _accept(OwnerBooking b) async {
    final l = AppLocalizations.of(context);
    setState(() => _accepting.add(b.id));
    try {
      await AppScope.of(context).owner.accept(b.id, newIdempotencyKey());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.bookingAccepted)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _accepting.remove(b.id));
    await _load();
  }

  Future<void> _open(OwnerBooking b) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OwnerBookingScreen(bookingId: b.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = AppScope.of(context).client.serverNow;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        actions: [
          TextButton.icon(
            onPressed: () => AppScope.of(context).switchMode(AppMode.customer),
            icon: const Icon(Icons.swap_horiz),
            label: Text(l.customerModeShort),
          ),
        ],
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDayLong(l, now), style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
          Text(widget.shop.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          if (_pending == null)
            SizedBox(height: 200, child: LoadState(error: _error, onRetry: _load))
          else ...[
            _header(l.pendingRequests, badge: _pending!.length),
            if (_pending!.isEmpty) _empty(l.noPending),
            for (final b in _pending!) _requestCard(l, b),
            const SizedBox(height: 12),
            _header(l.todayBookings, trailing: l.bookingsCount(_today!.length)),
            if (_today!.isEmpty) _empty(l.noBookingsDay) else DayBookingsList(bookings: _today!, onOpen: _open),
          ],
        ]),
      ),
    );
  }

  Widget _header(String title, {int? badge, String? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          if (badge != null && badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
              child: Text('$badge', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ]),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: const TextStyle(color: AppColors.textMuted)),
      );

  Widget _requestCard(AppLocalizations l, OwnerBooking b) {
    final client = AppScope.of(context).client;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(b.customer.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              if (b.customer.newDevice)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.disabledFill, borderRadius: BorderRadius.circular(8)),
                  child: Text(l.newDeviceBadge, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              if (b.responseDeadline != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(8)),
                  child: Countdown(
                    until: b.responseDeadline!,
                    now: () => client.serverNow,
                    onDone: _load,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warning),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text('${b.services.map((s) => s.name).join('، ')} · ${formatDayShort(l, b.startsAt)} ${formatTime(l, b.startsAt)}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            if (b.note != null) ...[
              const SizedBox(height: 4),
              Text('«${b.note!}»', style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: _accepting.contains(b.id) ? null : () => _accept(b),
                  child: Text(l.acceptLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () => _open(b),
                  child: Text(l.detailsLabel),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// حجوزات يوم واحد في جدول زمني: الوقت، الزبون، الخدمات، الحالة
class DayBookingsList extends StatelessWidget {
  const DayBookingsList({super.key, required this.bookings, required this.onOpen});
  final List<OwnerBooking> bookings;
  final ValueChanged<OwnerBooking> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = AppScope.of(context).client.serverNow;
    final next = bookings.where((b) => b.status == BookingStatus.confirmed && b.endsAt.isAfter(now)).firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final b in bookings) ...[
          if (b != bookings.first) const Divider(height: 1),
          Material(
            color: b == next ? AppColors.primarySoft : Colors.transparent,
            child: InkWell(
              onTap: () => onOpen(b),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  SizedBox(
                    width: 76,
                    child: Text(formatTime(l, b.startsAt),
                        style: TextStyle(fontWeight: FontWeight.w700, color: b.endsAt.isBefore(now) ? AppColors.textDisabled : AppColors.text)),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(b.services.map((s) => s.name).join('، '), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                  if (b == next)
                    Text(l.upcomingLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDark))
                  else
                    StatusChip(status: b.status, owner: true),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
