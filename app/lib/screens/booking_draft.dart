import '../api/models.dart';

/// ما يختاره الزبون عبر خطوات الحجز الثلاث
class BookingDraft {
  BookingDraft(this.shop);

  final ShopDetails shop;
  final List<Service> services = [];
  DateTime? startsAt;

  int get durationMinutes => services.fold(0, (a, s) => a + s.durationMinutes);
  List<int> get serviceIds => [for (final s in services) s.id];
}
