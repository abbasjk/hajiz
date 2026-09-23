import '../api/api_client.dart';
import '../l10n/app_localizations.dart';

/// يحوّل رمز الخطأ من الخادم إلى نص من ملف الترجمة.
String errorMessage(AppLocalizations l, Object error) {
  if (error is NetworkException) return l.errNetwork;
  if (error is! ApiException) return l.errGeneric;
  return switch (error.code) {
    'slot_unavailable' => l.errSlotUnavailable,
    'too_many_pending' => l.errTooManyPending,
    'time_no_longer_available' => l.errTimeNoLongerAvailable,
    'booking_expired' => l.errBookingExpired,
    'invalid_transition' => l.errInvalidTransition,
    'shop_not_found' => l.errShopNotFound,
    'own_shop' => l.errOwnShop,
    'not_allowed' => l.errNotAllowed,
    'invalid_phone' => l.errInvalidPhone,
    _ => l.errGeneric,
  };
}
