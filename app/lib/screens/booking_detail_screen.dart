import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../util/reasons.dart';
import '../widgets/common.dart';
import 'shop_screen.dart';

/// تفاصيل الحجز، والرد على تعديل المحل، والإلغاء.
class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, this.initial});
  final int bookingId;
  final Booking? initial;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Booking? _booking;
  Object? _error;
  int? _chosen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final b = await AppScope.of(context).api.booking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = b;
        _error = null;
        final available = b.proposedTimes.where((t) => t.available);
        if (_chosen == null || !available.any((t) => t.id == _chosen)) _chosen = available.firstOrNull?.id;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// لا حجز ولا إلغاء دون اتصال؛ ومفتاح فريد يمنع التكرار عند الضغط مرتين
  Future<void> _run(Future<Booking> Function(String key) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b = await action(newIdempotencyKey());
      if (mounted) setState(() => _booking = b);
    } catch (e) {
      if (mounted) showError(context, e);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.keepBooking)),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: Text(yes),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _cancel(Booking b) async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final freeCancel = Duration(hours: b.shop.freeCancelHours);
    final late = b.status == BookingStatus.confirmed && b.startsAt.difference(services.client.serverNow) < freeCancel;
    final ok = await _confirm(
      l.cancelConfirmTitle,
      late ? l.cancelLateWarning(formatDuration(l, b.shop.freeCancelHours * 60)) : l.cancelFree,
      l.confirmCancel,
    );
    if (ok) await _run((key) => services.api.cancel(b.id, key));
  }

  Future<void> _decline(Booking b) async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    if (await _confirm(l.declineConfirmTitle, l.declineConfirmBody, l.declineAndCancel)) {
      await _run((key) => services.api.decline(b.id, key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final b = _booking;
    return Scaffold(
      appBar: AppBar(title: Text(b == null ? '' : statusLabel(l, b.status))),
      body: b == null
          ? LoadState(error: _error, onRetry: _load)
          : RefreshIndicator(onRefresh: _load, child: _body(l, b)),
      bottomNavigationBar: b == null ? null : _actions(l, b),
    );
  }

  Widget _body(AppLocalizations l, Booking b) {
    final client = AppScope.of(context).client;
    final waiting = b.status.isPending && b.responseDeadline != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (waiting)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(b.status == BookingStatus.pendingShop ? l.shopRespondsIn : l.deadlineIn,
                      style: const TextStyle(fontSize: 13, color: AppColors.warning)),
                ),
                Countdown(
                  until: b.responseDeadline!,
                  now: () => client.serverNow,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.warning),
                  onDone: _load,
                ),
              ],
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(b.shop.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  StatusChip(status: b.status),
                ]),
                const SizedBox(height: 8),
                Text(
                  b.status == BookingStatus.pendingCustomer
                      ? '${l.originalRequest} ${formatAppointment(l, b.startsAt)}'
                      : formatAppointment(l, b.startsAt),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: b.status == BookingStatus.pendingCustomer ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${b.services.map((s) => s.name).join('، ')} · ${l.minutes(b.durationMinutes)}',
                    style: const TextStyle(color: AppColors.textMuted)),
                if (b.services.isNotEmpty) Text(formatTotal(l, b.services), style: const TextStyle(color: AppColors.textMuted)),
                if (b.note != null) ...[
                  const SizedBox(height: 8),
                  Text(l.yourNote(b.note!), style: const TextStyle(fontSize: 13)),
                ],
                if (b.cancelReason != null) ...[
                  const SizedBox(height: 8),
                  Text(l.reasonLabel(reasonText(l, b.cancelReason!)), style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                ],
                if (b.status == BookingStatus.expired) ...[
                  const SizedBox(height: 8),
                  Text(l.expiredHint, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (b.shop.phone != null) ...[
                    OutlinedButton.icon(onPressed: () => callPhone(b.shop.phone!), icon: const Icon(Icons.call_outlined), label: Text(l.call)),
                    OutlinedButton.icon(onPressed: () => openWhatsApp(b.shop.phone!), icon: const Icon(Icons.chat_outlined), label: Text(l.whatsapp)),
                  ],
                  if (b.shop.latitude != null && b.shop.longitude != null)
                    OutlinedButton.icon(
                      onPressed: () => openInMaps(b.shop.latitude!, b.shop.longitude!, b.shop.name),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l.openInMaps),
                    ),
                ]),
              ],
            ),
          ),
        ),
        if (b.status == BookingStatus.pendingCustomer) ..._proposal(l, b),
      ],
    );
  }

  List<Widget> _proposal(AppLocalizations l, Booking b) => [
        if (b.modificationMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(l.shopMessage(b.modificationMessage!), style: const TextStyle(height: 1.6)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(l.chooseProposed, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        RadioGroup<int>(
          groupValue: _chosen,
          onChanged: (v) => setState(() => _chosen = v),
          child: Column(
            children: [
              for (final t in b.proposedTimes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: t.available ? AppColors.surface : AppColors.disabledFill,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _chosen == t.id ? AppColors.primary : AppColors.border, width: _chosen == t.id ? 2 : 1),
                    ),
                    child: RadioListTile<int>(
                      value: t.id,
                      enabled: t.available,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      title: Text(
                        formatAppointment(l, t.startsAt),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: t.available ? AppColors.text : AppColors.textDisabled,
                          decoration: t.available ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      secondary: t.available
                          ? null
                          : Text(l.noLongerAvailable, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(l.proposalExpiryHint, style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textMuted)),
      ];

  Widget? _actions(AppLocalizations l, Booking b) {
    final api = AppScope.of(context).api;
    final now = AppScope.of(context).client.serverNow;
    if (b.status == BookingStatus.pendingCustomer) {
      return BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy || _chosen == null ? null : () => _run((key) => api.choose(b.id, _chosen!, key)),
              child: Text(l.confirmChosenTime),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(44)),
              onPressed: _busy ? null : () => _decline(b),
              child: Text(l.declineAndCancel),
            ),
          ],
        ),
      );
    }
    final cancellable = (b.status == BookingStatus.pendingShop || b.status == BookingStatus.confirmed) && b.startsAt.isAfter(now);
    if (!cancellable) return null;
    return BottomActionBar(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: _busy ? null : () => _cancel(b),
        child: Text(l.cancelBooking),
      ),
    );
  }
}
