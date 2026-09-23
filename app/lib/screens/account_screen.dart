import 'package:flutter/material.dart';

import '../api/owner_models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_scope.dart';
import '../theme/colors.dart';
import 'notifications_screen.dart';
import 'owner/owner_tab.dart';

/// حسابي (وضع الزبون): بيانات الزبون، وبطاقة "هل تملك محلاً؟".
/// صاحب المحل المقبول يبدّل من هنا إلى وضع المحل.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  OwnerShop? _shop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  /// حالة المحل إن وُجد؛ الجهاز غير الموثوق أو انقطاع الاتصال لا يُظهر شيئاً هنا
  Future<void> refresh() async {
    final services = AppScope.of(context);
    if (!services.session.isRegistered) return setState(() => _shop = null);
    try {
      final state = await services.owner.shop();
      if (mounted) setState(() => _shop = state.shop);
    } catch (_) {
      if (mounted) setState(() {});
    }
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
    final shop = _shop;
    return Scaffold(
      appBar: AppBar(title: Text(l.tabAccount)),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: AppColors.primarySoft, child: Icon(Icons.person_outline, color: AppColors.primary)),
              title: Text(user?.name ?? l.tabAccount, style: const TextStyle(fontWeight: FontWeight.w600)),
              // الرقم يُقرأ من اليسار لليمين لكنه يُحاذى مع بقية النص
              subtitle: Text(user?.phone ?? l.notRegisteredAccount,
                  textDirection: user == null ? null : TextDirection.ltr, textAlign: TextAlign.right),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.storefront_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(shop == null ? l.haveShopTitle : shop.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
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
                  style: const TextStyle(color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 12),
                if (shop?.status == ShopStatus.approved)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => services.switchMode(AppMode.shop),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l.switchToShop),
                  )
                else
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _openShop,
                    child: Text(switch (shop?.status) {
                      null => l.startApplication,
                      ShopStatus.draft => l.continueApplication,
                      _ => l.openShopDetails,
                    }),
                  ),
              ]),
            ),
          ),
          if (services.session.isRegistered) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_outlined, color: AppColors.primary),
                title: Text(l.notificationSettingsTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen())),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
