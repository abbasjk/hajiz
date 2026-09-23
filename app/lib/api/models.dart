// نماذج البيانات كما يرسلها الخادم. الأوقات تصل بالتوقيت العالمي وتُعرض بتوقيت بغداد.

DateTime _time(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _timeOrNull(Object? v) => v == null ? null : _time(v);
double? _double(Object? v) => (v as num?)?.toDouble();

class NamedItem {
  const NamedItem(this.id, this.name);
  final int id;
  final String name;

  factory NamedItem.fromJson(Map<String, dynamic> j) => NamedItem(j['id'] as int, j['name'] as String);
}

class Area extends NamedItem {
  const Area(super.id, super.name, this.districtId);
  final int districtId;

  factory Area.fromJson(Map<String, dynamic> j) =>
      Area(j['id'] as int, j['name'] as String, j['districtId'] as int);
}

/// شرائح مهلة الرد بالدقائق حسب قرب الموعد
class DeadlineTable {
  const DeadlineTable(this.minutes);
  final Map<String, int> minutes;

  factory DeadlineTable.fromJson(Map<String, dynamic> j) =>
      DeadlineTable(j.map((k, v) => MapEntry(k, (v as num).toInt())));
}

/// الإعدادات من الخادم: لا يحتاج تغييرها تحديثاً للتطبيق
class ServerConfig {
  const ServerConfig({
    required this.businessTypes,
    required this.districts,
    required this.areas,
    required this.shopDeadlineModes,
    required this.maxPending,
  });

  final List<NamedItem> businessTypes;
  final List<NamedItem> districts;
  final List<Area> areas;
  final Map<String, DeadlineTable> shopDeadlineModes;
  final int maxPending;

  factory ServerConfig.fromJson(Map<String, dynamic> j) {
    final settings = j['settings'] as Map<String, dynamic>;
    final modes = settings['shop_deadline_modes'] as Map<String, dynamic>;
    return ServerConfig(
      businessTypes: [for (final t in j['businessTypes'] as List) NamedItem.fromJson(t)],
      districts: [for (final d in j['districts'] as List) NamedItem.fromJson(d)],
      areas: [for (final a in j['areas'] as List) Area.fromJson(a)],
      shopDeadlineModes: modes.map((k, v) => MapEntry(k, DeadlineTable.fromJson(v))),
      maxPending: (settings['max_pending_requests_per_customer'] as num).toInt(),
    );
  }
}

class ShopSummary {
  const ShopSummary({
    required this.id,
    required this.name,
    this.businessType,
    this.district,
    this.area,
    this.landmark,
    this.distanceKm,
    this.nextAvailable,
    this.coverPhoto,
    required this.committed,
    required this.instantBooking,
  });

  final int id;
  final String name;
  final String? businessType;
  final String? district;
  final String? area;
  final String? landmark;
  final double? distanceKm;
  final DateTime? nextAvailable;
  final String? coverPhoto;
  final bool committed;
  final bool instantBooking;

  factory ShopSummary.fromJson(Map<String, dynamic> j) => ShopSummary(
        id: j['id'] as int,
        name: j['name'] as String,
        businessType: j['businessType'] as String?,
        district: j['district'] as String?,
        area: j['area'] as String?,
        landmark: j['landmark'] as String?,
        distanceKm: _double(j['distanceKm']),
        nextAvailable: _timeOrNull(j['nextAvailable']),
        coverPhoto: j['coverPhoto'] as String?,
        committed: j['committed'] == true,
        instantBooking: j['instantBooking'] == true,
      );
}

enum PriceType { fixed, startsFrom, afterInspection }

PriceType _priceType(Object? v) => switch (v) {
      'starts_from' => PriceType.startsFrom,
      'after_inspection' => PriceType.afterInspection,
      _ => PriceType.fixed,
    };

class Service {
  const Service({required this.id, required this.name, required this.durationMinutes, required this.priceType, this.price});

  final int id;
  final String name;
  final int durationMinutes;
  final PriceType priceType;
  final int? price;

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: (j['id'] as int?) ?? 0,
        name: j['name'] as String,
        durationMinutes: j['durationMinutes'] as int,
        priceType: _priceType(j['priceType']),
        price: j['price'] as int?,
      );
}

class WorkingPeriod {
  const WorkingPeriod(this.dayOfWeek, this.from, this.to);
  final int dayOfWeek; // 0 = الأحد
  final String from; // HH:MM
  final String to;

  factory WorkingPeriod.fromJson(Map<String, dynamic> j) =>
      WorkingPeriod(j['dayOfWeek'] as int, j['from'] as String, j['to'] as String);
}

class TemporarySchedule {
  const TemporarySchedule(this.name, this.fromDate, this.toDate);
  final String name;
  final String fromDate;
  final String toDate;

  factory TemporarySchedule.fromJson(Map<String, dynamic> j) =>
      TemporarySchedule(j['name'] as String, j['fromDate'] as String, j['toDate'] as String);
}

class ShopDetails {
  const ShopDetails({
    required this.id,
    required this.name,
    this.description,
    this.phone,
    this.businessType,
    this.district,
    this.area,
    this.street,
    this.landmark,
    this.latitude,
    this.longitude,
    required this.instantBooking,
    required this.deadlineMode,
    required this.freeCancelHours,
    required this.committed,
    required this.photos,
    required this.services,
    required this.weeklyHours,
    required this.temporarySchedules,
  });

  final int id;
  final String name;
  final String? description;
  final String? phone;
  final String? businessType;
  final String? district;
  final String? area;
  final String? street;
  final String? landmark;
  final double? latitude;
  final double? longitude;
  final bool instantBooking;
  final String deadlineMode;
  final int freeCancelHours;
  final bool committed;
  final List<String> photos;
  final List<Service> services;
  final List<WorkingPeriod> weeklyHours;
  final List<TemporarySchedule> temporarySchedules;

  factory ShopDetails.fromJson(Map<String, dynamic> j) => ShopDetails(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String?,
        phone: j['phone'] as String?,
        businessType: j['businessType'] as String?,
        district: j['district'] as String?,
        area: j['area'] as String?,
        street: j['street'] as String?,
        landmark: j['landmark'] as String?,
        latitude: _double(j['latitude']),
        longitude: _double(j['longitude']),
        instantBooking: j['instantBooking'] == true,
        deadlineMode: j['deadlineMode'] as String? ?? 'normal',
        freeCancelHours: j['freeCancelHours'] as int? ?? 2,
        committed: j['committed'] == true,
        photos: [for (final p in j['photos'] as List? ?? []) p as String],
        services: [for (final s in j['services'] as List? ?? []) Service.fromJson(s)],
        weeklyHours: [for (final h in j['weeklyHours'] as List? ?? []) WorkingPeriod.fromJson(h)],
        temporarySchedules: [for (final t in j['temporarySchedules'] as List? ?? []) TemporarySchedule.fromJson(t)],
      );
}

enum BookingStatus {
  pendingShop,
  pendingCustomer,
  confirmed,
  rejected,
  cancelledByCustomer,
  cancelledByShop,
  expired,
  completed,
  noShow;

  static BookingStatus parse(String v) => switch (v) {
        'pending_shop' => pendingShop,
        'pending_customer' => pendingCustomer,
        'confirmed' => confirmed,
        'rejected' => rejected,
        'cancelled_by_customer' => cancelledByCustomer,
        'cancelled_by_shop' => cancelledByShop,
        'expired' => expired,
        'completed' => completed,
        _ => noShow,
      };

  bool get isPending => this == pendingShop || this == pendingCustomer;
}

class ProposedTime {
  const ProposedTime(this.id, this.startsAt, this.endsAt, this.available);
  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool available;

  factory ProposedTime.fromJson(Map<String, dynamic> j) =>
      ProposedTime(j['id'] as int, _time(j['startsAt']), _time(j['endsAt']), j['available'] == true);
}

class BookingShop {
  const BookingShop(this.id, this.name, this.phone, this.latitude, this.longitude, this.freeCancelHours);
  final int id;
  final String name;
  final String? phone;
  final double? latitude;
  final double? longitude;
  final int freeCancelHours;

  factory BookingShop.fromJson(Map<String, dynamic> j) => BookingShop(
        j['id'] as int,
        j['name'] as String,
        j['phone'] as String?,
        _double(j['latitude']),
        _double(j['longitude']),
        j['freeCancelHours'] as int? ?? 2,
      );
}

class Booking {
  const Booking({
    required this.id,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    this.responseDeadline,
    required this.isInstant,
    this.note,
    this.modificationMessage,
    this.cancelReason,
    required this.shop,
    required this.services,
    required this.proposedTimes,
  });

  final int id;
  final BookingStatus status;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime? responseDeadline;
  final bool isInstant;
  final String? note;
  final String? modificationMessage;
  final String? cancelReason;
  final BookingShop shop;
  final List<Service> services;
  final List<ProposedTime> proposedTimes;

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as int,
        status: BookingStatus.parse(j['status'] as String),
        startsAt: _time(j['startsAt']),
        endsAt: _time(j['endsAt']),
        responseDeadline: _timeOrNull(j['responseDeadline']),
        isInstant: j['isInstant'] == true,
        note: j['note'] as String?,
        modificationMessage: j['modificationMessage'] as String?,
        cancelReason: j['cancelReason'] as String?,
        shop: BookingShop.fromJson(j['shop'] as Map<String, dynamic>),
        services: [for (final s in j['services'] as List? ?? []) Service.fromJson(s)],
        proposedTimes: [for (final t in j['proposedTimes'] as List? ?? []) ProposedTime.fromJson(t)],
      );
}

class RegisteredUser {
  const RegisteredUser(this.id, this.name, this.phone);
  final int id;
  final String name;
  final String phone;

  factory RegisteredUser.fromJson(Map<String, dynamic> j) =>
      RegisteredUser(j['id'] as int, j['name'] as String, j['phone'] as String);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};
}

/// إشعار داخل التطبيق؛ النص يكتبه الخادم (النص نفسه الذي وصل للهاتف)
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.bookingId,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  final int id;
  final String type;
  final int? bookingId;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as int,
        type: j['type'] as String,
        bookingId: j['bookingId'] as int?,
        title: j['title'] as String,
        body: j['body'] as String,
        read: j['read'] as bool,
        createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
      );
}

class NotificationSettings {
  const NotificationSettings({required this.reminders, required this.morningSummary});
  final bool reminders;
  final bool morningSummary;

  factory NotificationSettings.fromJson(Map<String, dynamic> j) =>
      NotificationSettings(reminders: j['reminders'] as bool, morningSummary: j['morningSummary'] as bool);
}
