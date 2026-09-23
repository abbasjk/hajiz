import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../state/push.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/refresh_on_push.dart';
import 'booking_detail_screen.dart';
import 'owner/owner_booking_screen.dart';

/// جرس الإشعارات مع عدد غير المقروء؛ audience: 'customer' أو 'shop'
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key, required this.audience});
  final String audience;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> with RefreshOnPush {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => onPush());
  }

  @override
  void onPush() {
    if (mounted) AppScope.of(context).refreshUnread(widget.audience);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    if (!services.session.isRegistered) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: services.unread[widget.audience]!,
      builder: (context, count, _) => IconButton(
        tooltip: l.notificationsTitle,
        icon: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: const Icon(Icons.notifications_outlined),
        ),
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(audience: widget.audience)));
          services.refreshUnread(widget.audience);
        },
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.audience});
  final String audience;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with RefreshOnPush {
  List<AppNotification>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void onPush() => _load();

  Future<void> _load() async {
    final services = AppScope.of(context);
    try {
      final r = await services.api.notifications(widget.audience);
      if (!mounted) return;
      setState(() => (_items = r.items, _error = null));
      // فتح القائمة يعني قراءتها؛ غير المقروء يبقى مميزاً في هذا العرض
      if (r.unread > 0) {
        await services.api.markNotificationsRead(widget.audience);
        services.unread[widget.audience]!.value = 0;
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(AppNotification n) {
    final id = n.bookingId;
    if (id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => widget.audience == 'shop' ? OwnerBookingScreen(bookingId: id) : BookingDetailScreen(bookingId: id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(l.notificationsTitle)),
      body: items == null
          ? LoadState(error: _error, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(child: Text(l.noNotifications, style: const TextStyle(color: AppColors.textMuted))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _tile(l, items[i]),
                    ),
            ),
    );
  }

  Widget _tile(AppLocalizations l, AppNotification n) {
    return ListTile(
      tileColor: n.read ? null : AppColors.primarySoft.withValues(alpha: 0.5),
      leading: CircleAvatar(
        backgroundColor: n.read ? AppColors.border : AppColors.primarySoft,
        child: Icon(_icon(n.type), color: AppColors.primary, size: 20),
      ),
      title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
      subtitle: Text(n.body, style: const TextStyle(height: 1.5)),
      trailing: Text(_ago(l, n.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      onTap: n.bookingId == null ? null : () => _open(n),
    );
  }

  String _ago(AppLocalizations l, DateTime at) {
    final minutes = AppScope.of(context).client.serverNow.difference(at).inMinutes;
    if (minutes < 1) return l.justNow;
    if (minutes < 60) return l.minutesAgo(minutes);
    if (minutes < 24 * 60) return l.hoursAgo(minutes ~/ 60);
    return formatDayShort(l, at);
  }

  static IconData _icon(String type) => switch (type) {
        'accepted' || 'customer_chose' || 'new_instant_booking' => Icons.event_available,
        'rejected' || 'shop_cancelled' || 'customer_cancelled' || 'customer_declined' => Icons.event_busy,
        'expired_shop' || 'expired_customer' || 'deadline_half' || 'deadline_final' || 'proposal_half' || 'proposal_final' =>
          Icons.timer_outlined,
        'proposal' || 'closure_proposal' => Icons.schedule,
        'morning_summary' => Icons.wb_sunny_outlined,
        'appointment_reminder' => Icons.alarm,
        _ => Icons.inbox_outlined,
      };
}

/// التذكيرات وملخص الصباح اختيارية؛ الإشعارات المهمة لا تُوقف
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.forShop = false});
  final bool forShop;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  NotificationSettings? _settings;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await AppScope.of(context).api.notificationSettings();
      if (mounted) setState(() => (_settings = s, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save({bool? reminders, bool? morningSummary}) async {
    try {
      final s = await AppScope.of(context).api.saveNotificationSettings(reminders: reminders, morningSummary: morningSummary);
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: Text(l.notificationSettingsTitle)),
      body: s == null
          ? LoadState(error: _error, onRetry: _load)
          : ListView(padding: const EdgeInsets.all(16), children: [
              PushOffBanner(forShop: widget.forShop),
              Card(
                child: SwitchListTile(
                  title: Text(l.notifyReminders, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(l.notifyRemindersHint),
                  value: s.reminders,
                  onChanged: (v) => _save(reminders: v),
                ),
              ),
              if (widget.forShop) ...[
                const SizedBox(height: 10),
                Card(
                  child: SwitchListTile(
                    title: Text(l.notifyMorningSummary, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(l.notifyMorningSummaryHint),
                    value: s.morningSummary,
                    onChanged: (v) => _save(morningSummary: v),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(l.notifyAlwaysOn, style: const TextStyle(color: AppColors.textMuted, height: 1.6)),
            ]),
    );
  }
}

/// تنبيه عندما أوقف المستخدم الإشعارات من إعدادات الهاتف؛ أهم لصاحب المحل لأن الطلبات تنتهي مهلتها
class PushOffBanner extends StatelessWidget {
  const PushOffBanner({super.key, required this.forShop});
  final bool forShop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    return ValueListenableBuilder<PushPermission>(
      valueListenable: services.pushPermission,
      builder: (context, permission, _) {
        if (permission != PushPermission.denied) return const SizedBox.shrink();
        return Card(
          color: AppColors.warningSoft,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.notifications_off_outlined, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(l.pushOffTitle, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              Text(forShop ? l.pushOffBody : l.pushOffCustomer, style: const TextStyle(height: 1.5)),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => unawaited(Geolocator.openAppSettings()),
                  child: Text(l.pushTurnOn),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
