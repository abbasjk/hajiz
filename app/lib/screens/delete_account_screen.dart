import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';

/// حذف الحساب: يعرض ما سيحدث بالضبط، ثم يحذف بعد تأكيد صريح.
/// متاح من الهاتف الذي سُجّل به الرقم أول مرة فقط (الخادم يرفض غيره).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  DeletionPreview? _preview;
  Object? _error;
  bool _understood = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await AppScope.of(context).api.deletionPreview();
      if (mounted) setState(() => _preview = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete() async {
    final services = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await services.api.deleteAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      return showError(context, e);
    }
    final nav = Navigator.of(context);
    final messenger = services.messengerKey.currentState;
    await services.forgetAccount();
    nav.popUntil((r) => r.isFirst);
    messenger?.showSnackBar(SnackBar(content: Text(l.accountDeleted)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: Text(l.deleteAccount)),
      body: p == null
          ? LoadState(error: _error, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.deleteAccountTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(l.deleteAccountIntro, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                _point(Icons.person_off_outlined, l.deleteWhatName),
                _point(Icons.event_busy_outlined, l.deleteWhatBookings(p.upcomingBookings)),
                if (p.upcomingBookings > 0) _point(Icons.info_outline, l.deleteWhatLate),
                if (p.shopName != null) ...[
                  _point(Icons.store_outlined, l.deleteWhatShop(p.shopName!), danger: true),
                  _point(Icons.event_busy_outlined, l.deleteWhatShopBookings(p.shopUpcomingBookings)),
                ],
                _point(Icons.history, l.deleteWhatKept),
                _point(Icons.phone_iphone, l.deleteWhatAgain),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _understood,
                  onChanged: _busy ? null : (v) => setState(() => _understood = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.danger,
                  title: Text(l.deleteConfirmCheck),
                ),
              ],
            ),
      bottomNavigationBar: p == null
          ? null
          : BottomActionBar(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: !_understood || _busy ? null : _delete,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(l.deleteConfirmButton),
              ),
            ),
    );
  }

  Widget _point(IconData icon, String text, {bool danger = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: danger ? AppColors.danger : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(height: 1.6, color: danger ? AppColors.danger : AppColors.text, fontWeight: danger ? FontWeight.w600 : null)),
          ),
        ]),
      );
}
