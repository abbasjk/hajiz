import 'api_client.dart';
import 'models.dart';

/// كل مسارات الخادم التي يستخدمها تطبيق الزبون.
class HajizApi {
  HajizApi(this.client);
  final ApiClient client;

  Future<ServerConfig> config() async => ServerConfig.fromJson(await client.get('/config'));

  Future<List<ShopSummary>> shops({
    int? businessTypeId,
    int? districtId,
    int? areaId,
    String? query,
    double? lat,
    double? lng,
    String sort = 'name',
  }) async {
    final json = await client.get('/shops', query: {
      if (businessTypeId != null) 'businessTypeId': '$businessTypeId',
      if (districtId != null) 'districtId': '$districtId',
      if (areaId != null) 'areaId': '$areaId',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'},
      'sort': sort,
    });
    return [for (final s in json['shops'] as List) ShopSummary.fromJson(s)];
  }

  Future<ShopDetails> shop(int id) async =>
      ShopDetails.fromJson((await client.get('/shops/$id'))['shop'] as Map<String, dynamic>);

  /// date بصيغة YYYY-MM-DD بتقويم بغداد
  Future<List<DateTime>> slots(int shopId, String date, List<int> serviceIds) async {
    final json = await client.get('/shops/$shopId/slots', query: {'date': date, 'services': serviceIds.join(',')});
    return [for (final s in json['slots'] as List) DateTime.parse(s as String).toUtc()];
  }

  Future<({String token, RegisteredUser user})> register(String name, String phone, String deviceId) async {
    final json = await client.post('/auth/register', body: {'name': name, 'phone': phone, 'deviceIdentifier': deviceId});
    return (token: json['token'] as String, user: RegisteredUser.fromJson(json['user'] as Map<String, dynamic>));
  }

  Future<Booking> createBooking({
    required int shopId,
    required List<int> serviceIds,
    required DateTime startsAt,
    String? note,
    required String idempotencyKey,
  }) async {
    final json = await client.post('/bookings', idempotencyKey: idempotencyKey, body: {
      'shopId': shopId,
      'serviceIds': serviceIds,
      'startsAt': startsAt.toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Booking.fromJson(json['booking'] as Map<String, dynamic>);
  }

  /// يعيد النص الخام أيضاً ليُحفظ ويظهر عند انقطاع الاتصال
  Future<({List<Booking> bookings, Map<String, dynamic> raw})> myBookings() async {
    final json = await client.get('/me/bookings');
    return (bookings: parseBookings(json), raw: json);
  }

  static List<Booking> parseBookings(Map<String, dynamic> json) =>
      [for (final b in json['bookings'] as List) Booking.fromJson(b)];

  Future<Booking> booking(int id) async =>
      Booking.fromJson((await client.get('/bookings/$id'))['booking'] as Map<String, dynamic>);

  Future<Booking> _action(int id, String action, String key, [Object? body]) async => Booking.fromJson(
        (await client.post('/bookings/$id/$action', idempotencyKey: key, body: body ?? {}))['booking']
            as Map<String, dynamic>,
      );

  Future<Booking> cancel(int id, String key) => _action(id, 'cancel', key);
  Future<Booking> decline(int id, String key) => _action(id, 'decline', key);
  Future<Booking> choose(int id, int proposedTimeId, String key) =>
      _action(id, 'choose', key, {'proposedTimeId': proposedTimeId});
}
