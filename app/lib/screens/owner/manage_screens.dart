import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import 'editors.dart';
import 'owner_booking_screen.dart';
import 'owner_tab.dart';
import 'propose_screen.dart';
import 'setup_wizard.dart';

/// اختصارات إدارة المحل: التقويم، الخدمات، الأوقات، الإعدادات
class ManageMenu extends StatelessWidget {
  const ManageMenu({super.key, required this.shop, required this.config, required this.onShopChanged, this.calendar = true});
  final OwnerShop shop;
  final ServerConfig config;
  final ValueChanged<OwnerShopState> onShopChanged;
  final bool calendar;

  Future<void> _open(BuildContext context, Widget screen) async {
    final result = await Navigator.of(context).push<OwnerShopState>(MaterialPageRoute(builder: (_) => screen));
    if (result != null) onShopChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = [
      if (calendar) (Icons.calendar_month_outlined, l.menuCalendar, () => _open(context, const CalendarScreen())),
      (Icons.list_alt, l.menuServices, () => _open(context, ServicesScreen(shop: shop))),
      (Icons.schedule, l.menuHours, () => _open(context, HoursScreen(shop: shop))),
      (Icons.settings_outlined, l.menuSettings, () => _open(context, SettingsScreen(shop: shop, config: config))),
    ];
    return Row(children: [
      for (final (icon, label, onTap) in items) ...[
        if (label != items.first.$2) const SizedBox(width: 8),
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(children: [
                  Icon(icon, color: AppColors.primary),
                  const SizedBox(height: 4),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// ينتظر تعديلات الشاشة ويعيد آخر حالة للمحل عند الرجوع
mixin _ReturnsShop<T extends StatefulWidget> on State<T> {
  OwnerShopState? latest;

  Widget returning(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(latest);
        },
        child: child,
      );
}

// ============================================================
// التقويم
// ============================================================

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late final List<DateTime> _dates = DayStrip.next14(AppScope.of(context).client.serverNow);
  int _day = 0;
  List<OwnerBooking>? _bookings;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => (_bookings = null, _error = null));
    try {
      final list = await AppScope.of(context).owner.day(localDateKey(_dates[_day]));
      if (mounted) setState(() => _bookings = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.calendarTitle)),
      body: Column(children: [
        DayStrip(dates: _dates, selected: _day, onSelected: (i) {
          setState(() => _day = i);
          _load();
        }),
        const SizedBox(height: 12),
        Expanded(
          child: _bookings == null
              ? LoadState(error: _error, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Text(l.bookingsCount(_bookings!.length), style: const TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    if (_bookings!.isNotEmpty)
                      DayBookingsList(
                        bookings: _bookings!,
                        onOpen: (b) async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OwnerBookingScreen(bookingId: b.id)));
                          _load();
                        },
                      ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

// ============================================================
// الخدمات
// ============================================================

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key, required this.shop});
  final OwnerShop shop;

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> with _ReturnsShop {
  late OwnerShop _shop = widget.shop;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return returning(Scaffold(
      appBar: AppBar(title: Text(l.servicesTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ServicesEditor(shop: _shop, onSaved: (s) => setState(() => (latest = s, _shop = s.shop!))),
      ]),
    ));
  }
}

// ============================================================
// الأوقات، الجداول المؤقتة، والإغلاق الطارئ
// ============================================================

class HoursScreen extends StatefulWidget {
  const HoursScreen({super.key, required this.shop});
  final OwnerShop shop;

  @override
  State<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends State<HoursScreen> with _ReturnsShop {
  late OwnerShop _shop = widget.shop;
  final _hours = GlobalKey<HoursEditorState>();
  bool _saving = false;

  void _changed(OwnerShopState s) => setState(() => (latest = s, _shop = s.shop!));

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    final ok = await _hours.currentState!.save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.savedLabel)));
  }

  Future<void> _addTemporary() async {
    final result = await showDialog<Map<String, Object>>(context: context, builder: (_) => const _TemporaryScheduleDialog());
    if (result == null || !mounted) return;
    final owner = AppScope.of(context).owner;
    final s = await runSave(context, () => owner.addTemporarySchedule(result));
    if (s != null) _changed(s);
  }

  Future<void> _closure() async {
    final l = AppLocalizations.of(context);
    final result = await showDialog<(DateTime, DateTime, String)>(context: context, builder: (_) => const _ClosureDialog());
    if (result == null || !mounted) return;
    final services = AppScope.of(context);
    try {
      final r = await services.owner.addClosure(result.$1, result.$2, result.$3, newIdempotencyKey());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.closureResult(r.moved.length, r.cancelled.length))));
      final s = await services.owner.shop();
      _changed(s);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final owner = AppScope.of(context).owner;
    return returning(Scaffold(
      appBar: AppBar(title: Text(l.hoursTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        HoursEditor(key: _hours, shop: _shop, onSaved: _changed),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text(l.tempSchedules, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          OutlinedButton.icon(onPressed: _addTemporary, icon: const Icon(Icons.add, size: 18), label: Text(l.newTempSchedule)),
        ]),
        const SizedBox(height: 8),
        for (final t in _shop.temporarySchedules)
          Card(
            child: ListTile(
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(l.tempScheduleRange(t.fromDate, t.toDate)),
              trailing: IconButton(
                tooltip: l.deleteLabel,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final s = await runSave(context, () => owner.deleteTemporarySchedule(t.id));
                  if (s != null) _changed(s);
                },
              ),
            ),
          ),
        Text(l.tempScheduleHint, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        if (_shop.closures.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(l.upcomingClosures, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final c in _shop.closures)
            Card(
              child: ListTile(
                title: Text('${formatAppointment(l, c.startsAt)} – ${formatTime(l, c.endsAt)}'),
                subtitle: c.reason == null ? null : Text(c.reason!),
                trailing: IconButton(
                  tooltip: l.deleteLabel,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final s = await runSave(context, () => owner.deleteClosure(c.id));
                    if (s != null) _changed(s);
                  },
                ),
              ),
            ),
        ],
      ]),
      bottomNavigationBar: BottomActionBar(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: Text(l.saveLabel),
          ),
          if (_shop.status == ShopStatus.approved) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                backgroundColor: AppColors.dangerSoft,
                side: BorderSide.none,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: _closure,
              child: Text(l.emergencyClosure),
            ),
          ],
        ]),
      ),
    ));
  }
}

String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _TemporaryScheduleDialog extends StatefulWidget {
  const _TemporaryScheduleDialog();

  @override
  State<_TemporaryScheduleDialog> createState() => _TemporaryScheduleDialogState();
}

class _TemporaryScheduleDialogState extends State<_TemporaryScheduleDialog> {
  final _name = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  final _days = {for (final d in weekOrder) d: [OpenPeriod(const TimeOfDay(hour: 20, minute: 0), const TimeOfDay(hour: 2, minute: 0))]};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 366)), initialDate: initial ?? now);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ready = _name.text.trim().isNotEmpty && _from != null && _to != null && !_to!.isBefore(_from!);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(title: Text(l.newTempSchedule)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: l.tempScheduleName)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await _pick(_from);
                  if (d != null) setState(() => _from = d);
                },
                child: Text(_from == null ? l.fromDateLabel : _dateKey(_from!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final d = await _pick(_to ?? _from);
                  if (d != null) setState(() => _to = d);
                },
                child: Text(_to == null ? l.toDateLabel : _dateKey(_to!)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          WeekPeriodsEditor(days: _days),
        ]),
        bottomNavigationBar: BottomActionBar(
          child: FilledButton(
            onPressed: !ready
                ? null
                : () => Navigator.pop(context, <String, Object>{
                      'name': _name.text.trim(),
                      'fromDate': _dateKey(_from!),
                      'toDate': _dateKey(_to!),
                      'periods': periodsToJson(_days),
                    }),
            child: Text(l.saveLabel),
          ),
        ),
      ),
    );
  }
}

/// إغلاق يوم كامل أو ساعات منه، بتوقيت بغداد
class _ClosureDialog extends StatefulWidget {
  const _ClosureDialog();

  @override
  State<_ClosureDialog> createState() => _ClosureDialogState();
}

class _ClosureDialogState extends State<_ClosureDialog> {
  late DateTime _day = toBaghdad(DateTime.now());
  bool _allDay = true;
  TimeOfDay _from = TimeOfDay.fromDateTime(toBaghdad(DateTime.now()));
  TimeOfDay _to = const TimeOfDay(hour: 23, minute: 59);
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// حقول يوم ووقت بغداد إلى وقت عالمي
  DateTime _instant(TimeOfDay t) =>
      DateTime.utc(_day.year, _day.month, _day.day, t.hour, t.minute).subtract(baghdadOffset);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.emergencyClosure),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 60)), initialDate: _day);
              if (d != null) setState(() => _day = d);
            },
            child: Text('${l.closureDay}: ${_dateKey(_day)}'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.closureAllDay),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          if (!_allDay)
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _from);
                    if (t != null) setState(() => _from = t);
                  },
                  child: Text(formatClock(l, hhmm(_from))),
                ),
              ),
              const Text('–'),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: _to);
                    if (t != null) setState(() => _to = t);
                  },
                  child: Text(formatClock(l, hhmm(_to))),
                ),
              ),
            ]),
          TextField(controller: _reason, decoration: InputDecoration(labelText: l.closureReasonLabel)),
          const SizedBox(height: 12),
          Text(l.closureInfo, style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.6)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () {
            final from = _allDay ? _instant(const TimeOfDay(hour: 0, minute: 0)) : _instant(_from);
            final to = _allDay ? _instant(const TimeOfDay(hour: 0, minute: 0)).add(const Duration(days: 1)) : _instant(_to);
            Navigator.pop(context, (from, to, _reason.text));
          },
          child: Text(l.closeLabel),
        ),
      ],
    );
  }
}

// ============================================================
// الإعدادات
// ============================================================

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.shop, required this.config});
  final OwnerShop shop;
  final ServerConfig config;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with _ReturnsShop {
  late OwnerShop _shop = widget.shop;

  Future<void> _update(Map<String, Object> change) async {
    final owner = AppScope.of(context).owner;
    final s = await runSave(context, () => owner.updateSettings(change));
    if (s != null) setState(() => (latest = s, _shop = s.shop!));
  }

  Widget _choice<T>(String title, T value, Map<T, String> options, ValueChanged<T> onChanged, {String? hint}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: e.key == value,
                showCheckmark: false,
                selectedColor: AppColors.primarySoft,
                side: BorderSide(color: e.key == value ? AppColors.primary : AppColors.border),
                onSelected: (_) => onChanged(e.key),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String hours(int h) => formatDuration(l, h * 60);
    return returning(Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _choice(l.deadlineModeLabel, _shop.deadlineMode,
            {'fast': l.modeFast, 'normal': l.modeNormal, 'flexible': l.modeFlexible},
            (v) => _update({'deadlineMode': v}), hint: l.modeHint),
        const SizedBox(height: 10),
        _choice(l.freeCancelLabel, _shop.freeCancelHours, {for (final h in [1, 2, 6, 24]) h: hours(h)},
            (v) => _update({'freeCancelHours': v})),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            title: Text(l.instantBookingLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l.instantBookingHint),
            value: _shop.instantBooking,
            onChanged: (v) => _update({'instantBooking': v}),
          ),
        ),
        const SizedBox(height: 10),
        _choice(l.bufferLabel, _shop.bufferMinutes,
            {0: l.noBuffer, 5: formatDuration(l, 5), 10: formatDuration(l, 10), 15: formatDuration(l, 15)},
            (v) => _update({'bufferMinutes': v})),
        const SizedBox(height: 10),
        _choice(l.minLeadLabel, _shop.minLeadMinutes,
            {for (final h in [3, 6, 12, 24]) h * 60: hours(h)}, (v) => _update({'minLeadMinutes': v})),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.edit_outlined),
          label: Text(l.editShopDetails),
          onPressed: () async {
            final state = await AppScope.of(context).owner.shop();
            if (!context.mounted) return;
            final result = await Navigator.of(context).push<OwnerShopState>(
              MaterialPageRoute(builder: (_) => SetupWizard(initial: state, config: widget.config, editOnly: true)),
            );
            if (result != null) setState(() => (latest = result, _shop = result.shop!));
          },
        ),
      ]),
    ));
  }
}
