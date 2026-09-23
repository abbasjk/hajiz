import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_draft.dart';
import 'booking_review_screen.dart';
import 'booking_services_screen.dart';

/// الخطوة 2: اليوم ثم الوقت، من الأوقات المتاحة فقط
class BookingTimeScreen extends StatefulWidget {
  const BookingTimeScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookingTimeScreen> createState() => _BookingTimeScreenState();
}

class _BookingTimeScreenState extends State<BookingTimeScreen> {
  static const _days = 14;
  late List<DateTime> _dates; // منتصف نهار كل يوم بتوقيت بغداد، للعرض فقط
  int _dayIndex = 0;
  List<DateTime>? _slots;
  Object? _error;
  int _requestId = 0;
  bool _autoAdvance = true;

  @override
  void initState() {
    super.initState();
    widget.draft.startsAt = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final now = AppScope.of(context).client.serverNow;
      final today = DateTime.parse('${localDateKey(now)}T09:00:00Z'); // 12:00 ظهراً في بغداد
      _dates = [for (var i = 0; i < _days; i++) today.add(Duration(days: i))];
      _dayIndex = _dates.indexWhere(_isOpenDay).clamp(0, _days - 1);
      _load();
    });
  }

  /// يوم بلا فترات عمل أسبوعية يظهر "مغلق"، إلا إذا غطّاه جدول مؤقت
  bool _isOpenDay(DateTime date) {
    final key = localDateKey(date);
    final covered = widget.draft.shop.temporarySchedules
        .any((t) => key.compareTo(t.fromDate) >= 0 && key.compareTo(t.toDate) <= 0);
    return covered || widget.draft.shop.weeklyHours.any((h) => h.dayOfWeek == localDayOfWeek(date));
  }

  int? _nextOpenDay(int from) {
    for (var i = from; i < _days; i++) {
      if (_isOpenDay(_dates[i])) return i;
    }
    return null;
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _slots = null;
      _error = null;
      widget.draft.startsAt = null;
    });
    try {
      final slots = await AppScope.of(context)
          .api
          .slots(widget.draft.shop.id, localDateKey(_dates[_dayIndex]), widget.draft.serviceIds);
      if (!mounted || id != _requestId) return;
      // عند الفتح: إذا لم يبقَ وقت اليوم ننتقل لأول يوم مفتوح فيه أوقات
      final next = _nextOpenDay(_dayIndex + 1);
      if (_autoAdvance && slots.isEmpty && next != null) {
        _dayIndex = next;
        await _load();
        return;
      }
      _autoAdvance = false;
      setState(() => _slots = slots);
    } catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final draft = widget.draft;
    return Scaffold(
      appBar: BookingAppBar(shopName: draft.shop.name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BookingSteps(current: 2),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${draft.services.map((s) => s.name).join(' + ')} · ${l.minutes(draft.durationMinutes)}',
              style: const TextStyle(fontSize: 13, color: AppColors.primaryDark),
            ),
          ),
          if (_slots != null || _error != null || _requestId > 0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '${monthName(l, toBaghdad(_dates[_dayIndex]).month)} ${toBaghdad(_dates[_dayIndex]).year}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 68,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _days,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) => _dayButton(l, i),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Expanded(child: _slotsView(l)),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.selectedTime, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                  Text(
                    draft.startsAt == null ? l.chooseTime : '${formatDayShort(l, draft.startsAt!)} · ${formatTime(l, draft.startsAt!)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: draft.startsAt == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingReviewScreen(draft: draft)));
                      // عند الرجوع من المراجعة (مثلاً الوقت أُخذ) نحدّث الأوقات
                      if (mounted) _load();
                    },
              child: Text(l.next),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayButton(AppLocalizations l, int i) {
    final date = _dates[i];
    final open = _isOpenDay(date);
    final selected = i == _dayIndex;
    return SizedBox(
      width: 56,
      child: Material(
        color: selected ? AppColors.primary : (open ? AppColors.surface : Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected ? BorderSide.none : BorderSide(color: open ? AppColors.border : AppColors.borderStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
              Text(dayName(l, localDayOfWeek(date)),
                  style: TextStyle(fontSize: 11, color: selected ? Colors.white : AppColors.textMuted)),
              Text(
                open ? '${toBaghdad(date).day}' : l.closed,
                style: TextStyle(
                  fontSize: open ? 17 : 12,
                  fontWeight: open ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : (open ? AppColors.text : AppColors.textDisabled),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slotsView(AppLocalizations l) {
    final slots = _slots;
    if (slots == null) return LoadState(error: _error, onRetry: _load);
    if (slots.isEmpty) {
      return Center(child: Text(l.noSlots, style: const TextStyle(color: AppColors.textMuted)));
    }
    final morning = slots.where((s) => toBaghdad(s).hour < 12).toList();
    final evening = slots.where((s) => toBaghdad(s).hour >= 12).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        if (morning.isNotEmpty) ..._group(l, l.morning, morning),
        if (evening.isNotEmpty) ..._group(l, l.evening, evening),
      ],
    );
  }

  List<Widget> _group(AppLocalizations l, String title, List<DateTime> slots) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [for (final s in slots) _slotButton(l, s)],
        ),
        const SizedBox(height: 12),
      ];

  Widget _slotButton(AppLocalizations l, DateTime slot) {
    final selected = widget.draft.startsAt == slot;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primarySoft : AppColors.surface,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        padding: EdgeInsets.zero,
      ),
      onPressed: () => setState(() => widget.draft.startsAt = slot),
      child: Text(
        formatTime(l, slot),
        style: TextStyle(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? AppColors.primaryDark : AppColors.text,
        ),
      ),
    );
  }
}
