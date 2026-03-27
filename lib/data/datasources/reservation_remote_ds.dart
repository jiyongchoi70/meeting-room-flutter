import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/calendar_event_model.dart';

class ReservationRemoteDs {
  ReservationRemoteDs({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// startDate/endDate: YYYY-MM-DD
  Future<List<CalendarEventModel>> fetchCalendarEvents({
    required String startDate,
    required String endDate,
    String? roomId,
  }) async {
    final startDay = '${startDate}T00:00:00.000Z';
    final endDay = '${endDate}T23:59:59.999Z';

    var query = _client
        .from('mr_reservations')
        .select(
          'reservation_id, title, start_ymd, end_ymd, room_id, repeat_group_id, status, create_user, mr_room(room_nm)',
        )
        .gte('start_ymd', startDay)
        .lte('start_ymd', endDay);

    if (roomId != null && roomId.isNotEmpty) {
      query = query.eq('room_id', roomId);
    }

    final rows = await query.order('start_ymd', ascending: true);

    return (rows as List<dynamic>).map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      final room = map['mr_room'] as Map<String, dynamic>?;
      map['room_nm'] = room?['room_nm'] ?? '';
      return CalendarEventModel.fromMap(map);
    }).toList();
  }

  Future<void> saveThisOccurrence({
    required String reservationId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    await _client.rpc(
      'rpc_split_series_this_occurrence_save',
      params: {
        'p_actor_uid': uid,
        'p_reservation_id': reservationId,
        'p_payload': payload,
      },
    );
  }

  Future<void> moveThisOccurrence({
    required String reservationId,
    required String startUtcIso,
    required String endUtcIso,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    await _client.rpc(
      'rpc_split_series_this_occurrence_move',
      params: {
        'p_actor_uid': uid,
        'p_reservation_id': reservationId,
        'p_start_ymd': startUtcIso,
        'p_end_ymd': endUtcIso,
      },
    );
  }
}
