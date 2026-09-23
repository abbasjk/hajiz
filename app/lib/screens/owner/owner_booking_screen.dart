import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../util/reasons.dart';
import '../../widgets/common.dart';
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

class _OwnerBookingScreenState extends State<OwnerBookingScreen> {
  OwnerBooking? _booking;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

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
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (b.status == BookingStatus.pendingShop && b.responseDeadline != null)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.timer_outlined, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(child: Text(l.autoCancelIn, style: const TextStyle(fontSize: 13, color: AppColors.warning))),
            Countdown(
              until: b.responseDeadline!,
              now: () => client.serverNow,
              onDone: _load,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.warning),
            ),
          ]),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const CircleAvatar(backgroundColor: AppColors.disabledFill, child: Icon(Icons.person_outline, color: AppColors.textMuted)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  if (c.phone != null)
                    Text(c.phone!, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))
                  else
                    Text(l.phoneHidden, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
              StatusChip(status: b.status, owner: true),
            ]),
            if (c.phone != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(c.phone!), icon: const Icon(Icons.call_outlined), label: Text(l.call))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => openWhatsApp(c.phone!), icon: const Icon(Icons.chat_outlined), label: Text(l.whatsapp))),
              ]),
            ],
            if (c.stats != null) ...[
              const SizedBox(height: 12),
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
      ),
      if (c.newDevice) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.disabledFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.newDeviceTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(l.newDeviceBody, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.6)),
            const SizedBox(height: 10),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
              onPressed: _busy ? null : () => _run((key) => AppScope.of(context).owner.verifyDevice(b.id, key)),
              child: Text(l.verifiedByCall),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _row(l.reviewAppointment, formatAppointment(l, b.startsAt)),
            _row(l.reviewServices, b.services.map((s) => s.name).join('، ')),
            _row(l.reviewDuration, l.minutes(b.durationMinutes)),
            if (b.note != null) ...[
              const Divider(height: 20),
              Text(l.customerNote, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(b.note!),
            ],
            if (b.cancelReason != null) ...[
              const Divider(height: 20),
              Text(l.reasonLabel(reasonText(l, b.cancelReason!)), style: const TextStyle(color: AppColors.danger)),
            ],
            if (b.status == BookingStatus.pendingCustomer) ...[
              const Divider(height: 20),
              Text(l.awaitingCustomer, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final t in b.proposedTimes) Text('• ${formatAppointment(l, t)}'),
            ],
          ]),
        ),
      ),
    ]);
  }

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

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
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
