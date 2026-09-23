import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// شريط أيام أفقي (14 يوماً من اليوم) بتوقيت بغداد
class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.dates, required this.selected, required this.onSelected});
  final List<DateTime> dates;
  final int selected;
  final ValueChanged<int> onSelected;

  static List<DateTime> next14(DateTime now) {
    final noon = DateTime.parse('${localDateKey(now)}T09:00:00Z'); // 12:00 ظهراً في بغداد
    return [for (var i = 0; i < 14; i++) noon.add(Duration(days: i))];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final on = i == selected;
          return SizedBox(
            width: 56,
            child: Material(
              color: on ? AppColors.primary : AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: on ? BorderSide.none : const BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(i),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(dayName(l, localDayOfWeek(dates[i])), style: TextStyle(fontSize: 11, color: on ? Colors.white : AppColors.textMuted)),
                  Text('${toBaghdad(dates[i]).day}',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.text)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// اقتراح من وقت إلى ثلاثة أوقات بديلة، من الأوقات المتاحة التي تتسع لمدة الحجز
class ProposeScreen extends StatefulWidget {
  const ProposeScreen({super.key, required this.booking});
  final OwnerBooking booking;

  @override
  State<ProposeScreen> createState() => _ProposeScreenState();
}

class _ProposeScreenState extends State<ProposeScreen> {
  late final List<DateTime> _dates = DayStrip.next14(AppScope.of(context).client.serverNow);
  int _day = 0;
  List<DateTime>? _slots;
  Object? _error;
  final _chosen = <DateTime>[];
  final _message = TextEditingController();
  final _key = newIdempotencyKey();
  bool _sending = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => (_slots = null, _error = null));
    try {
      final slots = await AppScope.of(context).owner.proposalSlots(widget.booking.id, localDateKey(_dates[_day]));
      // الوقت الأصلي نفسه ليس بديلاً
      if (mounted) setState(() => _slots = slots.where((s) => s != widget.booking.startsAt).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    if (_sending || _chosen.isEmpty) return;
    setState(() => _sending = true);
    try {
      final b = await AppScope.of(context).owner.propose(widget.booking.id, _chosen..sort(), _message.text, _key);
      if (mounted) Navigator.pop(context, b);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showError(context, e);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final b = widget.booking;
    return Scaffold(
      appBar: AppBar(title: Text(l.proposeAlternatives)),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b.customer.name} · ${l.minutes(b.durationMinutes)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: AppColors.textMuted), children: [
                  TextSpan(text: '${l.requestedLabel} '),
                  TextSpan(text: formatAppointment(l, b.startsAt), style: const TextStyle(decoration: TextDecoration.lineThrough)),
                ])),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(children: [
            Expanded(child: Text(l.chooseUpTo3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(8)),
              child: Text(l.selectedCount(_chosen.length),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
            ),
          ]),
        ),
        DayStrip(dates: _dates, selected: _day, onSelected: (i) {
          setState(() => _day = i);
          _load();
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(l.slotsFitDuration(b.durationMinutes), style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _slots == null
              ? SizedBox(height: 100, child: LoadState(error: _error, onRetry: _load))
              : _slots!.isEmpty
                  ? Text(l.noSlots, style: const TextStyle(color: AppColors.textMuted))
                  : Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in _slots!)
                        FilterChip(
                          label: Text(formatTime(l, s)),
                          selected: _chosen.contains(s),
                          showCheckmark: false,
                          selectedColor: AppColors.primarySoft,
                          side: BorderSide(color: _chosen.contains(s) ? AppColors.primary : AppColors.border),
                          onSelected: (on) => setState(() {
                            if (on && _chosen.length < 3) {
                              _chosen.add(s);
                            } else {
                              _chosen.remove(s);
                            }
                          }),
                        ),
                    ]),
        ),
        if (_chosen.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(l.selectedTimes, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          for (final t in [..._chosen]..sort())
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: ListTile(
                  title: Text(formatAppointment(l, t), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: IconButton(
                    tooltip: l.removeLabel,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _chosen.remove(t)),
                  ),
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.messageToCustomer, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(controller: _message, maxLength: 200, decoration: InputDecoration(hintText: l.messageHint)),
            Text(l.proposalNotHeld, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.6)),
          ]),
        ),
      ]),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _sending || _chosen.isEmpty ? null : _send,
          child: Text(l.sendProposal),
        ),
      ),
    );
  }
}
