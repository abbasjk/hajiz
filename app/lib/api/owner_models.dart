import 'models.dart';

// نماذج واجهة صاحب المحل كما يرسلها الخادم.

DateTime _time(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _timeOrNull(Object? v) => v == null ? null : _time(v);
double? _double(Object? v) => (v as num?)?.toDouble();

enum ShopStatus {
  draft,
  underReview,
  approved,
  rejected,
  suspended;

  static ShopStatus parse(String v) => switch (v) {
        'under_review' => underReview,
        'approved' => approved,
        'rejected' => rejected,
        'suspended' => suspended,
        _ => draft,
      };
}

class OwnerService extends Service {
  const OwnerService({
    required super.id,
    required super.name,
    required super.durationMinutes,
    required super.priceType,
    super.price,
    required this.active,
  });

  final bool active;

  factory OwnerService.fromJson(Map<String, dynamic> j) {
    final s = Service.fromJson(j);
    return OwnerService(
      id: s.id,
      name: s.name,
      durationMinutes: s.durationMinutes,
      priceType: s.priceType,
      price: s.price,
      active: j['active'] != false,
    );
  }
}

class OwnerTemporarySchedule {
  const OwnerTemporarySchedule(this.id, this.name, this.fromDate, this.toDate, this.periods);
  final int id;
  final String name;
  final String fromDate;
  final String toDate;
  final List<WorkingPeriod> periods;

  factory OwnerTemporarySchedule.fromJson(Map<String, dynamic> j) => OwnerTemporarySchedule(
        j['id'] as int,
        j['name'] as String,
        j['fromDate'] as String,
        j['toDate'] as String,
        [for (final p in j['periods'] as List? ?? []) WorkingPeriod.fromJson(p)],
      );
}

class Closure {
  const Closure(this.id, this.startsAt, this.endsAt, this.reason);
  final int id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? reason;

  factory Closure.fromJson(Map<String, dynamic> j) =>
      Closure(j['id'] as int, _time(j['startsAt']), _time(j['endsAt']), j['reason'] as String?);
}

class ShopPhoto {
  const ShopPhoto(this.id, this.url);
  final int id;
  final String url;

  factory ShopPhoto.fromJson(Map<String, dynamic> j) => ShopPhoto(j['id'] as int, j['url'] as String);
}

class OwnerShop {
  const OwnerShop({
    required this.id,
    required this.name,
    required this.status,
    this.reviewNote,
    this.businessTypeId,
    this.description,
    this.phone,
    this.districtId,
    this.areaId,
    this.street,
    this.landmark,
    this.latitude,
    this.longitude,
    required this.deadlineMode,
    required this.freeCancelHours,
    required this.minLeadMinutes,
    required this.instantBooking,
    required this.bufferMinutes,
    required this.services,
    required this.weeklyHours,
    required this.temporarySchedules,
    required this.photos,
    required this.closures,
  });

  final int id;
  final String name;
  final ShopStatus status;
  final String? reviewNote;
  final int? businessTypeId;
  final String? description;
  final String? phone;
  final int? districtId;
  final int? areaId;
  final String? street;
  final String? landmark;
  final double? latitude;
  final double? longitude;
  final String deadlineMode;
  final int freeCancelHours;
  final int minLeadMinutes;
  final bool instantBooking;
  final int bufferMinutes;
  final List<OwnerService> services;
  final List<WorkingPeriod> weeklyHours;
  final List<OwnerTemporarySchedule> temporarySchedules;
  final List<ShopPhoto> photos;
  final List<Closure> closures;

  factory OwnerShop.fromJson(Map<String, dynamic> j) => OwnerShop(
        id: j['id'] as int,
        name: j['name'] as String,
        status: ShopStatus.parse(j['status'] as String),
        reviewNote: j['reviewNote'] as String?,
        businessTypeId: j['businessTypeId'] as int?,
        description: j['description'] as String?,
        phone: j['phone'] as String?,
        districtId: j['districtId'] as int?,
        areaId: j['areaId'] as int?,
        street: j['street'] as String?,
        landmark: j['landmark'] as String?,
        latitude: _double(j['latitude']),
        longitude: _double(j['longitude']),
        deadlineMode: j['deadlineMode'] as String? ?? 'normal',
        freeCancelHours: j['freeCancelHours'] as int? ?? 2,
        minLeadMinutes: j['minLeadMinutes'] as int? ?? 180,
        instantBooking: j['instantBooking'] == true,
        bufferMinutes: j['bufferMinutes'] as int? ?? 0,
        services: [for (final s in j['services'] as List? ?? []) OwnerService.fromJson(s)],
        weeklyHours: [for (final h in j['weeklyHours'] as List? ?? []) WorkingPeriod.fromJson(h)],
        temporarySchedules: [for (final t in j['temporarySchedules'] as List? ?? []) OwnerTemporarySchedule.fromJson(t)],
        photos: [for (final p in j['photos'] as List? ?? []) ShopPhoto.fromJson(p)],
        closures: [for (final c in j['closures'] as List? ?? []) Closure.fromJson(c)],
      );
}

/// المحل مع ما ينقصه قبل الإرسال للمراجعة
class OwnerShopState {
  const OwnerShopState(this.shop, this.missing);
  final OwnerShop? shop;
  final List<String> missing;

  factory OwnerShopState.fromJson(Map<String, dynamic> j) => OwnerShopState(
        j['shop'] == null ? null : OwnerShop.fromJson(j['shop'] as Map<String, dynamic>),
        [for (final m in j['missing'] as List? ?? []) m as String],
      );
}

class CustomerStats {
  const CustomerStats(this.attended, this.lateCancels, this.noShows);
  final int attended;
  final int lateCancels;
  final int noShows;
}

class BookingCustomer {
  const BookingCustomer(this.id, this.name, this.phone, this.newDevice, this.stats);
  final int id;
  final String name;

  /// يظهر فقط ما دام بين الطرفين حجز قائم
  final String? phone;
  final bool newDevice;
  final CustomerStats? stats;

  factory BookingCustomer.fromJson(Map<String, dynamic> j) {
    final s = j['stats'] as Map<String, dynamic>?;
    return BookingCustomer(
      j['id'] as int,
      j['name'] as String,
      j['phone'] as String?,
      j['newDevice'] == true,
      s == null ? null : CustomerStats(s['attended'] as int, s['lateCancels'] as int, s['noShows'] as int),
    );
  }
}

class OwnerBooking {
  const OwnerBooking({
    required this.id,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    this.responseDeadline,
    required this.isInstant,
    this.note,
    this.modificationMessage,
    this.cancelReason,
    required this.customer,
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
  final BookingCustomer customer;
  final List<Service> services;
  final List<DateTime> proposedTimes;

  int get durationMinutes => endsAt.difference(startsAt).inMinutes;

  factory OwnerBooking.fromJson(Map<String, dynamic> j) => OwnerBooking(
        id: j['id'] as int,
        status: BookingStatus.parse(j['status'] as String),
        startsAt: _time(j['startsAt']),
        endsAt: _time(j['endsAt']),
        responseDeadline: _timeOrNull(j['responseDeadline']),
        isInstant: j['isInstant'] == true,
        note: j['note'] as String?,
        modificationMessage: j['modificationMessage'] as String?,
        cancelReason: j['cancelReason'] as String?,
        customer: BookingCustomer.fromJson(j['customer'] as Map<String, dynamic>),
        services: [for (final s in j['services'] as List? ?? []) Service.fromJson(s)],
        proposedTimes: [for (final t in j['proposedTimes'] as List? ?? []) _time((t as Map)['startsAt'])],
      );
}
