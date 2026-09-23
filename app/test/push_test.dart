import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hajiz/api/api_client.dart';
import 'package:hajiz/api/models.dart';
import 'package:hajiz/main.dart';
import 'package:hajiz/screens/booking_detail_screen.dart';
import 'package:hajiz/state/app_scope.dart';
import 'package:hajiz/state/push.dart';
import 'package:hajiz/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'owner_flow_test.dart' show FakeOwnerServer;

class FakePush implements PushService {
  PushPermission granted = PushPermission.granted;
  final foregroundCtrl = StreamController<PushEvent>.broadcast();
  final openedCtrl = StreamController<PushEvent>.broadcast();
  PushEvent? launchedFrom;

  @override
  Future<PushPermission> init() async => granted;
  @override
  Future<PushPermission> permission() async => granted;
  @override
  Future<String?> token() async => 'fcm-token-1';
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
  @override
  Stream<PushEvent> get foreground => foregroundCtrl.stream;
  @override
  Stream<PushEvent> get opened => openedCtrl.stream;
  @override
  Future<PushEvent?> initial() async => launchedFrom;
}

/// خادم المحل الوهمي مع مسارات الإشعارات
class FakeServer extends FakeOwnerServer {
  int unread = 0;
  final pushTokens = <Map<String, dynamic>>[];
  var marked = 0;

  @override
  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path;
    Object? body;
    if (path == '/v1/me/push-token') {
      pushTokens.add(jsonDecode(r.body) as Map<String, dynamic>);
      body = {'ok': true};
    } else if (path == '/v1/me/notifications') {
      body = {
        'notifications': [
          {'id': 1, 'type': 'new_request', 'bookingId': 7, 'title': 'طلب حجز جديد', 'body': 'حسن يطلب موعداً.', 'read': unread == 0,
            'createdAt': DateTime.now().toUtc().subtract(const Duration(minutes: 3)).toIso8601String()},
        ],
        'unreadCount': unread,
      };
    } else if (path == '/v1/me/notifications/read') {
      marked++;
      unread = 0;
      body = {'ok': true};
    }
    if (body == null) return super.handle(r);
    requests.add(r);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  }
}

Future<(FakeServer, FakePush, AppServices)> start(WidgetTester tester, {String mode = 'customer', FakePush? push}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'appMode': mode});
  final server = FakeServer();
  final fake = push ?? FakePush();
  final session = await Session.load();
  await session.saveRegistration('tok', const RegisteredUser(1, 'علي', '07800000000'));
  final services = AppServices(
    client: ApiClient(client: MockClient(server.handle), baseUrl: 'https://api.test'),
    session: session,
    locate: () async => null,
    push: fake,
  );
  await tester.pumpWidget(HajizApp(services: services));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return (server, fake, services);
}

void main() {
  testWidgets('sends the push token and opens a shop notification in shop mode', (tester) async {
    final (server, push, services) = await start(tester);
    expect(server.pushTokens, [{'token': 'fcm-token-1', 'enabled': true}]);
    expect(services.mode.value, AppMode.customer);

    push.openedCtrl.add(const PushEvent(type: 'new_request', audience: 'shop', bookingId: 7));
    await tester.pumpAndSettle();
    expect(services.mode.value, AppMode.shop);
    expect(find.text('قصة قصيرة'), findsOneWidget); // تفاصيل الطلب نفسه
    expect(find.text('رقم مستخدم من جهاز جديد'), findsOneWidget);
  });

  testWidgets('a notification while the app is open shows a banner and updates the bell', (tester) async {
    final (server, push, _) = await start(tester, mode: 'shop');
    final bellCount = find.descendant(of: find.byType(Badge), matching: find.text('1'));
    expect(find.byType(Badge), findsOneWidget);
    expect(bellCount, findsNothing);

    server.unread = 1;
    push.foregroundCtrl.add(const PushEvent(type: 'new_request', audience: 'shop', bookingId: 7, title: 'طلب حجز جديد', body: 'حسن يطلب موعداً.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('طلب حجز جديد'), findsOneWidget);
    expect(bellCount, findsOneWidget);

    await tester.tap(find.byTooltip('الإشعارات'));
    await tester.pumpAndSettle();
    expect(find.text('حسن يطلب موعداً.'), findsWidgets);
    expect(find.text('قبل 3 د'), findsOneWidget);
    expect(server.marked, 1);
  });

  testWidgets('warns the owner when notifications are turned off on the phone', (tester) async {
    await start(tester, mode: 'shop', push: FakePush()..granted = PushPermission.denied);
    expect(find.text('الإشعارات متوقفة على هذا الهاتف'), findsOneWidget);
    expect(find.text('تفعيل الإشعارات'), findsOneWidget);
  });

  testWidgets('opening the app from a customer notification shows that booking', (tester) async {
    final push = FakePush()..launchedFrom = const PushEvent(type: 'accepted', audience: 'customer', bookingId: 7);
    final (_, _, services) = await start(tester, mode: 'shop', push: push);
    await tester.pumpAndSettle();
    expect(services.mode.value, AppMode.customer);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
  });
}
