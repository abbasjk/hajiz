import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';

/// شاشات التعريف الثلاث عند أول فتح، كما في التصميم:
/// أعلى بنفسجي برسم، وأسفل برتقالي بالعنوان والشرح والنقاط والزر
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) return widget.onDone();
    _pages.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pages = [
      (Icons.calendar_month_rounded, l.onboardTitle1, l.onboardBody1),
      (Icons.notifications_active_rounded, l.onboardTitle2, l.onboardBody2),
      (Icons.storefront_rounded, l.onboardTitle3, l.onboardBody3),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Column(children: [
          SafeArea(
            bottom: false,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: widget.onDone,
                child: Text(l.onboardSkip, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (icon, _, _) in pages)
                  Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
                      alignment: Alignment.center,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
                        child: Icon(icon, size: 90, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 28, 20, 20 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.hero)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(_page),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pages[_page].$2,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: Text(pages[_page].$3, style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.white)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_page == 2 ? l.onboardStart : l.next),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
