import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/owner_models.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../util/links.dart';
import '../widgets/untrusted_device_card.dart';
import 'delete_account_screen.dart';
import 'notifications_screen.dart';
import 'owner/owner_tab.dart';
import 'register_screen.dart';

/// حسابي (وضع الزبون): بيانات الزبون، وبطاقة "هل تملك محلاً؟".
/// صاحب المحل المقبول يبدّل من هنا إلى وضع المحل.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  OwnerShop? _shop;

  /// null: لم يُعرف بعد (أو غير مسجّل)
  bool? _trusted;
  bool _trustRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  /// حالة المحل إن وُجد؛ الجهاز غير الموثوق أو انقطاع الاتصال لا يُظهر شيئاً هنا
  Future<void> refresh() async {
    final services = AppScope.of(context);
    if (!services.session.isRegistered) {
      return setState(() {
        _shop = null;
        _trusted = null;
      });
    }
    try {
      final me = await services.api.me();
      if (mounted) {
        setState(() {
          _trusted = me.trusted;
          _trustRequested = me.trustRequested;
        });
      }
    } catch (_) {
      // دون اتصال تبقى الحالة السابقة
    }
    try {
      final state = await services.owner.shop();
      if (mounted) setState(() => _shop = state.shop);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  /// الدخول دون حجز: بالاسم والرقم نفسيهما
  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    await Navigator.of(context).push(MaterialPageRoute(
      // شاشة الدخول كما في التصميم: أعلى برتقالي، ثم ورقة بيضاء فيها النموذج
      builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.accent,
          body: Column(children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: 190,
                child: Stack(children: [
                  const PositionedDirectional(top: 4, start: 4, child: BackButton(color: Colors.white)),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.2)),
                        child: const Icon(Icons.event_available_rounded, size: 52, color: Colors.white),
                      ),
                      const SizedBox(height: 10),
                      Text(l.signIn, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ]),
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
                ),
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 24), children: [
                  RegisterForm(onRegistered: () => Navigator.of(context).pop()),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ));
    if (mounted) refresh();
  }

  Future<void> _openShop() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OwnerTab()));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final services = AppScope.of(context);
    final user = services.session.user;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Column(
          children: [
            _header(l, user?.name, user?.phone),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
                ),
                child: RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
                    if (user == null) ...[
                      Text(l.signInHint, style: AppText.body.copyWith(height: 1.6)),
                      const SizedBox(height: 10),
                      FilledButton.icon(onPressed: _signIn, icon: const Icon(Icons.login), label: Text(l.signIn)),
                      const SizedBox(height: 16),
                    ],
                    _shopCard(l, services),
                    if (_trusted == false) ...[
                      const SizedBox(height: 16),
                      UntrustedDeviceCard(key: ValueKey(_trustRequested), requested: _trustRequested),
                    ],
                    const SizedBox(height: 8),
                    if (services.session.isRegistered)
                      _row(l.notificationSettingsTitle, Icons.notifications_outlined, () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()))),
                    _row(l.privacyPolicy, Icons.privacy_tip_outlined, openPrivacyPolicy, external: true),
                    if (services.session.isRegistered && _trusted != false)
                      _row(l.deleteAccount, Icons.delete_outline,
                          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
                          danger: true),
                    const SizedBox(height: 24),
                    Text(
                      buildNumber.isEmpty ? l.appVersionLabel(appVersion) : l.appVersionBuildLabel(appVersion, buildNumber),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الرأس البنفسجي: الصورة الرمزية والاسم والرقم
  Widget _header(AppLocalizations l, String? name, String? phone) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.person_outline, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name ?? l.tabAccount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(phone == null ? Icons.info_outline : Icons.call, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        // الرقم يُقرأ من اليسار لليمين لكنه يُحاذى مع بقية النص
                        child: Text(phone ?? l.notRegisteredAccount,
                            textDirection: phone == null ? null : TextDirection.ltr,
                            style: const TextStyle(fontSize: 15, color: Colors.white)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// المحل: صاحب المحل المقبول يرى زر التبديل البرتقالي كما في التصميم، وغيره يرى حالة طلبه
  Widget _shopCard(AppLocalizations l, AppServices services) {
    final shop = _shop;
    if (shop?.status == ShopStatus.approved) {
      return Material(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => services.switchMode(AppMode.shop),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Expanded(
                  child: Text(l.switchToShop,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const Icon(Icons.swap_vert, color: Colors.white, size: 28),
              ]),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.storefront_outlined, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(shop == null ? l.haveShopTitle : shop.name, style: AppText.title)),
        ]),
        const SizedBox(height: 8),
        Text(
          switch (shop?.status) {
            null => l.haveShopBody,
            ShopStatus.approved => l.shopApprovedTitle,
            ShopStatus.draft => l.shopStatusDraft,
            ShopStatus.underReview => l.underReviewTitle,
            ShopStatus.rejected => l.rejectedTitle,
            ShopStatus.suspended => l.suspendedTitle,
          },
          style: AppText.body.copyWith(height: 1.6),
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(48)),
          onPressed: _openShop,
          child: Text(switch (shop?.status) {
            null => l.startApplication,
            ShopStatus.draft => l.continueApplication,
            _ => l.openShopDetails,
          }),
        ),
      ]),
    );
  }

  Widget _row(String title, IconData icon, VoidCallback onTap, {bool danger = false, bool external = false}) => InkWell(
        onTap: onTap,
        child: Container(
          height: 60,
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Icon(icon, color: danger ? AppColors.danger : AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: danger ? AppColors.danger : AppColors.primary)),
            ),
            Icon(external ? Icons.open_in_new : Icons.chevron_right, size: 20, color: AppColors.primaryMuted),
          ]),
        ),
      );
}
