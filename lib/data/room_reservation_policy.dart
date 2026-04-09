/// `mr_room` 예약 가능 방식·기간 (저장 시 종료일 검증용).
class RoomReservationPolicy {
  const RoomReservationPolicy({
    required this.roomName,
    this.reservationAvailable,
    this.reservationCnt,
    this.reservationYmd,
  });

  final String roomName;
  final int? reservationAvailable;

  /// `reservation_available == 110` 일 때, 오늘로부터 며칠 후까지 예약 가능한지.
  final int? reservationCnt;

  /// `reservation_available == 170` 일 때 마감일 (DB 형식 혼용 가능).
  final String? reservationYmd;
}
