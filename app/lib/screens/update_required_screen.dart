import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/colors.dart';

/// إجبار التحديث: يمنع استخدام نسخة قديمة عند تغيير جذري
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
                child: const Icon(Icons.system_update, size: 60, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(l.updateRequiredTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 8),
              Text(l.updateRequiredBody, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.onPrimaryMuted, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}
