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

/// خادم وهمي بالشكل نفسه الذي يرسله الخادم الحقيقي
class FakeServer {
  final requests = <http.Request>[];
  String bookingStatus = 'pending_shop';
  int bookingPosts = 0;
  int? failWith;

  final slot = DateTime.now().toUtc().add(const Duration(days: 1));
  DateTime get deadline => DateTime.now().toUtc().add(const Duration(minutes: 42));

  Map<String, dynamic> get booking => {
        'id': 5,
        'status': bookingStatus,
        'startsAt': slot.toIso8601String(),
        'endsAt': slot.add(const Duration(minutes: 45)).toIso8601String(),
        'responseDeadline': bookingStatus == 'pending_shop' ? deadline.toIso8601String() : null,
        'isInstant': false,
        'note': null,
        'shop': {'id': 1, 'name': 'صالون تجريبي', 'phone': '07700000000', 'latitude': 30.5, 'longitude': 47.8, 'freeCancelHours': 2},
        'services': [
          {'name': 'حلاقة شعر', 'durationMinutes': 30, 'priceType': 'fixed', 'price': 10000},
          {'name': 'تهذيب لحية', 'durationMinutes': 15, 'priceType': 'fixed', 'price': 5000},
        ],
        'proposedTimes': [],
      };

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    Map<String, dynamic> body;
    if (failWith != null) {
      return http.Response(jsonEncode({'error': {'code': 'update_required'}}), failWith!);
    }
    if (path == '/v1/config') {
      body = {
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'settings': {
          'shop_deadline_modes': {
            'normal': {'same_day_under_6h': 15, 'same_day': 30, 'tomorrow': 60, 'within_week': 240, 'week_or_more': 720},
          },
          'max_pending_requests_per_customer': 2,
        },
        'businessTypes': [{'id': 1, 'name': 'حلاقة رجالية'}],
        'districts': [{'id': 1, 'name': 'البصرة'}],
        'areas': [],
      };
    } else if (path == '/v1/shops') {
      body = {
        'shops': [
          {'id': 1, 'name': 'صالون تجريبي', 'businessType': 'حلاقة رجالية', 'area': 'منطقة تجريبية', 'committed': true, 'instantBooking': false},
        ],
      };
    } else if (path == '/v1/shops/1') {
      body = {
        'shop': {
          'id': 1, 'name': 'صالون تجريبي', 'phone': '07700000000', 'businessType': 'حلاقة رجالية',
          'instantBooking': false, 'deadlineMode': 'normal', 'freeCancelHours': 2, 'committed': true,
          'photos': [],
          'services': [
            {'id': 11, 'name': 'حلاقة شعر', 'durationMinutes': 30, 'priceType': 'fixed', 'price': 10000},
            {'id': 12, 'name': 'تهذيب لحية', 'durationMinutes': 15, 'priceType': 'fixed', 'price': 5000},
          ],
          'weeklyHours': [for (var d = 0; d < 7; d++) {'dayOfWeek': d, 'from': '09:00', 'to': '22:00'}],
          'temporarySchedules': [],
        },
      };
    } else if (path == '/v1/shops/1/slots') {
      body = {'slots': [slot.toIso8601String()]};
    } else if (path == '/v1/auth/register') {
      body = {'token': 'tok', 'user': {'id': 9, 'name': 'حسن', 'phone': '07701234567'}, 'trustedDevice': true};
    } else if (path == '/v1/bookings' && r.method == 'POST') {
      bookingPosts++;
      body = {'booking': booking, 'serverTime': DateTime.now().toUtc().toIso8601String()};
    } else if (path == '/v1/bookings/5/cancel') {
      bookingStatus = 'cancelled_by_customer';
      body = {'booking': booking};
    } else if (path == '/v1/bookings/5') {
      body = {'booking': booking, 'serverTime': DateTime.now().toUtc().toIso8601String()};
    } else if (path == '/v1/me/bookings') {
      body = {'bookings': [booking], 'serverTime': DateTime.now().toUtc().toIso8601String()};
    } else {
      return http.Response(jsonEncode({'error': {'code': 'not_found'}}), 404);
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  }
}

Future<(FakeServer, AppServices)> startApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final server = FakeServer();
  final services = AppServices(client: ApiClient(client: MockClient(server.handle), baseUrl: 'https://api.test'), session: await Session.load(), locate: () async => null);
  await tester.pumpWidget(HajizApp(services: services));
  await tester.pumpAndSettle();
  return (server, services);
}

void main() {
  testWidgets('browse, book in three steps, and see the countdown', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final (server, services) = await startApp(tester);

    // الرئيسية: المحل مع شارة الالتزام، والتطبيق من اليمين لليسار
    expect(find.text('صالون تجريبي'), findsOneWidget);
    expect(find.text('ملتزم بمواعيده'), findsOneWidget);
    expect(Directionality.of(tester.element(find.text('صالون تجريبي'))), TextDirection.rtl);

    await tester.tap(find.text('صالون تجريبي'));
    await tester.pumpAndSettle();
    expect(find.text('10,000 د.ع'), findsOneWidget);

    await tester.tap(find.text('احجز موعداً'));
    await tester.pumpAndSettle();

    // الخطوة 1: خدمتان، تُجمع المدة والسعر
    await tester.tap(find.text('حلاقة شعر'));
    await tester.tap(find.text('تهذيب لحية'));
    await tester.pump();
    expect(find.text('خدمتان · 45 دقيقة'), findsOneWidget);
    expect(find.text('المجموع: 15,000 د.ع'), findsOneWidget);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    // الخطوة 2: الأوقات المتاحة فقط، بتوقيت بغداد
    final slotRequest = server.requests.lastWhere((r) => r.url.path.endsWith('/slots'));
    expect(slotRequest.url.queryParameters['services'], '11,12');
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    // الخطوة 3: الاسم والرقم عند أول حجز، والمحل يرد خلال ساعة (موعد الغد)
    expect(find.textContaining('يرد خلال ساعة واحدة'), findsOneWidget);
    await tester.tap(find.text('إرسال طلب الحجز'));
    await tester.pump();
    expect(find.text('اكتب اسمك'), findsOneWidget);
    expect(server.bookingPosts, 0);

    await tester.enterText(find.widgetWithText(TextFormField, 'الاسم'), 'حسن');
    await tester.enterText(find.widgetWithText(TextFormField, 'رقم الهاتف'), '0770 123 4567');
    await tester.tap(find.text('إرسال طلب الحجز'));
    await tester.tap(find.text('إرسال طلب الحجز'), warnIfMissed: false); // ضغطة ثانية سريعة
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final register = server.requests.firstWhere((r) => r.url.path == '/v1/auth/register');
    expect(jsonDecode(register.body)['phone'], '07701234567');
    expect(server.bookingPosts, 1);
    final post = server.requests.firstWhere((r) => r.url.path == '/v1/bookings');
    expect(post.headers['idempotency-key'], isNotEmpty);
    expect(post.headers['authorization'], 'Bearer tok');
    expect(post.headers['x-app-version'], '0.3.0');
    expect(services.session.isRegistered, isTrue);

    // تفاصيل الطلب مع العداد التنازلي
    expect(find.text('بانتظار رد المحل'), findsWidgets);
    expect(find.textContaining('00:4'), findsOneWidget);

    // الإلغاء المبكر مجاني
    await tester.tap(find.text('إلغاء الحجز'));
    await tester.pumpAndSettle();
    expect(find.text('الإلغاء الآن مجاني.'), findsOneWidget);
    await tester.tap(find.text('نعم، ألغِ الحجز'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ألغيته'), findsWidgets);
    expect(server.requests.where((r) => r.url.path == '/v1/bookings/5/cancel'), hasLength(1));
  });

  testWidgets('shows the update screen when the server requires a newer version', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = FakeServer()..failWith = 426;
    final services = AppServices(client: ApiClient(client: MockClient(server.handle), baseUrl: 'https://api.test'), session: await Session.load(), locate: () async => null);
    await tester.pumpWidget(HajizApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
  });

  testWidgets('shows the offline banner and keeps my bookings from the last load', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = FakeServer();
    var online = true;
    final client = MockClient((r) async => online ? server.handle(r) : throw http.ClientException('offline'));
    final session = await Session.load();
    await session.saveRegistration('tok', const RegisteredUser(9, 'حسن', '07701234567'));
    final services = AppServices(client: ApiClient(client: client, baseUrl: 'https://api.test'), session: session, locate: () async => null);
    await tester.pumpWidget(HajizApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('حجوزاتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('صالون تجريبي'), findsOneWidget);
    expect(find.text('لا يوجد اتصال'), findsNothing);

    online = false;
    await tester.tap(find.text('الرئيسية'));
    await tester.pump();
    await tester.tap(find.text('حجوزاتي'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('لا يوجد اتصال'), findsOneWidget);
    expect(find.text('صالون تجريبي'), findsOneWidget);
    expect(find.textContaining('آخر تحديث'), findsOneWidget);
  });
}
