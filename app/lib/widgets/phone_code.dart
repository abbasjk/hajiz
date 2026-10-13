import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/errors.dart';
import 'common.dart';

/// التسجيل بالاسم والرقم: إذا كان الخادم يطلب رمز تحقق تُفتح شاشة الرمز،
/// وإلا يُسجَّل مباشرة. يعيد true عند نجاح التسجيل.
/// أخطاء طلب الرمز الأول (الشبكة، الحدود) تُرمى للمستدعي ليعرضها.
Future<bool> registerWithCode(BuildContext context, String name, String phone) async {
  final services = AppScope.of(context);
  if (services.session.isRegistered) return true;
  final required = await services.api.requestCode(phone);
  if (!required) {
    await services.ensureRegistered(name, phone);
    return true;
  }
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => PhoneCodeScreen(name: name, phone: phone)),
  );
  return ok == true;
}

/// إدخال رمز التحقق: ستة أرقام، يُرسل تلقائياً عند اكتمالها، وإعادة إرسال بعد دقيقة
class PhoneCodeScreen extends StatefulWidget {
  const PhoneCodeScreen({super.key, required this.name, required this.phone});
  final String name;
  final String phone;

  @override
  State<PhoneCodeScreen> createState() => _PhoneCodeScreenState();
}

class _PhoneCodeScreenState extends State<PhoneCodeScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _wait = 60;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer([int seconds = 60]) {
    setState(() => _wait = seconds);
    _runTimer();
  }

  void _runTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (_busy || code.length != 6) return;
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    setState(() => (_busy = true, _error = null));
    try {
      await services.ensureRegistered(widget.name, widget.phone, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l, e);
      });
      _code.clear();
    }
  }

  Future<void> _resend() async {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    setState(() => (_busy = true, _error = null));
    try {
      await services.api.requestCode(widget.phone);
      if (!mounted) return;
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.codeResent)));
    } catch (e) {
      if (!mounted) return;
      final retry = e is ApiException ? (e.details['retryAfter'] as num?)?.toInt() : null;
      if (retry != null) _startTimer(retry);
      setState(() => _error = errorMessage(l, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.codeTitle, style: AppText.headline)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: const Icon(Icons.sms_outlined, size: 44, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          // الرقم يُقرأ من اليسار لليمين داخل الجملة العربية
          l.codeSentTo('⁦${widget.phone}⁩'),
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(height: 1.7, color: AppColors.text),
        ),
        const SizedBox(height: 24),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 14, color: AppColors.primary),
            decoration: const InputDecoration(counterText: '', hintText: '------'),
            onChanged: (v) {
              if (v.length == 6) _submit();
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, height: 1.5)),
        ],
        const SizedBox(height: 16),
        Center(
          child: _wait > 0
              ? Text(l.codeResendIn(_wait), style: AppText.body)
              : TextButton(onPressed: _busy ? null : _resend, child: Text(l.codeResend)),
        ),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(l.codeWrongNumber, style: const TextStyle(color: AppColors.textMuted)),
          ),
        ),
      ]),
      bottomNavigationBar: BottomActionBar(
        child: FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l.codeConfirm),
        ),
      ),
    );
  }
}
