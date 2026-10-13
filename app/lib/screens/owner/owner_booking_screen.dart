import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../util/reasons.dart';
import '../../widgets/common.dart';
import '../../widgets/refresh_on_push.dart';
import '../shop_screen.dart';
import 'propose_screen.dart';

/// تفاصيل الطلب لصاحب المحل: الزبون وسجل التزامه، تنبيه الجهاز الجديد،
/// ثم القبول أو الاقتراح أو الرفض؛ وبعد الموعد: اكتمل أو لم يحضر.
class OwnerBookingScreen extends StatefulWidget {
  const OwnerBookingScreen({super.key, required this.bookingId});
  final int bookingId;

  @override
  State<OwnerBookingScreen> createState() => _OwnerBookingScreenState();
}

class _OwnerBookingScreenState extends State<OwnerBookingScreen> with RefreshOnPush {
  OwnerBooking? _booking;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void onPush() => _load();

  Future<void> _load() async {
    try {
      final b = await AppScope.of(context).owner.booking(widget.bookingId);
      if (mounted) setState(() => (_booking = b, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<OwnerBooking> Function(String key) action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b = await action(newIdempotencyKey());
      if (!mounted) return;
      setState(() => _booking = b);
      if (done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) showError(context, e);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// قائمة أسباب قصيرة؛ عند الإلغاء يُعرض اقتراح وقت آخر بدل الإلغاء
  Future<void> _chooseReason({required bool cancel}) async {
    final l = AppLocalizations.of(context);
    final owner = AppScope.of(context).owner;
    final b = _booking!;
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(cancel ? l.cancelByShopTitle : l.rejectTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (cancel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.cancelInsteadHint, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => Navigator.pop(context, '__propose'), child: Text(l.proposeInstead)),
                const Divider(height: 24),
              ]),
            ),
          for (final code in cancel ? shopCancelReasons : rejectReasons)
            ListTile(title: Text(reasonText(l, code)), onTap: () => Navigator.pop(context, code)),
        ]),
      ),
    );
    if (reason == null || !mounted) return;
    if (reason == '__propose') return _propose();
    await _run((key) => cancel ? owner.cancel(b.id, reason, key) : owner.reject(b.id, reason, key));
  }

  Future<void> _propose() async {
    final l = AppLocalizations.of(context);
    final result = await Navigator.of(context).push<OwnerBooking>(
      MaterialPageRoute(builder: (_) => ProposeScreen(booking: _booking!)),
    );
    if (result != null && mounted) {
      setState(() => _booking = result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.proposalSent)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final b = _booking;
    return Scaffold(
      appBar: AppBar(title: Text(b?.status == BookingStatus.pendingShop ? l.newRequestTitle : l.ownerBookingTitle)),
      body: b == null ? LoadState(error: _error, onRetry: _load) : RefreshIndicator(onRefresh: _load, child: _body(l, b)),
      bottomNavigationBar: b == null ? null : _actions(l, b),
    );
  }

  Widget _body(AppLocalizations l, OwnerBooking b) {
    final client = AppScope.of(context).client;
    final c = b.customer;
    final now = client.serverNow;
    final inProgress = b.status == BookingStatus.confirmed && !now.isBefore(b.startsAt) && now.isBefore(b.endsAt);
    final progress = inProgress
        ? now.difference(b.startsAt).inSeconds / b.endsAt.difference(b.startsAt).inSeconds.clamp(1, 1 << 30)
        : null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      // بطاقة الموعد البنفسجية كما في "الخدمة بدأت" في التصميم
      Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.hero)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text(statusLabel(l, b.status, owner: true),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          const SizedBox(height: 12),
          Text('${formatTime(l, b.startsAt)} – ${formatTime(l, b.endsAt)}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${formatDayLong(l, b.startsAt)} · ${l.minutes(b.durationMinutes)}',
              style: const TextStyle(fontSize: 14, color: AppColors.onPrimaryMuted)),
          if (progress != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: AppColors.accent,
              ),
            ),
          ],
          if (b.status == BookingStatus.pendingShop && b.responseDeadline != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.timer_outlined, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(l.autoCancelIn, style: const TextStyle(fontSize: 13, color: Colors.white))),
              Countdown(
                until: b.responseDeadline!,
                now: () => client.serverNow,
                onDone: _load,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.base),
          boxShadow: AppShadows.card,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: const Icon(Icons.person_outline, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(customerName(l, c), style: AppText.headline),
                if (c.phone != null)
                  Text(c.phone!, textDirection: TextDirection.ltr, style: AppText.body)
                else
                  Text(l.phoneHidden, style: AppText.caption),
              ]),
            ),
            if (c.phone != null) ...[
              _circleAction(Icons.call, l.call, () => callPhone(c.phone!)),
              const SizedBox(width: 8),
              _circleAction(Icons.chat, l.whatsapp, () => openWhatsApp(c.phone!)),
            ],
          ]),
          if (c.stats != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              _stat(c.stats!.attended, l.statAttended, highlight: true),
              const SizedBox(width: 8),
              _stat(c.stats!.lateCancels, l.statLateCancel),
              const SizedBox(width: 8),
              _stat(c.stats!.noShows, l.statNoShow),
            ]),
          ],
        ]),
      ),
      if (c.newDevice) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppRadius.base),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.newDeviceTitle, style: AppText.title),
            const SizedBox(height: 4),
            Text(l.newDeviceBody, style: AppText.body.copyWith(height: 1.6)),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
              onPressed: _busy ? null : () => _run((key) => AppScope.of(context).owner.verifyDevice(b.id, key)),
              child: Text(l.verifiedByCall),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      _sectionTitle(Icons.content_cut, l.reviewServices),
      for (final s in b.services)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text(l.minutes(s.durationMinutes), style: AppText.body),
              ]),
            ),
            Text(formatPrice(l, s), style: const TextStyle(fontSize: 15, color: AppColors.inkMuted)),
          ]),
        ),
      if (b.note != null) ...[
        const SizedBox(height: 10),
        _sectionTitle(Icons.sticky_note_2_outlined, l.customerNote),
        Text(b.note!, style: const TextStyle(fontSize: 15, height: 1.6)),
      ],
      if (b.cancelReason != null) ...[
        const SizedBox(height: 16),
        Text(l.reasonLabel(reasonText(l, b.cancelReason!)), style: const TextStyle(color: AppColors.danger)),
      ],
      if (b.status == BookingStatus.pendingCustomer) ...[
        const SizedBox(height: 16),
        _sectionTitle(Icons.schedule, l.awaitingCustomer),
        for (final t in b.proposedTimes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('• ${formatAppointment(l, t)}', style: const TextStyle(fontSize: 15)),
          ),
      ],
    ]);
  }

  Widget _sectionTitle(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.text),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.headline)),
        ]),
      );

  Widget _circleAction(IconData icon, String label, VoidCallback onTap) => Tooltip(
        message: label,
        child: Material(
          color: AppColors.primarySoft,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, color: AppColors.primary, size: 20)),
          ),
        ),
      );

  Widget _stat(int n, String label, {bool highlight = false}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: highlight ? AppColors.primarySoft : AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: highlight ? AppColors.primaryDark : null)),
            Text(label, style: TextStyle(fontSize: 12, color: highlight ? AppColors.primaryDark : AppColors.textMuted)),
          ]),
        ),
      );

  Widget? _actions(AppLocalizations l, OwnerBooking b) {
    final owner = AppScope.of(context).owner;
    final now = AppScope.of(context).client.serverNow;
    final started = !now.isBefore(b.startsAt);
    if (b.status == BookingStatus.pendingShop) {
      return BottomActionBar(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : () => _run((key) => owner.accept(b.id, key), done: l.bookingAccepted),
            child: Text(l.acceptBooking),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _propose, child: Text(l.proposeAlternatives))),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(44)),
                onPressed: _busy ? null : () => _chooseReason(cancel: false),
                child: Text(l.rejectWithReason),
              ),
            ),
          ]),
        ]),
      );
    }
    if (b.status == BookingStatus.confirmed && started) {
      // لا يُسجل الغياب إلا بعد مرور وقت الموعد
      return BottomActionBar(
        child: Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _run((key) => owner.complete(b.id, key)),
              child: Text(l.markCompleted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _busy ? null : () => _run((key) => owner.noShow(b.id, key)),
              child: Text(l.markNoShow),
            ),
          ),
        ]),
      );
    }
    if ((b.status == BookingStatus.confirmed || b.status == BookingStatus.pendingCustomer) && !started) {
      return BottomActionBar(
        child: Row(children: [
          if (b.status == BookingStatus.confirmed) ...[
            Expanded(child: OutlinedButton(onPressed: _busy ? null : _propose, child: Text(l.proposeInstead))),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(44)),
              onPressed: _busy ? null : () => _chooseReason(cancel: true),
              child: Text(l.cancelAnyway),
            ),
          ),
        ]),
      );
    }
    return null;
  }
}
