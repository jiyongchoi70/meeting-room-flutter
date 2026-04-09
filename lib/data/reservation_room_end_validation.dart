import 'room_reservation_policy.dart';

/// 일반 예약자 저장 시: 회의실 정책 대비 허용 종료일(YYYYMMDD) 검증.
/// [endYmdDigits] — 비교할 마지막 일자 (`repeat_end_ymd` 또는 단건 종료의 달력일).
String? validateReservationEndAgainstRoomPolicy({
  required String endYmdDigits,
  required RoomReservationPolicy policy,
  required bool skipForPrivilegedUser,
}) {
  if (skipForPrivilegedUser) return null;

  final avail = policy.reservationAvailable;
  if (avail != 110 && avail != 170) return null;

  final name =
      policy.roomName.trim().isEmpty ? '해당 회의실' : policy.roomName.trim();
  final end = _digitsOnlyYmd(endYmdDigits);
  if (end == null || end.length != 8) return null;

  if (avail == 110) {
    final cnt = policy.reservationCnt ?? 0;
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final limit = base.add(Duration(days: cnt));
    final limitDigits = _dateToYmdDigits(limit);
    if (limitDigits.compareTo(end) < 0) {
      return '$name은(는) ${_formatYmdForUser(limitDigits)} 까지만 예약이 가능합니다.';
    }
  } else if (avail == 170) {
    final roomYmd = _digitsOnlyYmd(policy.reservationYmd);
    if (roomYmd != null &&
        roomYmd.length == 8 &&
        roomYmd.compareTo(end) < 0) {
      return '$name은(는) ${_formatYmdForUser(roomYmd)} 까지만 예약이 가능합니다.';
    }
  }
  return null;
}

String? _digitsOnlyYmd(String? raw) {
  if (raw == null) return null;
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length >= 8) return d.substring(0, 8);
  return null;
}

String _dateToYmdDigits(DateTime d) {
  final l = d.toLocal();
  final y = l.year.toString().padLeft(4, '0');
  final m = l.month.toString().padLeft(2, '0');
  final day = l.day.toString().padLeft(2, '0');
  return '$y$m$day';
}

String _formatYmdForUser(String yyyymmdd) {
  if (yyyymmdd.length != 8) return yyyymmdd;
  return '${yyyymmdd.substring(0, 4)}-${yyyymmdd.substring(4, 6)}-${yyyymmdd.substring(6, 8)}';
}
