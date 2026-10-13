import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../util/reasons.dart';
import '../widgets/common.dart';
import '../widgets/location_preview.dart';
import '../widgets/refresh_on_push.dart';
import 'home_screen.dart' show ShopImage;
import 'shop_screen.dart';

/// تفاصيل الحجز، والرد على تعديل المحل، والإلغاء.
class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, this.initial});
  final int bookingId;
  final Booking? initial;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> with RefreshOnPush {
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

  @override
  void onPush() => _load();

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
    final stage = switch (b.status) {
      BookingStatus.pendingShop || BookingStatus.pendingCustomer => 1,
      BookingStatus.confirmed => 2,
      BookingStatus.completed => 3,
      _ => null,
    };
    final waiting = b.status.isPending && b.responseDeadline != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (stage != null) BookingStages(current: stage) else _endedBanner(l, b),
        const SizedBox(height: 20),
        _shopCard(l, b),
        if (waiting || b.status == BookingStatus.confirmed) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(AppRadius.base)),
            child: Row(
              children: [
                Icon(waiting ? Icons.timer : Icons.schedule, color: AppColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    waiting ? (b.status == BookingStatus.pendingShop ? l.shopRespondsIn : l.deadlineIn) : l.appointmentLength,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                ),
                if (waiting)
                  Countdown(
                    until: b.responseDeadline!,
                    now: () => client.serverNow,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                    onDone: _load,
                  )
                else
                  Text(l.minutes(b.durationMinutes), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _sectionTitle(Icons.calendar_month, l.reviewAppointment),
        Text(
          b.status == BookingStatus.pendingCustomer
              ? '${l.originalRequest} ${formatAppointment(l, b.startsAt)}'
              : formatAppointment(l, b.startsAt),
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textMuted,
            decoration: b.status == BookingStatus.pendingCustomer ? TextDecoration.lineThrough : null,
          ),
        ),
        if (b.status == BookingStatus.pendingCustomer) ..._proposal(l, b),
        const SizedBox(height: 24),
        _sectionTitle(Icons.content_cut, l.reviewServices),
        for (final s in b.services)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                      Text(l.minutes(s.durationMinutes), style: AppText.body),
                    ],
                  ),
                ),
                Text(formatPrice(l, s), style: const TextStyle(fontSize: 16, color: AppColors.inkMuted)),
              ],
            ),
          ),
        if (b.services.length > 1)
          Row(children: [
            Expanded(child: Text(l.reviewTotal, style: AppText.title)),
            Text(formatTotal(l, b.services), style: AppText.title),
          ]),
        if (b.note != null) ...[
          const SizedBox(height: 16),
          Text(l.yourNote(b.note!), style: AppText.body.copyWith(height: 1.6)),
        ],
        // يوم الموعد هو وقت الحاجة للطريق
        if ((b.status == BookingStatus.confirmed || b.status == BookingStatus.pendingShop) &&
            b.shop.latitude != null && b.shop.longitude != null) ...[
          const SizedBox(height: 24),
          _sectionTitle(Icons.location_on, l.shopLocation),
          LocationPreview(latitude: b.shop.latitude!, longitude: b.shop.longitude!, label: b.shop.name),
        ],
        if (b.review != null) ...[
          const SizedBox(height: 24),
          _sectionTitle(Icons.star_rounded, l.yourReview),
          Row(children: [
            StarRow(stars: b.review!.stars, size: 18),
            const SizedBox(width: 6),
            Text('(${b.review!.stars}.0)', style: const TextStyle(fontSize: 14, color: AppColors.primary)),
          ]),
          if (b.review!.comment != null) ...[
            const SizedBox(height: 6),
            Text(b.review!.comment!, style: AppText.body.copyWith(height: 1.6)),
          ],
        ],
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 22, color: AppColors.text),
          const SizedBox(width: 8),
          Text(text, style: AppText.headline),
        ]),
      );

  /// الحجز انتهى دون إتمام: مرفوض، ملغى، انتهت مهلته، أو لم يحضر
  Widget _endedBanner(AppLocalizations l, Booking b) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(AppRadius.base)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.event_busy, color: AppColors.danger, size: 22),
              const SizedBox(width: 8),
              Text(statusLabel(l, b.status), style: AppText.title.copyWith(color: AppColors.danger)),
            ]),
            if (b.cancelReason != null) ...[
              const SizedBox(height: 6),
              Text(l.reasonLabel(reasonText(l, b.cancelReason!)), style: const TextStyle(fontSize: 14, color: AppColors.danger)),
            ],
            if (b.status == BookingStatus.expired) ...[
              const SizedBox(height: 6),
              Text(l.expiredHint, style: AppText.body),
            ],
          ],
        ),
      );

  /// بطاقة المحل: الصورة والاسم والمنطقة، ثم الخريطة والاتصال وزر الإلغاء
  Widget _shopCard(AppLocalizations l, Booking b) {
    final client = AppScope.of(context).client;
    final shop = b.shop;
    final place = [shop.district, shop.area].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    final now = client.serverNow;
    final cancellable = (b.status == BookingStatus.pendingShop || b.status == BookingStatus.confirmed) && b.startsAt.isAfter(now);
    final actions = <(IconData, String, VoidCallback)>[
      if (shop.latitude != null && shop.longitude != null)
        (Icons.map_outlined, l.mapsShort, () => openInMaps(shop.latitude!, shop.longitude!, shop.name)),
      if (shop.phone != null) ...[
        (Icons.call_outlined, l.call, () => callPhone(shop.phone!)),
        (Icons.chat_outlined, l.whatsapp, () => openWhatsApp(shop.phone!)),
      ],
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.base),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShopScreen(shopId: shop.id))),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.base),
                  child: SizedBox(
                    width: 78,
                    height: 78,
                    child: ShopImage(url: shop.coverPhoto == null ? null : client.absoluteUrl(shop.coverPhoto!)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline),
                      if (place.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.location_on, size: 16, color: AppColors.primaryMuted),
                          const SizedBox(width: 4),
                          Expanded(child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (actions.isNotEmpty || cancellable) ...[
            const Divider(height: 28, color: AppColors.border),
            Row(
              children: [
                for (final (icon, label, onTap) in actions)
                  Expanded(
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(AppRadius.base),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, color: AppColors.primary, size: 24),
                          const SizedBox(height: 4),
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: AppColors.primary)),
                        ]),
                      ),
                    ),
                  ),
                if (actions.isEmpty) const Spacer(),
                if (cancellable)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: _busy ? null : () => _cancel(b),
                    child: Text(l.cancelBooking),
                  ),
              ],
            ),
          ],
        ],
      ),
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

  Future<void> _rate(Booking b) async {
    final l = AppLocalizations.of(context);
    final api = AppScope.of(context).api;
    final result = await Navigator.of(context).push<(int, String?)>(
      MaterialPageRoute(builder: (_) => _RateScreen(booking: b)),
    );
    if (result == null || !mounted) return;
    final before = _booking;
    await _run((key) => api.review(b.id, result.$1, result.$2, key));
    if (mounted && _booking?.review != null && before?.review == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.reviewSent)));
    }
  }

  Widget? _actions(AppLocalizations l, Booking b) {
    final api = AppScope.of(context).api;
    if (b.canReview) {
      return BottomActionBar(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : () => _rate(b),
          icon: const Icon(Icons.star_outline_rounded),
          label: Text(l.rateVisit),
        ),
      );
    }
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
    // الإلغاء في بطاقة المحل
    return null;
  }
}

/// شاشة التقييم كما في التصميم: رأس بنفسجي ببطاقة المحل، نجوم، تعليق، وعبارات جاهزة
class _RateScreen extends StatefulWidget {
  const _RateScreen({required this.booking});
  final Booking booking;

  @override
  State<_RateScreen> createState() => _RateScreenState();
}

class _RateScreenState extends State<_RateScreen> {
  int _stars = 0;
  final _comment = TextEditingController();
  final List<String> _tags = [];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    final text = [..._tags, _comment.text.trim()].where((s) => s.isNotEmpty).join('، ');
    Navigator.pop(context, (_stars, text.isEmpty ? null : text));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = [l.rateLabel1, l.rateLabel2, l.rateLabel3, l.rateLabel4, l.rateLabel5];
    final suggestions = [l.rateTag1, l.rateTag2, l.rateTag3, l.rateTag4, l.rateTag5, l.rateTag6, l.rateTag7, l.rateTag8];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Column(
          children: [
            _header(l),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                  children: [
                    Text(l.rateTitle, style: AppText.headline),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: Semantics(
                              button: true,
                              label: labels[i - 1],
                              child: GestureDetector(
                                onTap: () => setState(() => _stars = i),
                                child: Icon(Icons.star_rounded,
                                    size: 46, color: i <= _stars ? AppColors.accent : AppColors.border),
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        if (_stars > 0) Text('($_stars.0)', style: const TextStyle(fontSize: 16, color: AppColors.text)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_stars == 0 ? l.rateChooseStars : labels[_stars - 1],
                        style: TextStyle(fontSize: 14, color: _stars == 0 ? AppColors.textMuted : AppColors.text)),
                    const SizedBox(height: 22),
                    Text(l.yourReview, style: AppText.headline),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.base),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_tags.isNotEmpty)
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final t in _tags)
                                InputChip(
                                  label: Text(t, style: const TextStyle(fontSize: 14, color: AppColors.primary)),
                                  backgroundColor: AppColors.surface,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.base),
                                    side: const BorderSide(color: AppColors.primaryMuted),
                                  ),
                                  onDeleted: () => setState(() => _tags.remove(t)),
                                ),
                            ]),
                          TextField(
                            controller: _comment,
                            maxLength: 400,
                            minLines: 4,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: l.rateCommentHint,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.only(top: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final t in suggestions)
                          GestureDetector(
                            onTap: () => setState(() {
                              if (!_tags.remove(t)) _tags.add(t);
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tags.contains(t) ? AppColors.primaryLight.withValues(alpha: 0.6) : null,
                                borderRadius: BorderRadius.circular(AppRadius.base),
                                border: Border.all(color: _tags.contains(t) ? AppColors.primary : Colors.transparent),
                              ),
                              child: Text(t,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: _tags.contains(t) ? AppColors.primary : AppColors.textDisabled,
                                  )),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(l.rateFirstNameHint, style: AppText.caption),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          child: FilledButton(onPressed: _stars == 0 ? null : _submit, child: Text(l.rateSubmit)),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l) {
    final shop = widget.booking.shop;
    final client = AppScope.of(context).client;
    final place = [shop.district, shop.area].whereType<String>().where((s) => s.isNotEmpty).join('، ');
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BackButton(color: Colors.white),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsetsDirectional.only(start: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.base),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.base),
                    child: SizedBox(
                      width: 78,
                      height: 78,
                      child: ShopImage(url: shop.coverPhoto == null ? null : client.absoluteUrl(shop.coverPhoto!)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(shop.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.headline.copyWith(color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(formatAppointment(l, widget.booking.startsAt),
                            style: const TextStyle(fontSize: 14, color: Colors.white)),
                        if (place.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.white),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(place,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, color: Colors.white)),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
