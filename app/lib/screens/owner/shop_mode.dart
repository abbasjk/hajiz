import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../api/owner_models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import 'manage_screens.dart';
import 'owner_tab.dart';

/// وضع المحل: واجهة صاحب المحل وحدها، بتبويباتها الخاصة.
/// إذا لم يعد المحل مقبولاً (أو تعذّر التحقق) يعود التطبيق لوضع الزبون.
class ShopModeShell extends StatefulWidget {
  const ShopModeShell({super.key});

  @override
  State<ShopModeShell> createState() => _ShopModeShellState();
}

class _ShopModeShellState extends State<ShopModeShell> {
  OwnerShopState? _state;
  ServerConfig? _config;
  Object? _error;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    setState(() => _error = null);
    try {
      final results = await Future.wait([services.owner.shop(), services.config(refresh: true)]);
      if (!mounted) return;
      final state = results[0] as OwnerShopState;
      if (state.shop?.status != ShopStatus.approved) {
        await services.switchMode(AppMode.customer);
        return;
      }
      setState(() => (_state = state, _config = results[1] as ServerConfig));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _changed(OwnerShopState s) => setState(() => _state = s);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shop = _state?.shop;
    if (shop == null || _config == null) {
      return Scaffold(
        body: LoadState(error: _error, onRetry: _load),
        // عند تعذّر الاتصال يبقى الخروج إلى وضع الزبون ممكناً
        bottomNavigationBar: _error == null
            ? null
            : BottomActionBar(
                child: OutlinedButton(
                  onPressed: () => AppScope.of(context).switchMode(AppMode.customer),
                  child: Text(l.switchToCustomer),
                ),
              ),
      );
    }
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        OwnerDashboard(shop: shop, config: _config!, onShopChanged: _changed),
        const CalendarScreen(),
        ServicesScreen(key: ValueKey('services-${shop.services.length}'), shop: shop, embedded: true, onChanged: _changed),
        SettingsScreen(shop: shop, config: _config!, embedded: true, onChanged: _changed),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.inbox_outlined), label: l.tabRequests),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), label: l.menuCalendar),
          NavigationDestination(icon: const Icon(Icons.list_alt), label: l.menuServices),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: l.menuSettings),
        ],
      ),
    );
  }
}
