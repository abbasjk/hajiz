import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/refresh_on_push.dart';
import '../../widgets/untrusted_device_card.dart';
import '../notifications_screen.dart';
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
        body: ListView(padding: const EdgeInsets.all(16), children: const [
          UntrustedDeviceCard(forShop: true),
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

class _OwnerDashboardState extends State<OwnerDashboard> with RefreshOnPush {
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

  @override
  void onPush() => _load();

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
    final remaining = _today?.where((b) => b.status == BookingStatus.confirmed && b.endsAt.isAfter(now)).length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        actions: [
          const NotificationsBell(audience: 'shop', onDark: true),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => AppScope.of(context).switchMode(AppMode.customer),
            icon: const Icon(Icons.swap_horiz),
            label: Text(l.customerModeShort),
          ),
        ],
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatDayLong(l, now), style: const TextStyle(fontSize: 13, color: AppColors.onPrimaryMuted, fontWeight: FontWeight.w400)),
          Text(widget.shop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          const PushOffBanner(forShop: true),
          // بطاقات الأرقام كما في لوحة صاحب العمل في التصميم
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.75,
            children: [
              _stat('${_pending?.length ?? '–'}', l.statPending, Icons.hourglass_top_rounded),
              _stat('${_today?.length ?? '–'}', l.statToday, Icons.event_note_outlined),
              _stat('${remaining ?? '–'}', l.statRemaining, Icons.schedule),
              _stat('${widget.shop.services.length}', l.statServices, Icons.content_cut),
            ],
          ),
          const SizedBox(height: 20),
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

  Widget _stat(String value, String label, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.base),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primaryBright)),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
          ],
        ),
      );

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
              Expanded(child: Text(customerName(l, b.customer), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
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

  /// لون كل حالة: الحافة الجانبية والخلفية الفاتحة، كما في تقويم التصميم
  static (Color, Color) colors(BookingStatus s) => switch (s) {
        BookingStatus.pendingShop || BookingStatus.pendingCustomer => (AppColors.accent, const Color(0xFFFEF0E2)),
        BookingStatus.confirmed => (AppColors.primary, AppColors.primarySoft),
        BookingStatus.completed => (const Color(0xFF27AE60), const Color(0xFFDDF3E6)),
        BookingStatus.noShow => (AppColors.textMuted, AppColors.fill),
        _ => (AppColors.danger, AppColors.dangerSoft),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = AppScope.of(context).client.serverNow;
    final next = bookings.where((b) => b.status == BookingStatus.confirmed && b.endsAt.isAfter(now)).firstOrNull;
    return Column(children: [
      for (final b in bookings)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 72,
                child: Column(children: [
                  Text(formatTime(l, b.startsAt),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: b.endsAt.isBefore(now) ? AppColors.textDisabled : AppColors.text,
                      )),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Container(width: 3, decoration: BoxDecoration(
                      color: colors(b.status).$1.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    )),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: colors(b.status).$2,
                  borderRadius: BorderRadius.circular(AppRadius.base),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onOpen(b),
                    child: Container(
                      decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: colors(b.status).$1, width: 5))),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(customerName(l, b.customer),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                          ),
                          if (b == next)
                            Text(l.upcomingLabel,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary))
                          else
                            StatusChip(status: b.status, owner: true),
                        ]),
                        const SizedBox(height: 4),
                        Text(b.services.map((s) => s.name).join('، '), style: AppText.body),
                        if (b.services.isNotEmpty)
                          Text(formatTotal(l, b.services), style: AppText.body),
                        if (b.note != null)
                          Text('«${b.note!}»', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
