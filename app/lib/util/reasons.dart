import '../l10n/app_localizations.dart';

/// أسباب الرفض والإلغاء تُحفظ كرموز ثابتة وتُترجم هنا
const rejectReasons = ['busy', 'service_unavailable', 'closed', 'other'];
const shopCancelReasons = ['emergency', 'closed', 'other'];

String reasonText(AppLocalizations l, String code) => switch (code) {
      'busy' => l.reasonBusy,
      'service_unavailable' => l.reasonServiceUnavailable,
      'closed' => l.reasonClosed,
      'emergency' => l.reasonEmergency,
      'emergency_closure' => l.reasonEmergencyClosure,
      'other' => l.reasonOther,
      _ => code,
    };
