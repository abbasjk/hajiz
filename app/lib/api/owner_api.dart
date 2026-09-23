import 'api_client.dart';
import 'owner_models.dart';

/// مسارات صاحب المحل في الخادم.
class OwnerApi {
  OwnerApi(this.client);
  final ApiClient client;

  Future<OwnerShopState> _state(Future<Map<String, dynamic>> request) async => OwnerShopState.fromJson(await request);

  Future<OwnerShopState> shop() => _state(client.get('/owner/shop'));

  /// يحفظ ما تغيّر فقط؛ أول حفظ يُنشئ المحل كمسودة
  Future<OwnerShopState> saveDetails(Map<String, Object?> fields) => _state(client.put('/owner/shop', body: fields));

  Future<OwnerShopState> submit() => _state(client.post('/owner/shop/submit'));

  Future<OwnerShopState> addService(Map<String, Object?> service) => _state(client.post('/owner/services', body: service));

  Future<OwnerShopState> updateService(int id, Map<String, Object?> service) =>
      _state(client.put('/owner/services/$id', body: service));

  Future<OwnerShopState> setHours(List<Map<String, Object>> periods) =>
      _state(client.put('/owner/hours', body: {'periods': periods}));

  Future<OwnerShopState> addTemporarySchedule(Map<String, Object> schedule) =>
      _state(client.post('/owner/temporary-schedules', body: schedule));

  Future<OwnerShopState> deleteTemporarySchedule(int id) => _state(client.delete('/owner/temporary-schedules/$id'));

  Future<OwnerShopState> updateSettings(Map<String, Object> settings) =>
      _state(client.put('/owner/settings', body: settings));

  Future<OwnerShopState> addPhoto(String contentType, String base64) =>
      _state(client.post('/owner/photos', body: {'contentType': contentType, 'data': base64}));

  Future<OwnerShopState> deletePhoto(int id) => _state(client.delete('/owner/photos/$id'));

  Future<void> requestArea(int districtId, String name) =>
      client.post('/owner/area-requests', body: {'districtId': districtId, 'name': name});

  Future<({List<int> moved, List<int> cancelled})> addClosure(DateTime from, DateTime to, String? reason, String key) async {
    final j = await client.post('/owner/closures', idempotencyKey: key, body: {
      'startsAt': from.toUtc().toIso8601String(),
      'endsAt': to.toUtc().toIso8601String(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    return (moved: [for (final i in j['moved'] as List) i as int], cancelled: [for (final i in j['cancelled'] as List) i as int]);
  }

  Future<OwnerShopState> deleteClosure(int id) => _state(client.delete('/owner/closures/$id'));

  Future<({List<OwnerBooking> pending, List<OwnerBooking> today})> dashboard() async {
    final j = await client.get('/owner/dashboard');
    return (
      pending: [for (final b in j['pending'] as List) OwnerBooking.fromJson(b)],
      today: [for (final b in j['today'] as List) OwnerBooking.fromJson(b)],
    );
  }

  Future<List<OwnerBooking>> day(String date) async {
    final j = await client.get('/owner/day', query: {'date': date});
    return [for (final b in j['bookings'] as List) OwnerBooking.fromJson(b)];
  }

  Future<OwnerBooking> booking(int id) async =>
      OwnerBooking.fromJson((await client.get('/owner/bookings/$id'))['booking'] as Map<String, dynamic>);

  Future<List<DateTime>> proposalSlots(int bookingId, String date) async {
    final j = await client.get('/owner/bookings/$bookingId/slots', query: {'date': date});
    return [for (final s in j['slots'] as List) DateTime.parse(s as String).toUtc()];
  }

  Future<OwnerBooking> _action(int id, String action, String key, [Object? body]) async => OwnerBooking.fromJson(
        (await client.post('/owner/bookings/$id/$action', idempotencyKey: key, body: body ?? {}))['booking']
            as Map<String, dynamic>,
      );

  Future<OwnerBooking> accept(int id, String key) => _action(id, 'accept', key);
  Future<OwnerBooking> reject(int id, String reason, String key) => _action(id, 'reject', key, {'reason': reason});
  Future<OwnerBooking> cancel(int id, String reason, String key) => _action(id, 'cancel', key, {'reason': reason});
  Future<OwnerBooking> noShow(int id, String key) => _action(id, 'no-show', key);
  Future<OwnerBooking> complete(int id, String key) => _action(id, 'complete', key);
  Future<OwnerBooking> verifyDevice(int id, String key) => _action(id, 'verify-device', key);
  Future<OwnerBooking> propose(int id, List<DateTime> times, String? message, String key) => _action(id, 'propose', key, {
        'times': [for (final t in times) t.toUtc().toIso8601String()],
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      });
}
