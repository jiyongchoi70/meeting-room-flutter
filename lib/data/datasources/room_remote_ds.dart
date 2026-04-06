import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meeting_room_model.dart';

/// 웹: RESERVATION_SPECIFIC_DATE_CD = 170 (src/api/rooms.ts)
const int _kReservationSpecificDateCd = 170;

class RoomRemoteDs {
  RoomRemoteDs({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String _todayYmd() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// 웹 fetchRoomsForReservation과 유사: 특정일(170)이면 reservation_ymd >= 오늘만
  Future<List<MeetingRoom>> fetchRoomsForReservation() async {
    final res = await _client
        .from('mr_room')
        .select(
          'room_id, room_nm, cnt, reservation_available, reservation_ymd, seq',
        )
        .order('seq', ascending: true);

    final rows = List<Map<String, dynamic>>.from(res as List);
    final today = _todayYmd();

    final filtered = rows.where((r) {
      final avail = r['reservation_available'] as int?;
      if (avail != _kReservationSpecificDateCd) return true;
      final ymd = r['reservation_ymd'] as String?;
      return ymd != null && ymd.compareTo(today) >= 0;
    });

    return filtered.map(MeetingRoom.fromMrRoom).toList();
  }
}
