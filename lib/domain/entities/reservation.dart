class Reservation {
  const Reservation({
    required this.id,
    required this.roomId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.createdBy,
  });

  final String id;
  final String roomId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String createdBy;
}
