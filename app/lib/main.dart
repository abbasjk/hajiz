import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/api_client.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/account_screen.dart';
import 'screens/owner/shop_mode.dart';
import 'screens/update_required_screen.dart';
import 'state/app_scope.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await Session.load();
  runApp(HajizApp(services: AppServices(client: ApiClient(), session: session)));
}

class HajizApp extends StatelessWidget {
  const HajizApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // عربي بالكامل ومن اليمين لليسار؛ الكردية السورانية تُضاف بملف ترجمة آخر بالاتجاه نفسه
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: services.client.updateRequired,
          builder: (context, mustUpdate, _) => mustUpdate
              ? const UpdateRequiredScreen()
              : OfflineBanner(offline: services.client.offline, child: child!),
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final services = AppScope.of(context);
      // يفتح التطبيق على آخر وضع استُخدم؛ وضع المحل يتحقق من المحل عند الفتح
      if (services.session.isRegistered && services.session.appMode == AppMode.shop.name) {
        services.mode.value = AppMode.shop;
      }
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold();
    return ValueListenableBuilder<AppMode>(
      valueListenable: AppScope.of(context).mode,
      builder: (context, mode, _) => mode == AppMode.shop ? const ShopModeShell() : const CustomerShell(),
    );
  }
}

/// وضع الزبون: الرئيسية، حجوزاتي، حسابي
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _tab = 0;
  final _bookingsKey = GlobalKey<MyBookingsScreenState>();
  final _accountKey = GlobalKey<AccountScreenState>();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [const HomeScreen(), MyBookingsScreen(key: _bookingsKey), AccountScreen(key: _accountKey)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _bookingsKey.currentState?.refresh();
          if (i == 2) _accountKey.currentState?.refresh();
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), label: l.tabHome),
          NavigationDestination(icon: const Icon(Icons.event_note_outlined), label: l.tabMyBookings),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: l.tabAccount),
        ],
      ),
    );
  }
}
