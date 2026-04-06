class ChangeReservationStatusResult {
  const ChangeReservationStatusResult({
    required this.ok,
    required this.message,
    required this.affectedCount,
    required this.affectedIds,
  });

  final bool ok;
  final String message;
  final int affectedCount;
  final List<String> affectedIds;
}
