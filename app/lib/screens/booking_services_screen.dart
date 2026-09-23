import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../theme/colors.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import 'booking_draft.dart';
import 'booking_time_screen.dart';

/// الخطوة 1: اختيار خدمة أو أكثر، وتُجمع مدتها
class BookingServicesScreen extends StatefulWidget {
  const BookingServicesScreen({super.key, required this.shop});
  final ShopDetails shop;

  @override
  State<BookingServicesScreen> createState() => _BookingServicesScreenState();
}

class _BookingServicesScreenState extends State<BookingServicesScreen> {
  late final BookingDraft _draft = BookingDraft(widget.shop);

  void _toggle(Service s) => setState(() {
        if (_draft.services.contains(s)) {
          _draft.services.remove(s);
        } else {
          _draft.services.add(s);
        }
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final selected = _draft.services;
    return Scaffold(
      appBar: BookingAppBar(shopName: widget.shop.name),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BookingSteps(current: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l.chooseServices, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: widget.shop.services.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final s = widget.shop.services[i];
                final on = selected.contains(s);
                return Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: on ? AppColors.primary : AppColors.border, width: on ? 2 : 1),
                  ),
                  child: CheckboxListTile(
                    value: on,
                    onChanged: (_) => _toggle(s),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(l.minutes(s.durationMinutes)),
                    secondary: Text(formatPrice(l, s), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: [
            Expanded(
              child: selected.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.servicesCount(selected.length, _draft.durationMinutes),
                            style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        Text(l.total(formatTotal(l, selected)),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingTimeScreen(draft: _draft))),
              child: Text(l.next),
            ),
          ],
        ),
      ),
    );
  }
}

/// رأس شاشات الحجز: "حجز موعد" واسم المحل؛ سهم الرجوع يُعكس تلقائياً
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
