import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import 'common.dart';

/// بطاقة الهاتف غير الموثوق: تشرح السبب، وتتيح طلب التوثيق من الإدارة.
/// forShop: الصياغة من جهة إدارة المحل.
class UntrustedDeviceCard extends StatefulWidget {
  const UntrustedDeviceCard({super.key, this.forShop = false, this.requested});
  final bool forShop;

  /// هل أُرسل طلب سابقاً؛ إن لم يُعرف تجلبه البطاقة بنفسها
  final bool? requested;

  @override
  State<UntrustedDeviceCard> createState() => _UntrustedDeviceCardState();
}

class _UntrustedDeviceCardState extends State<UntrustedDeviceCard> {
  bool? _requested;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _requested = widget.requested;
    if (_requested == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final me = await AppScope.of(context).api.me();
      if (mounted) setState(() => _requested = me.trustRequested);
    } catch (_) {
      if (mounted) setState(() => _requested = false);
    }
  }

  Future<void> _request() async {
    final l = AppLocalizations.of(context);
    final api = AppScope.of(context).api;
    final note = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.requestTrustTitle),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l.requestTrustBody, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          TextField(controller: note, maxLength: 300, decoration: InputDecoration(hintText: l.requestTrustNoteHint)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.requestTrustSend)),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (send != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.requestTrust(text);
      if (mounted) setState(() => _requested = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final requested = _requested;
    return Card(
      color: AppColors.warningSoft,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.phonelink_lock_outlined, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.forShop ? l.untrustedDeviceTitle : l.untrustedPhoneTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.warning)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(widget.forShop ? l.untrustedDeviceBody : l.untrustedPhoneBody, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          if (requested == true)
            Row(children: [
              const Icon(Icons.schedule, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text(l.trustRequestedNote, style: const TextStyle(color: AppColors.textMuted))),
            ])
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: requested == null || _busy ? null : _request,
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(l.requestTrustButton),
            ),
        ]),
      ),
    );
  }
}
