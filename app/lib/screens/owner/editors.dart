import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// محرر خطوة من بيانات المحل: يحفظ ما فيه عند الطلب ويعيد true إذا نجح.
abstract class StepEditorState<T extends StatefulWidget> extends State<T> {
  Future<bool> save();
}

typedef ShopChanged = void Function(OwnerShopState state);

/// ينفذ طلباً للخادم ويعرض الخطأ إن حدث
Future<OwnerShopState?> runSave(BuildContext context, Future<OwnerShopState> Function() request) async {
  try {
    return await request();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

String? _nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();

Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );

// ============================================================
// البيانات
// ============================================================

class DetailsEditor extends StatefulWidget {
  const DetailsEditor({super.key, required this.shop, required this.config, required this.onSaved});
  final OwnerShop? shop;
  final ServerConfig config;
  final ShopChanged onSaved;

  @override
  State<DetailsEditor> createState() => DetailsEditorState();
}

class DetailsEditorState extends StepEditorState<DetailsEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.shop?.name);
  late final _description = TextEditingController(text: widget.shop?.description);
  late final _phone = TextEditingController(text: widget.shop?.phone);
  late int? _typeId = widget.shop?.businessTypeId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // رقم المحل يُقترح من رقم صاحب المحل
    if (_phone.text.isEmpty) _phone.text = AppScope.of(context).session.user?.phone ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Future<bool> save() async {
    if (!(_form.currentState?.validate() ?? false)) return false;
    final owner = AppScope.of(context).owner;
    final state = await runSave(context, () => owner.saveDetails({
          'name': _name.text.trim(),
          'businessTypeId': _typeId,
          'description': _nonEmpty(_description.text),
          'phone': _nonEmpty(_phone.text),
        }));
    if (state == null) return false;
    widget.onSaved(state);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionLabel(l.shopNameLabel),
          TextFormField(
            controller: _name,
            maxLength: 60,
            validator: (v) => (v ?? '').trim().length < 2 ? l.fieldRequired : null,
          ),
          sectionLabel(l.businessTypeLabel),
          DropdownButtonFormField<int>(
            initialValue: _typeId,
            isExpanded: true,
            items: [for (final t in widget.config.businessTypes) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setState(() => _typeId = v),
            validator: (v) => v == null ? l.fieldRequired : null,
          ),
          sectionLabel(l.shopPhoneLabel),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
          ),
          sectionLabel(l.descriptionLabel),
          TextFormField(controller: _description, maxLines: 3, maxLength: 500),
        ],
      ),
    );
  }
}

// ============================================================
// العنوان والموقع
// ============================================================

/// مركز البصرة، نقطة البداية إذا لم يحدد صاحب المحل موقعه بعد
const _basra = LatLng(30.5085, 47.7804);

class AddressEditor extends StatefulWidget {
  const AddressEditor({super.key, required this.shop, required this.config, required this.onSaved});
  final OwnerShop? shop;
  final ServerConfig config;
  final ShopChanged onSaved;

  @override
  State<AddressEditor> createState() => AddressEditorState();
}

class AddressEditorState extends StepEditorState<AddressEditor> {
  final _form = GlobalKey<FormState>();
  final _map = MapController();
  late int? _districtId = widget.shop?.districtId;
  late int? _areaId = widget.shop?.areaId;
  late final _street = TextEditingController(text: widget.shop?.street);
  late final _landmark = TextEditingController(text: widget.shop?.landmark);
  late LatLng? _point = widget.shop?.latitude == null ? null : LatLng(widget.shop!.latitude!, widget.shop!.longitude!);
  bool _locating = false;

  @override
  void dispose() {
    _street.dispose();
    _landmark.dispose();
    super.dispose();
  }

  @override
  Future<bool> save() async {
    final l = AppLocalizations.of(context);
    if (!(_form.currentState?.validate() ?? false)) return false;
    final point = _point ?? _map.camera.center;
    final owner = AppScope.of(context).owner;
    final state = await runSave(context, () => owner.saveDetails({
          'districtId': _districtId,
          'areaId': _areaId,
          'street': _nonEmpty(_street.text),
          'landmark': _nonEmpty(_landmark.text),
          'latitude': point.latitude,
          'longitude': point.longitude,
        }));
    if (state == null) return false;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.savedLabel)));
    widget.onSaved(state);
    return true;
  }

  /// "أنا في المحل الآن": موقع دقيق من الهاتف، ثم يعدّله صاحب المحل بتحريك الخريطة
  Future<void> _locate() async {
    final l = AppLocalizations.of(context);
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final point = LatLng(p.latitude, p.longitude);
      setState(() => _point = point);
      _map.move(point, 17);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.locationFailed)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _requestArea() async {
    final l = AppLocalizations.of(context);
    final districtId = _districtId;
    if (districtId == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.areaRequestTitle),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: l.areaRequestHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(l.sendLabel)),
        ],
      ),
    );
    if (name == null || name.trim().length < 2 || !mounted) return;
    try {
      await AppScope.of(context).owner.requestArea(districtId, name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.areaRequested)));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final areas = widget.config.areas.where((a) => a.districtId == _districtId).toList();
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionLabel(l.districtLabel),
          DropdownButtonFormField<int>(
            initialValue: _districtId,
            isExpanded: true,
            items: [for (final d in widget.config.districts) DropdownMenuItem(value: d.id, child: Text(d.name))],
            onChanged: (v) => setState(() {
              _districtId = v;
              _areaId = null;
            }),
            validator: (v) => v == null ? l.fieldRequired : null,
          ),
          sectionLabel(l.areaLabel),
          DropdownButtonFormField<int>(
            key: ValueKey(_districtId),
            initialValue: areas.any((a) => a.id == _areaId) ? _areaId : null,
            isExpanded: true,
            items: [for (final a in areas) DropdownMenuItem(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _areaId = v),
            validator: (v) => v == null ? l.fieldRequired : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: _districtId == null ? null : _requestArea, child: Text(l.missingArea)),
          ),
          sectionLabel(l.streetLabel),
          TextFormField(controller: _street, decoration: InputDecoration(hintText: l.streetHint)),
          sectionLabel(l.landmarkLabel),
          TextFormField(controller: _landmark, decoration: InputDecoration(hintText: l.landmarkHint)),
          sectionLabel(l.mapLabel),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // خريطة مفتوحة المصدر؛ الدبوس ثابت في المنتصف وصاحب المحل يحرّك الخريطة تحته
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _point ?? _basra,
                      initialZoom: _point == null ? 12 : 17,
                      onPositionChanged: (camera, hasGesture) {
                        if (hasGesture) _point = camera.center;
                      },
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'iq.hajiz.hajiz'),
                      const SimpleAttributionWidget(source: Text('OpenStreetMap')),
                    ],
                  ),
                  const IgnorePointer(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 36),
                      child: Icon(Icons.location_on, size: 40, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l.mapHint, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: Text(l.iAmAtShop),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// الصور
// ============================================================

class PhotosEditor extends StatefulWidget {
  const PhotosEditor({super.key, required this.shop, required this.onSaved});
  final OwnerShop shop;
  final ShopChanged onSaved;

  @override
  State<PhotosEditor> createState() => PhotosEditorState();
}

class PhotosEditorState extends StepEditorState<PhotosEditor> {
  bool _busy = false;

  /// الصور تُحفظ فور إضافتها، والخطوة اختيارية
  @override
  Future<bool> save() async => true;

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(l.fromCamera), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(l.fromGallery), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    // تصغير قبل الرفع: الخادم يحفظ الصور في قاعدة البيانات
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 75);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final type = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    if (!mounted) return;
    final owner = AppScope.of(context).owner;
    final state = await runSave(context, () => owner.addPhoto(type, base64Encode(bytes)));
    if (mounted) setState(() => _busy = false);
    if (state != null) widget.onSaved(state);
  }

  Future<void> _delete(ShopPhoto p) async {
    final owner = AppScope.of(context).owner;
    final state = await runSave(context, () => owner.deletePhoto(p.id));
    if (state != null) widget.onSaved(state);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final client = AppScope.of(context).client;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.photosHint, style: const TextStyle(color: AppColors.textMuted, height: 1.6)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in widget.shop.photos)
              Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(client.absoluteUrl(p.url), fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: AppColors.primarySoft)),
                ),
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: IconButton.filledTonal(
                    tooltip: l.deletePhoto,
                    iconSize: 18,
                    onPressed: () => _delete(p),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ]),
            OutlinedButton(
              onPressed: _busy ? null : _add,
              child: _busy
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_a_photo_outlined),
                      const SizedBox(height: 4),
                      Text(l.addPhoto, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                    ]),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// الخدمات
// ============================================================

class ServicesEditor extends StatefulWidget {
  const ServicesEditor({super.key, required this.shop, required this.onSaved});
  final OwnerShop shop;
  final ShopChanged onSaved;

  @override
  State<ServicesEditor> createState() => ServicesEditorState();
}

class ServicesEditorState extends StepEditorState<ServicesEditor> {
  /// الخدمات تُحفظ فور إضافتها؛ يلزم خدمة واحدة ظاهرة على الأقل
  @override
  Future<bool> save() async {
    final ok = widget.shop.services.any((s) => s.active);
    if (!ok) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.missingItems(l.missingServices))));
    }
    return ok;
  }

  Future<void> _edit([OwnerService? service]) async {
    final result = await showDialog<Map<String, Object?>>(context: context, builder: (_) => _ServiceDialog(service: service));
    if (result == null || !mounted) return;
    final owner = AppScope.of(context).owner;
    final state = await runSave(
      context,
      () => service == null ? owner.addService(result) : owner.updateService(service.id, result),
    );
    if (state != null) widget.onSaved(state);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.shop.services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.noServicesYet, style: const TextStyle(color: AppColors.textMuted)),
          ),
        for (final s in widget.shop.services)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                onTap: () => _edit(s),
                title: Text(s.name, style: TextStyle(fontWeight: FontWeight.w600, color: s.active ? null : AppColors.textDisabled)),
                subtitle: Text(s.active ? l.minutes(s.durationMinutes) : '${l.minutes(s.durationMinutes)} · ${l.serviceHidden}'),
                trailing: Text(formatPrice(l, s), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        OutlinedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(l.addService)),
      ],
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.service});
  final OwnerService? service;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name);
  late final _duration = TextEditingController(text: '${widget.service?.durationMinutes ?? 30}');
  late final _price = TextEditingController(text: widget.service?.price?.toString() ?? '');
  late PriceType _type = widget.service?.priceType ?? PriceType.fixed;
  late bool _active = widget.service?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.service == null ? l.addService : l.editService),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.serviceName),
              validator: (v) => (v ?? '').trim().isEmpty ? l.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _duration,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.serviceDuration),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 5 || n > 480 || n % 5 != 0 ? l.durationInvalid : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PriceType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: l.priceTypeLabel),
              items: [
                DropdownMenuItem(value: PriceType.fixed, child: Text(l.priceFixedOption)),
                DropdownMenuItem(value: PriceType.startsFrom, child: Text(l.priceStartsFromOption)),
                DropdownMenuItem(value: PriceType.afterInspection, child: Text(l.priceAfterInspectionOption)),
              ],
              onChanged: (v) => setState(() => _type = v ?? PriceType.fixed),
            ),
            if (_type != PriceType.afterInspection) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.priceAmount),
                validator: (v) => int.tryParse(v ?? '') == null ? l.fieldRequired : null,
              ),
            ],
            if (widget.service != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_active ? l.hideService : l.showService),
                value: !_active,
                onChanged: (v) => setState(() => _active = !v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        TextButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'durationMinutes': int.parse(_duration.text),
              'priceType': switch (_type) {
                PriceType.fixed => 'fixed',
                PriceType.startsFrom => 'starts_from',
                PriceType.afterInspection => 'after_inspection',
              },
              'price': _type == PriceType.afterInspection ? null : int.parse(_price.text),
              'active': _active,
            });
          },
          child: Text(l.saveLabel),
        ),
      ],
    );
  }
}

// ============================================================
// أوقات العمل
// ============================================================

/// الأسبوع في العراق يبدأ السبت
const weekOrder = [6, 0, 1, 2, 3, 4, 5];

class OpenPeriod {
  OpenPeriod(this.from, this.to);
  TimeOfDay from;
  TimeOfDay to;

  bool get overnight => to.hour * 60 + to.minute <= from.hour * 60 + from.minute;
}

String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay parseHhmm(String s) {
  final p = s.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}

List<Map<String, Object>> periodsToJson(Map<int, List<OpenPeriod>> days) => [
      for (final e in days.entries)
        for (final p in e.value) {'dayOfWeek': e.key, 'from': hhmm(p.from), 'to': hhmm(p.to)},
    ];

Map<int, List<OpenPeriod>> periodsFromList(List<WorkingPeriod> list) => {
      for (final d in weekOrder)
        d: [for (final p in list.where((p) => p.dayOfWeek == d)) OpenPeriod(parseHhmm(p.from), parseHhmm(p.to))],
    };

/// محرر فترات الأسبوع: كل يوم يُفعَّل أو يكون عطلة، وفيه فترة أو أكثر
class WeekPeriodsEditor extends StatefulWidget {
  const WeekPeriodsEditor({super.key, required this.days});
  final Map<int, List<OpenPeriod>> days;

  @override
  State<WeekPeriodsEditor> createState() => _WeekPeriodsEditorState();
}

class _WeekPeriodsEditorState extends State<WeekPeriodsEditor> {
  Future<TimeOfDay?> _pick(TimeOfDay initial) => showTimePicker(context: context, initialTime: initial);

  String _clock(AppLocalizations l, TimeOfDay t) => formatClock(l, hhmm(t));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Column(children: [
        for (final day in weekOrder) ...[
          if (day != weekOrder.first) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 104,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.primary,
                  value: widget.days[day]!.isNotEmpty,
                  title: Text(dayName(l, day), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onChanged: (on) => setState(() {
                    widget.days[day] = on == true
                        ? [OpenPeriod(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 21, minute: 0))]
                        : [];
                  }),
                ),
              ),
              Expanded(
                child: widget.days[day]!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(l.dayOff, style: const TextStyle(color: AppColors.textMuted)),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final p in widget.days[day]!)
                          Row(children: [
                            Expanded(
                              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                                  onPressed: () async {
                                    final t = await _pick(p.from);
                                    if (t != null) setState(() => p.from = t);
                                  },
                                  child: Text(_clock(l, p.from)),
                                ),
                                const Text('–'),
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                                  onPressed: () async {
                                    final t = await _pick(p.to);
                                    if (t != null) setState(() => p.to = t);
                                  },
                                  child: Text('${_clock(l, p.to)}${p.overnight ? ' ${l.nextDay}' : ''}'),
                                ),
                              ]),
                            ),
                            IconButton(
                              tooltip: l.deleteLabel,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => widget.days[day]!.remove(p)),
                            ),
                          ]),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            final last = widget.days[day]!.last;
                            widget.days[day]!.add(OpenPeriod(last.to, TimeOfDay(hour: (last.to.hour + 3) % 24, minute: last.to.minute)));
                          }),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(l.addPeriod),
                        ),
                      ]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class HoursEditor extends StatefulWidget {
  const HoursEditor({super.key, required this.shop, required this.onSaved});
  final OwnerShop shop;
  final ShopChanged onSaved;

  @override
  State<HoursEditor> createState() => HoursEditorState();
}

class HoursEditorState extends StepEditorState<HoursEditor> {
  late final Map<int, List<OpenPeriod>> _days = () {
    final days = periodsFromList(widget.shop.weeklyHours);
    // أول مرة: السبت إلى الخميس من 9 صباحاً إلى 9 مساءً، والجمعة عطلة
    if (widget.shop.weeklyHours.isEmpty) {
      for (final d in [6, 0, 1, 2, 3, 4]) {
        days[d] = [OpenPeriod(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 21, minute: 0))];
      }
    }
    return days;
  }();

  @override
  Future<bool> save() async {
    final owner = AppScope.of(context).owner;
    final state = await runSave(context, () => owner.setHours(periodsToJson(_days)));
    if (state == null) return false;
    widget.onSaved(state);
    return state.shop!.weeklyHours.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l.hoursHint, style: const TextStyle(color: AppColors.textMuted, height: 1.6)),
      const SizedBox(height: 12),
      WeekPeriodsEditor(days: _days),
    ]);
  }
}
