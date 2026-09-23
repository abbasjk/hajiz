import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/deadline.dart';
import '../util/format.dart';
import '../util/phone.dart';
import '../widgets/common.dart';
import 'booking_detail_screen.dart';
import 'booking_draft.dart';
import 'booking_services_screen.dart';

/// الخطوة 3: المراجعة، ملاحظة اختيارية، والاسم ورقم الهاتف عند أول حجز فقط
class BookingReviewScreen extends StatefulWidget {
  const BookingReviewScreen({super.key, required this.draft});
  final BookingDraft draft;

  @override
  State<BookingReviewScreen> createState() => _BookingReviewScreenState();
}

class _BookingReviewScreenState extends State<BookingReviewScreen> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  /// مفتاح واحد لهذه المحاولة: الضغط مرتين أو إعادة الإرسال لا يُنشئ حجزين
  final _idempotencyKey = newIdempotencyKey();

  /// نسخة ثابتة من الوقت المختار: شاشة الوقت خلفنا قد تعيد ضبطه
  late final DateTime _startsAt = widget.draft.startsAt!;
  bool _sending = false;
  DeadlineTable? _deadlines;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final config = await AppScope.of(context).config();
        if (mounted) setState(() => _deadlines = config.shopDeadlineModes[widget.draft.shop.deadlineMode]);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || !(_form.currentState?.validate() ?? true)) return;
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await services.ensureRegistered(_name.text.trim(), normalizeIraqiPhone(_phone.text) ?? _phone.text);
      final booking = await services.api.createBooking(
        shopId: widget.draft.shop.id,
        serviceIds: widget.draft.serviceIds,
        startsAt: _startsAt,
        note: _note.text,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(booking.status == BookingStatus.confirmed ? l.bookingConfirmedNow : l.bookingSent),
      ));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: booking.id, initial: booking)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showError(context, e);
      if (e is ApiException && e.code == 'slot_unavailable') Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final draft = widget.draft;
    final shop = draft.shop;
    final registered = AppScope.of(context).session.isRegistered;
    final now = AppScope.of(context).client.serverNow;
    final freeCancel = formatDuration(l, shop.freeCancelHours * 60);
    final deadline = _deadlines == null
        ? null
        : formatDuration(l, expectedDeadlineMinutes(_deadlines!, now, _startsAt));

    return Scaffold(
      appBar: BookingAppBar(shopName: shop.name),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const BookingSteps(current: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _row(l.reviewAppointment, formatAppointment(l, _startsAt)),
                          _row(l.reviewServices, draft.services.map((s) => s.name).join('، ')),
                          _row(l.reviewDuration, l.minutes(draft.durationMinutes)),
                          const Divider(height: 20),
                          _row(l.reviewTotal, formatTotal(l, draft.services), bold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(l.noteLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(controller: _note, maxLines: 3, maxLength: 300, decoration: InputDecoration(hintText: l.noteHint)),
                  if (!registered) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(l.yourDetails, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _name,
                              decoration: InputDecoration(labelText: l.nameLabel, hintText: l.nameHint),
                              validator: (v) => (v ?? '').trim().length < 2 ? l.nameRequired : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              // الرقم يُكتب ويُقرأ من اليسار لليمين حتى داخل واجهة عربية
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.right,
                              decoration: InputDecoration(labelText: l.phoneLabel, hintText: l.phoneHint),
                              validator: (v) => normalizeIraqiPhone(v ?? '') == null ? l.phoneInvalid : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.schedule, size: 20, color: AppColors.primaryDark),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            shop.instantBooking
                                ? l.instantInfo(freeCancel)
                                : l.holdInfo(deadline ?? '…', freeCancel),
                            style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.primaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l.sendRequest),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: bold ? AppColors.text : AppColors.textMuted, fontWeight: bold ? FontWeight.w600 : null)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
            ),
          ],
        ),
      );
}
