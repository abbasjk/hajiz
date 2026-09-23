import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/colors.dart';
import '../util/errors.dart';
import '../util/format.dart';

/// شريط واضح أعلى الشاشة عند انقطاع الاتصال
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.offline, required this.child});
  final ValueNotifier<bool> offline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: offline,
          builder: (context, isOffline, _) => AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: isOffline
                ? Material(
                    color: AppColors.text,
                    child: SafeArea(
                      bottom: false,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context).offlineBanner,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: offline.value, child: child)),
      ],
    );
  }
}

/// حالة تحميل أو خطأ مع زر إعادة المحاولة
class LoadState extends StatelessWidget {
  const LoadState({super.key, this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage(l, error!), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            if (onRetry != null) OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}

/// شريط خطوات الحجز الثلاث؛ يُعكس تلقائياً مع اتجاه النص
class BookingSteps extends StatelessWidget {
  const BookingSteps({super.key, required this.current});
  final int current; // 1..3

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = [l.stepServices, l.stepTime, l.stepReview];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < current ? AppColors.primary : AppColors.track,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: i < current ? AppColors.primary : AppColors.textMuted,
                      fontWeight: i == current - 1 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// العداد التنازلي بتوقيت الخادم
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.until, required this.now, this.style, this.onDone});
  final DateTime until;
  final DateTime Function() now;
  final TextStyle? style;
  final VoidCallback? onDone;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  late Timer _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_done && widget.until.difference(widget.now()).isNegative) {
        _done = true;
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // الأرقام نفسها لا تُعكس
    return Text(
      formatCountdown(widget.until.difference(widget.now())),
      textDirection: TextDirection.ltr,
      style: widget.style,
    );
  }
}

String statusLabel(AppLocalizations l, BookingStatus s) => switch (s) {
      BookingStatus.pendingShop => l.statusPendingShop,
      BookingStatus.pendingCustomer => l.statusPendingCustomer,
      BookingStatus.confirmed => l.statusConfirmed,
      BookingStatus.rejected => l.statusRejected,
      BookingStatus.cancelledByCustomer => l.statusCancelledByCustomer,
      BookingStatus.cancelledByShop => l.statusCancelledByShop,
      BookingStatus.expired => l.statusExpired,
      BookingStatus.completed => l.statusCompleted,
      BookingStatus.noShow => l.statusNoShow,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      BookingStatus.confirmed || BookingStatus.completed => (AppColors.primarySoft, AppColors.primaryDark),
      BookingStatus.pendingShop || BookingStatus.pendingCustomer => (AppColors.warningSoft, AppColors.warning),
      _ => (AppColors.disabledFill, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(AppLocalizations.of(context), status),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// شريط سفلي ثابت فيه ملخص وزر
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: child)),
    );
  }
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorMessage(AppLocalizations.of(context), error))));
}
