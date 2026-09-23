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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Column(children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _step ? AppColors.primary : AppColors.track,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(labels[i],
                          style: TextStyle(
                            fontSize: 11,
                            color: i <= _step ? AppColors.primary : AppColors.textMuted,
                            fontWeight: i == _step ? FontWeight.w600 : FontWeight.w400,
                          )),
                    ]),
                  ),
                ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_state.shop?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (missing.isEmpty)
            Text(l.readyToSubmit, style: const TextStyle(height: 1.6))
          else
            Text(l.missingItems(missing.map((m) => missingLabel(l, m)).join('، ')),
                style: const TextStyle(color: AppColors.danger, height: 1.6)),
        ]),
      ),
    );
  }
}
