import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hajiz/api/api_client.dart';
import 'package:hajiz/api/models.dart';
import 'package:hajiz/main.dart';
import 'package:hajiz/state/app_scope.dart';
import 'package:hajiz/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خادم وهمي لواجهة صاحب المحل
class FakeOwnerServer {
  final requests = <http.Request>[];
  String status = 'pending_shop';
  String? reason;
  bool verified = false;
  String shopStatus = 'approved';
  final settingsBodies = <Map<String, dynamic>>[];
  final start = DateTime.now().toUtc().add(const Duration(days: 1));

  Map<String, dynamic> get booking => {
        'id': 7,
        'status': status,
        'startsAt': start.toIso8601String(),
        'endsAt': start.add(const Duration(minutes: 30)).toIso8601String(),
        'responseDeadline': status == 'pending_shop' ? DateTime.now().toUtc().add(const Duration(minutes: 40)).toIso8601String() : null,
        'isInstant': false,
        'note': 'قصة قصيرة',
        'cancelReason': reason,
        'customer': {
          'id': 3, 'name': 'حسن', 'phone': ['pending_shop', 'confirmed', 'pending_customer'].contains(status) ? '07701234567' : null,
          'newDevice': !verified, 'stats': {'attended': 8, 'lateCancels': 1, 'noShows': 0},
        },
        'services': [{'name': 'حلاقة شعر', 'durationMinutes': 30, 'priceType': 'fixed', 'price': 10000}],
        'proposedTimes': status == 'pending_customer' ? [{'id': 1, 'startsAt': start.add(const Duration(hours: 2)).toIso8601String()}] : [],
      };

  Map<String, dynamic> get shop => {
        'shop': {
          'id': 1, 'name': 'صالون النخيل', 'status': shopStatus, 'deadlineMode': 'normal', 'freeCancelHours': 2,
          'minLeadMinutes': 180, 'instantBooking': false, 'bufferMinutes': 0,
          'services': [{'id': 11, 'name': 'حلاقة شعر', 'durationMinutes': 30, 'priceType': 'fixed', 'price': 10000, 'active': true}],
          'weeklyHours': [{'dayOfWeek': 6, 'from': '09:00', 'to': '21:00'}],
          'temporarySchedules': [], 'photos': [], 'closures': [],
        },
        'missing': [],
      };

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    Object body;
    if (path == '/v1/config') {
      body = {
        'settings': {'shop_deadline_modes': {'normal': {'tomorrow': 60}}, 'max_pending_requests_per_customer': 2},
        'businessTypes': [{'id': 1, 'name': 'حلاقة رجالية'}], 'districts': [{'id': 1, 'name': 'البصرة'}], 'areas': [],
      };
    } else if (path == '/v1/shops') {
      body = {'shops': []};
    } else if (path == '/v1/me/bookings') {
      body = {'bookings': []};
    } else if (path == '/v1/owner/shop') {
      body = shop;
    } else if (path == '/v1/owner/settings' || path == '/v1/owner/hours') {
      settingsBodies.add(jsonDecode(r.body) as Map<String, dynamic>);
      body = shop;
    } else if (path == '/v1/owner/day') {
      body = {'bookings': []};
    } else if (path == '/v1/owner/dashboard') {
      body = {'pending': status == 'pending_shop' ? [booking] : [], 'today': []};
    } else if (path == '/v1/owner/bookings/7') {
      body = {'booking': booking};
    } else if (path == '/v1/owner/bookings/7/verify-device') {
      verified = true;
      body = {'booking': booking};
    } else if (path == '/v1/owner/bookings/7/reject') {
      status = 'rejected';
      reason = (jsonDecode(r.body) as Map)['reason'] as String;
      body = {'booking': booking};
    } else if (path == '/v1/owner/bookings/7/slots') {
      body = {'slots': [start.add(const Duration(hours: 2)).toIso8601String(), start.add(const Duration(hours: 3)).toIso8601String()]};
    } else if (path == '/v1/owner/bookings/7/propose') {
      status = 'pending_customer';
      body = {'booking': booking};
    } else {
      return http.Response(jsonEncode({'error': {'code': 'not_found'}}), 404);
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  }
}

Future<FakeOwnerServer> openMyShop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appMode': 'shop'});
  final server = FakeOwnerServer();
  final session = await Session.load();
  await session.saveRegistration('tok', const RegisteredUser(1, 'علي', '07800000000'));
  final services = AppServices(
    client: ApiClient(client: MockClient(server.handle), baseUrl: 'https://api.test'),
    session: session,
    locate: () async => null,
  );
  await tester.pumpWidget(HajizApp(services: services));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  return server;
}

void main() {
  testWidgets('dashboard shows the waiting request with a countdown and the new-device badge', (tester) async {
    await openMyShop(tester);
    expect(find.text('صالون النخيل'), findsOneWidget);
    expect(find.text('طلبات تنتظر ردك'), findsOneWidget);
    expect(find.text('حسن'), findsOneWidget);
    expect(find.text('جهاز جديد'), findsOneWidget);
    expect(find.textContaining('00:'), findsOneWidget);
    expect(find.text('قبول'), findsOneWidget);
  });

  testWidgets('request details: verify by phone, then reject with a reason', (tester) async {
    final server = await openMyShop(tester);
    await tester.tap(find.text('التفاصيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('طلب حجز جديد'), findsOneWidget);
    expect(find.text('8'), findsOneWidget); // حضر
    expect(find.text('قصة قصيرة'), findsOneWidget);
    expect(find.text('رقم مستخدم من جهاز جديد'), findsOneWidget);

    await tester.tap(find.text('تم التأكد بالاتصال'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('رقم مستخدم من جهاز جديد'), findsNothing);
    expect(server.requests.last.headers['idempotency-key'], isNotEmpty);

    await tester.tap(find.text('رفض مع سبب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشغول في هذا الوقت'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(server.reason, 'busy');
    expect(find.text('السبب: مشغول في هذا الوقت'), findsOneWidget);
    expect(find.text('يظهر رقم الزبون فقط ما دام الحجز قائماً.'), findsOneWidget);
  });

  testWidgets('propose an alternative time', (tester) async {
    final server = await openMyShop(tester);
    await tester.tap(find.text('التفاصيل'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('اقتراح أوقات بديلة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('0 من 3'), findsOneWidget);
    await tester.tap(find.byType(FilterChip).first);
    await tester.pump();
    expect(find.text('1 من 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'عندي ظرف');
    await tester.tap(find.text('إرسال الاقتراح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final post = server.requests.lastWhere((r) => r.url.path.endsWith('/propose'));
    final body = jsonDecode(post.body) as Map;
    expect(body['times'], hasLength(1));
    expect(body['message'], 'عندي ظرف');
    expect(find.text('بانتظار رد الزبون على الأوقات المقترحة'), findsOneWidget);
  });

  testWidgets('shop mode has its own tabs and switches back to customer mode', (tester) async {
    final server = await openMyShop(tester);
    expect(find.text('الطلبات'), findsOneWidget);
    expect(find.text('حجوزاتي'), findsNothing); // لا شيء من واجهة الزبون

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مرن'));
    await tester.pumpAndSettle();
    expect(server.settingsBodies.last, {'deadlineMode': 'flexible'});

    await tester.tap(find.text('أوقات العمل'));
    await tester.pumpAndSettle();
    expect(find.text('إغلاق طارئ'), findsOneWidget);
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(server.settingsBodies.last['periods'], [{'dayOfWeek': 6, 'from': '09:00', 'to': '21:00'}]);
    await tester.tap(find.text('إغلاق طارئ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تُعرض على أصحابها بأقرب أوقات بديلة'), findsOneWidget);
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('التقويم'));
    await tester.pumpAndSettle();
    expect(find.text('لا حجوزات'), findsOneWidget);

    await tester.tap(find.text('الإعدادات'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('التبديل إلى وضع الزبون'), 200);
    await tester.tap(find.text('التبديل إلى وضع الزبون'));
    await tester.pumpAndSettle();
    expect(find.text('حجوزاتي'), findsOneWidget);
    expect(find.text('الطلبات'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appMode'), 'customer');

    // من "حسابي" يعود إلى وضع المحل
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التبديل إلى وضع المحل'));
    await tester.pumpAndSettle();
    expect(find.text('الطلبات'), findsOneWidget);
  });

  testWidgets('a second device with the owner number cannot manage the shop', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = await Session.load();
    await session.saveRegistration('tok', const RegisteredUser(1, 'علي', '07800000000'));
    final client = MockClient((r) async => r.url.path.startsWith('/v1/owner')
        ? http.Response(jsonEncode({'error': {'code': 'untrusted_device'}}), 403)
        : FakeOwnerServer().handle(r));
    await tester.pumpWidget(HajizApp(
      services: AppServices(client: ApiClient(client: client, baseUrl: 'https://api.test'), session: session, locate: () async => null),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    expect(find.text('هل تملك محلاً؟'), findsOneWidget);
    await tester.tap(find.text('ابدأ طلب فتح المحل'));
    await tester.pumpAndSettle();
    expect(find.text('هذا الجهاز غير موثّق لإدارة المحل'), findsOneWidget);
  });

  testWidgets('a shop under review shows its status and the management shortcuts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final server = FakeOwnerServer()..shopStatus = 'under_review';
    final session = await Session.load();
    await session.saveRegistration('tok', const RegisteredUser(1, 'علي', '07800000000'));
    await tester.pumpWidget(HajizApp(
      services: AppServices(client: ApiClient(client: MockClient(server.handle), baseUrl: 'https://api.test'), session: session, locate: () async => null),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    expect(find.text('طلبك قيد المراجعة'), findsOneWidget);
    await tester.tap(find.text('عرض'));
    await tester.pumpAndSettle();
    expect(find.text('طلبك قيد المراجعة'), findsOneWidget);
    expect(find.text('الخدمات'), findsOneWidget);
    expect(find.text('التقويم'), findsNothing);
  });
}
