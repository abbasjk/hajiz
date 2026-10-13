import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_draft.dart';
import 'booking_review_screen.dart';

/// حجز موعد كما في التصميم: اليوم، ثم الوقت، ثم الخدمات، وملخص السعر
/// الأوقات تُحسب من مدة الخدمات المختارة، فتتحدث كلما تغيّرت
class BookingServicesScreen extends StatefulWidget {
  const BookingServicesScreen({super.key, required this.shop, this.initial = const []});
  final ShopDetails shop;

  /// الخدمات التي اختارها الزبون من صفحة المحل
  final List<Service> initial;

  @override
  State<BookingServicesScreen> createState() => _BookingServicesScreenState();
}

class _BookingServicesScreenState extends State<BookingServicesScreen> {
  static const _days = 14;
  late final BookingDraft _draft = BookingDraft(widget.shop)..services.addAll(widget.initial);
  List<DateTime>? _dates; // منتصف نهار كل يوم بتوقيت بغداد، للعرض فقط
  int _dayIndex = 0;
  List<DateTime>? _slots;
  Object? _error;
  int _requestId = 0;
  bool _autoAdvance = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dates != null) return;
    final now = AppScope.of(context).client.serverNow;
    final today = DateTime.parse('${localDateKey(now)}T09:00:00Z'); // 12:00 ظهراً في بغداد
    final dates = [for (var i = 0; i < _days; i++) today.add(Duration(days: i))];
    _dates = dates;
    _dayIndex = dates.indexWhere(_isOpenDay).clamp(0, _days - 1);
    if (_draft.services.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// يوم بلا فترات عمل أسبوعية يظهر "مغلق"، إلا إذا غطّاه جدول مؤقت
  bool _isOpenDay(DateTime date) {
    final key = localDateKey(date);
    final covered = widget.shop.temporarySchedules
        .any((t) => key.compareTo(t.fromDate) >= 0 && key.compareTo(t.toDate) <= 0);
    return covered || widget.shop.weeklyHours.any((h) => h.dayOfWeek == localDayOfWeek(date));
  }

  int? _nextOpenDay(int from) {
    final dates = _dates!;
    for (var i = from; i < _days; i++) {
      if (_isOpenDay(dates[i])) return i;
    }
    return null;
  }

  Future<void> _load() async {
    final id = ++_requestId;
    final previous = _draft.startsAt;
    setState(() {
      _slots = null;
      _error = null;
      _draft.startsAt = null;
    });
    if (_draft.services.isEmpty) return;
    try {
      final slots = await AppScope.of(context).api.slots(widget.shop.id, localDateKey(_dates![_dayIndex]), _draft.serviceIds);
      if (!mounted || id != _requestId) return;
      // عند الفتح: إذا لم يبقَ وقت اليوم ننتقل لأول يوم مفتوح فيه أوقات
      final next = _nextOpenDay(_dayIndex + 1);
      if (_autoAdvance && slots.isEmpty && next != null) {
        _dayIndex = next;
        await _load();
        return;
      }
      _autoAdvance = false;
      setState(() {
        _slots = slots;
        // إذا بقي الوقت المختار متاحاً بعد تغيير الخدمات نُبقيه
        if (previous != null && slots.contains(previous)) _draft.startsAt = previous;
      });
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e);
    }
  }

  void _toggle(Service s) {
    setState(() {
      if (!_draft.services.remove(s)) _draft.services.add(s);
    });
    _load();
  }

  Future<void> _continue() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingReviewScreen(draft: _draft)));
    // عند الرجوع من التأكيد (مثلاً الوقت أُخذ) نحدّث الأوقات
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dates = _dates!;
    final day = toBaghdad(dates[_dayIndex]);
    return Scaffold(
      appBar: AppBar(title: Text(l.bookingTitle, style: AppText.headline)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _heading(l.chooseDate),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('${monthName(l, day.month)}، ${day.year}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: AppColors.text)),
          ),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _days,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _dayCard(l, i),
            ),
          ),
          const SizedBox(height: 24),
          _heading(l.availableTime),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _slotsView(l)),
          const SizedBox(height: 24),
          _heading(l.chooseService),
          SizedBox(
            height: 124,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.shop.services.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _serviceItem(l, widget.shop.services[i]),
            ),
          ),
          if (_draft.services.isNotEmpty) ...[
            const SizedBox(height: 16),
            _heading(l.paymentSummary),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final s in _draft.services) _summaryRow(s.name, formatPrice(l, s)),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: DashedLine()),
                  _summaryRow(l.servicesCount(_draft.services.length, _draft.durationMinutes), formatTotal(l, _draft.services),
                      bold: true),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _draft.startsAt == null ? null : _continue,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_draft.startsAt == null ? l.chooseTime : l.confirmAppointment),
              const SizedBox(width: 8),
              const Icon(Icons.event_available_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Text(text, style: AppText.headline),
      );

  Widget _dayCard(AppLocalizations l, int i) {
    final date = _dates![i];
    final open = _isOpenDay(date);
    final selected = i == _dayIndex;
    final numberColor = selected ? Colors.white : (open ? AppColors.inkMuted : AppColors.textDisabled);
    final labelColor = selected ? Colors.white : (open ? AppColors.primaryMuted : AppColors.textDisabled);
    return SizedBox(
      width: 80,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.day),
          side: selected ? BorderSide.none : const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.day),
          onTap: open && !selected
              ? () {
                  _autoAdvance = false;
                  setState(() => _dayIndex = i);
                  _load();
                }
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${toBaghdad(date).day}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: numberColor)),
              const SizedBox(height: 4),
              Text(open ? dayName(l, localDayOfWeek(date)) : l.closed,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: labelColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slotsView(AppLocalizations l) {
    if (_draft.services.isEmpty) {
      return Text(l.pickServiceFirst, style: AppText.body);
    }
    final slots = _slots;
    if (slots == null) {
      return SizedBox(height: 120, child: LoadState(error: _error, onRetry: _load));
    }
    if (slots.isEmpty) return Text(l.noSlots, style: AppText.body);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [for (final s in slots) _slotButton(l, s)],
    );
  }

  Widget _slotButton(AppLocalizations l, DateTime slot) {
    final selected = _draft.startsAt == slot;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primary : AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.base)),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => setState(() => _draft.startsAt = slot),
      child: Text(
        formatTime(l, slot),
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.inkMuted),
      ),
    );
  }

  Widget _serviceItem(AppLocalizations l, Service s) {
    final on = _draft.services.contains(s);
    return InkWell(
      onTap: () => _toggle(s),
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: SizedBox(
        width: 104,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? AppColors.primaryMuted : AppColors.primarySoft,
              ),
              child: on
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 32)
                  : Text(s.name.characters.first,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ),
            const SizedBox(height: 8),
            Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(formatPrice(l, s), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: AppColors.text)),
            ),
            Text(value,
                style: TextStyle(fontSize: bold ? 18 : 16, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: AppColors.text)),
          ],
        ),
      );
}

/// خط متقطع كما في ملخص السعر في التصميم
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, this.color = AppColors.borderStrong});
  final Color color;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final count = (box.maxWidth / 14).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < count; i++) SizedBox(width: 8, height: 1.2, child: ColoredBox(color: color)),
            ],
          );
        },
      );
}

/// رأس شاشة تأكيد الحجز: "حجز موعد" واسم المحل؛ سهم الرجوع يُعكس تلقائياً
class BookingAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BookingAppBar({super.key, required this.shopName});
  final String shopName;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      toolbarHeight: 64,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.bookingTitle, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
          Text(shopName),
        ],
      ),
    );
  }
}
