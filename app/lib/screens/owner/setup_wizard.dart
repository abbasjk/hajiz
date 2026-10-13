import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../theme/colors.dart';
import '../../widgets/common.dart';
import 'editors.dart';

String missingLabel(AppLocalizations l, String code) => switch (code) {
      'businessType' => l.missingBusinessType,
      'address' => l.missingAddress,
      'location' => l.missingLocation,
      'photos' => l.missingPhotos,
      'services' => l.missingServices,
      'hours' => l.missingHours,
      _ => code,
    };

/// طلب فتح المحل بخمس خطوات. كل خطوة تُحفظ في الخادم قبل الانتقال،
/// فيكمل صاحب المحل لاحقاً من حيث توقف، والمحل "مسودة" حتى يُرسل.
class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key, required this.initial, required this.config, this.editOnly = false});
  final OwnerShopState initial;
  final ServerConfig config;

  /// من الإعدادات بعد القبول: تعديل البيانات والعنوان والصور دون إرسال
  final bool editOnly;

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  late OwnerShopState _state = widget.initial;
  int _step = 0;
  bool _busy = false;
  final _editor = GlobalKey<StepEditorState>();

  int get _stepCount => widget.editOnly ? 3 : 5;
  bool get _onReview => !widget.editOnly && _step == _stepCount;

  void _changed(OwnerShopState s) => setState(() => _state = s);

  Future<void> _next() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _editor.currentState?.save() ?? true;
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (widget.editOnly && _step == _stepCount - 1) return Navigator.pop(context, _state);
    setState(() => _step++);
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final state = await runSave(context, () => AppScope.of(context).owner.submit());
    if (!mounted) return;
    setState(() => _busy = false);
    if (state == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.submittedForReview)));
    Navigator.pop(context, state);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final titles = [l.detailsTitle, l.addressTitle, l.photosTitle, l.servicesTitle, l.hoursTitle];
    final labels = [l.stepDetails, l.stepAddress, l.stepPhotos, l.stepShopServices, l.stepHours];
    final shop = _state.shop;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.editOnly)
              Text(l.wizardStep(_step.clamp(0, 4) + 1),
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w400)),
            Text(_onReview ? l.submitTitle : titles[_step]),
          ]),
        ),
        body: Column(children: [
          if (!widget.editOnly)
            // خطوات مرقمة متصلة بخط يتقدم، بأسلوب مراحل الحجز
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Row(children: [
                for (var i = 0; i < 5; i++)
                  Expanded(
                    child: Column(children: [
                      SizedBox(
                        height: 30,
                        child: Stack(alignment: Alignment.center, children: [
                          Row(children: [
                            Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= _step ? AppColors.accent : AppColors.primarySoft))),
                            Expanded(child: Container(height: 3, color: i == 4 ? Colors.transparent : (i < _step ? AppColors.accent : AppColors.primarySoft))),
                          ]),
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _step ? AppColors.accent : (i == _step ? AppColors.primary : AppColors.primarySoft),
                            ),
                            child: i < _step
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : Text('${i + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: i == _step ? Colors.white : AppColors.primaryMuted,
                                    )),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: i <= _step ? AppColors.primary : AppColors.textMuted,
                            fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400,
                          )),
                    ]),
                  ),
              ]),
            ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              if (_onReview) _review(l) else _stepEditor(shop),
            ]),
          ),
        ]),
        bottomNavigationBar: BottomActionBar(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy || (_onReview && _state.missing.isNotEmpty) ? null : (_onReview ? _submit : _next),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_onReview ? l.submitForReview : (widget.editOnly && _step == _stepCount - 1 ? l.saveLabel : l.next)),
          ),
        ),
      ),
    );
  }

  Widget _stepEditor(OwnerShop? shop) {
    // الخطوات بعد الأولى تحتاج محلاً محفوظاً (يُنشأ في الخطوة الأولى)
    return switch (_step) {
      0 => DetailsEditor(key: _editor, shop: shop, config: widget.config, onSaved: _changed),
      1 => AddressEditor(key: _editor, shop: shop, config: widget.config, onSaved: _changed),
      2 => PhotosEditor(key: _editor, shop: shop!, onSaved: _changed),
      3 => ServicesEditor(key: _editor, shop: shop!, onSaved: _changed),
      _ => HoursEditor(key: _editor, shop: shop!, onSaved: _changed),
    };
  }

  Widget _review(AppLocalizations l) {
    final missing = _state.missing;
    const all = ['businessType', 'address', 'location', 'photos', 'services', 'hours'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.storefront, color: Colors.white, size: 30),
          const SizedBox(height: 8),
          Text(_state.shop?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 6),
          Text(missing.isEmpty ? l.readyToSubmit : l.missingItems(missing.map((m) => missingLabel(l, m)).join('، ')),
              style: const TextStyle(color: AppColors.onPrimaryMuted, height: 1.6)),
        ]),
      ),
      const SizedBox(height: 16),
      // قائمة تحقق: ما اكتمل وما ينقص
      for (final code in all)
        Container(
          height: 52,
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Icon(missing.contains(code) ? Icons.radio_button_unchecked : Icons.check_circle,
                color: missing.contains(code) ? AppColors.danger : const Color(0xFF27AE60), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(missingLabel(l, code),
                  style: TextStyle(fontSize: 15, color: missing.contains(code) ? AppColors.danger : AppColors.text)),
            ),
          ]),
        ),
    ]);
  }
}
