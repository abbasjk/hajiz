import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import '../util/phone.dart';
import '../widgets/common.dart';

/// الاسم ورقم الهاتف؛ الرقم نفسه للحجز ولإدارة المحل
class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key, required this.onRegistered});
  final VoidCallback onRegistered;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).ensureRegistered(_name.text.trim(), normalizeIraqiPhone(_phone.text)!);
      widget.onRegistered();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.registerTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(l.registerBody, style: const TextStyle(color: AppColors.textMuted, height: 1.6)),
        const SizedBox(height: 16),
        TextFormField(
          controller: _name,
          decoration: InputDecoration(labelText: l.nameLabel, hintText: l.nameHint),
          validator: (v) => (v ?? '').trim().length < 2 ? l.nameRequired : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          decoration: InputDecoration(labelText: l.phoneLabel, hintText: l.phoneHint),
          validator: (v) => normalizeIraqiPhone(v ?? '') == null ? l.phoneInvalid : null,
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : _submit,
          child: Text(l.continueLabel),
        ),
      ]),
    );
  }
}
