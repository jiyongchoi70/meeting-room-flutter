import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/repeat_date_ranges.dart';
import '../models/calendar_event_model.dart';
import '../models/change_reservation_status_result.dart';
import '../models/reservation_booker_info.dart';
import '../reservation_save_policy.dart';

/// 웹 `formatPhone` / 표시용.
String _formatPhoneDisplay(String? raw) {
  if (raw == null) return '';
  final s = raw.trim();
  if (s.isEmpty) return '';
  final d = s.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('010')) {
    return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
  }
  if (d.length == 10) {
    return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  }
  return s;
}

class ReservationRemoteDs {
  ReservationRemoteDs({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// 반복 스케줄 lookup(160) 라벨 fallback
  static const kFallbackRepeatLabels = <int, String>{
    110: '반복없음',
    120: '매일',
    130: '매주',
    140: '매월',
  };

  /// `mr_lookup_value` — 유효기간 필터 후 코드→이름 (라디오 110·120·130·140)
  Future<Map<int, String>> fetchRepeatScheduleLookupLabels() async {
    final typeRow = await _client
        .from('mr_lookup_type')
        .select('lookup_type_id')
        .eq('lookup_type_cd', 160)
        .maybeSingle();
    final typeId = typeRow?['lookup_type_id'];
    if (typeId == null) {
      return Map<int, String>.from(kFallbackRepeatLabels);
    }
    final raw = await _client
        .from('mr_lookup_value')
        .select('lookup_value_cd, lookup_value_nm, start_ymd, end_ymd')
        .eq('lookup_type_id', typeId);
    final list = (raw as List<dynamic>? ?? []);
    final now = DateTime.now();
    final nowDigits =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final out = <int, String>{};
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final cd = (m['lookup_value_cd'] as num?)?.toInt();
      final nm = (m['lookup_value_nm'] as String?)?.trim() ?? '';
      if (cd == null || nm.isEmpty) continue;
      final s = (m['start_ymd'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      final end =
          (m['end_ymd'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (s.isNotEmpty && nowDigits.compareTo(s) < 0) continue;
      if (end.isNotEmpty && nowDigits.compareTo(end) > 0) continue;
      out[cd] = nm;
    }
    final merged = Map<int, String>.from(kFallbackRepeatLabels);
    for (final e in out.entries) {
      if ([110, 120, 130, 140].contains(e.key)) {
        merged[e.key] = e.value;
      }
    }
    return merged;
  }

  int? _parseOptionalInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  List<bool> _weekdayFlagsFromPayload(Map<String, dynamic> p) => [
        p['sun_yn'] == 'Y',
        p['mon_yn'] == 'Y',
        p['tue_yn'] == 'Y',
        p['wed_yn'] == 'Y',
        p['thu_yn'] == 'Y',
        p['fri_yn'] == 'Y',
        p['sat_yn'] == 'Y',
      ];

  /// 웹 `getRoomConfirmAndDuplicate` 와 동일.
  Future<({int? confirmYn, int? duplicateYn})> getRoomConfirmAndDuplicate(
    String roomId,
  ) async {
    final data = await _client
        .from('mr_room')
        .select('confirm_yn, duplicate_yn')
        .eq('room_id', roomId)
        .maybeSingle();
    final cy = (data?['confirm_yn'] as num?)?.toInt();
    final dy = (data?['duplicate_yn'] as num?)?.toInt();
    return (confirmYn: cy, duplicateYn: dy);
  }

  /// 웹 `getStatusForReserver` 와 동일.
  Future<int> resolveStatusForNewReservation(String roomId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final mrUser = await _client
        .from('mr_users')
        .select('user_type')
        .eq('user_uid', uid)
        .maybeSingle();
    if ((mrUser?['user_type'] as num?)?.toInt() == kMrUserTypeManager) {
      return kReservationStatusCompleted;
    }

    final ap = await _client
        .from('mr_approver')
        .select('room_id')
        .eq('user_uid', uid)
        .eq('room_id', roomId)
        .maybeSingle();
    if (ap != null) return kReservationStatusCompleted;

    final room = await _client
        .from('mr_room')
        .select('confirm_yn')
        .eq('room_id', roomId)
        .maybeSingle();
    final cy = (room?['confirm_yn'] as num?)?.toInt();
    return cy == kConfirmYnAutoComplete
        ? kReservationStatusCompleted
        : kReservationStatusApplied;
  }

  void _throwIfOverlapRpcResult(dynamic raw) {
    final list = raw as List<dynamic>?;
    if (list == null || list.isEmpty) return;
    final first = list.first;
    if (first is! Map) return;
    final row = Map<String, dynamic>.from(first);
    if (row['has_overlap'] == true) {
      final ymd = row['conflict_ymd'] as String?;
      throw Exception(
        ymd != null && ymd.isNotEmpty ? '$ymd 중복이 됩니다.' : '시간이 중복됩니다.',
      );
    }
  }

  /// `duplicate_yn == 120` 일 때만 RPC 호출 (웹 `checkOverlap`).
  Future<void> assertNoOverlapIfRequired({
    required String roomId,
    required DateTime startUtc,
    required DateTime endUtc,
    required int? duplicateYn,
    String? excludeReservationId,
  }) async {
    if (!duplicateYnRequiresOverlapCheck(duplicateYn)) return;

    final params = <String, dynamic>{
      'p_room_id': roomId,
      'p_start_ymd': startUtc.toIso8601String(),
      'p_end_ymd': endUtc.toIso8601String(),
      'p_exclude_reservation_id': excludeReservationId,
    };

    final raw = await _client.rpc('check_reservation_overlap', params: params);
    _throwIfOverlapRpcResult(raw);
  }

  /// 반복 시리즈 일괄 변경 시(웹 `checkOverlapExcluding`).
  Future<void> assertNoOverlapExcludingIfRequired({
    required String roomId,
    required DateTime startUtc,
    required DateTime endUtc,
    required int? duplicateYn,
    required List<String> excludeReservationIds,
  }) async {
    if (!duplicateYnRequiresOverlapCheck(duplicateYn)) return;

    final raw = await _client.rpc(
      'check_reservation_overlap_excluding',
      params: {
        'p_room_id': roomId,
        'p_start_ymd': startUtc.toIso8601String(),
        'p_end_ymd': endUtc.toIso8601String(),
        'p_exclude_ids': excludeReservationIds,
      },
    );
    _throwIfOverlapRpcResult(raw);
  }

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
          'reservation_id, title, start_ymd, end_ymd, room_id, repeat_group_id, '
          'status, create_user, return_comment, allday_yn, repeat_id, repeat_end_ymd, '
          'repeat_cycle, repeat_user, sun_yn, mon_yn, tue_yn, wed_yn, thu_yn, fri_yn, sat_yn, '
          'mr_room(room_nm)',
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

  Future<void> saveSingle({
    required String reservationId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final roomId = payload['room_id'] as String?;
    if (roomId == null || roomId.isEmpty) {
      throw Exception('room_id가 필요합니다.');
    }
    final startIso = payload['start_ymd'] as String?;
    final endIso = payload['end_ymd'] as String?;
    if (startIso == null || endIso == null) {
      throw Exception('start_ymd, end_ymd가 필요합니다.');
    }
    final policy = await getRoomConfirmAndDuplicate(roomId);
    await assertNoOverlapIfRequired(
      roomId: roomId,
      startUtc: DateTime.parse(startIso).toUtc(),
      endUtc: DateTime.parse(endIso).toUtc(),
      duplicateYn: policy.duplicateYn,
      excludeReservationId: reservationId,
    );

    await _client
        .from('mr_reservations')
        .update({
          ...payload,
          'update_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('reservation_id', reservationId);
  }

  Future<void> createReservation({
    required String roomId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final startIso = payload['start_ymd'] as String?;
    final endIso = payload['end_ymd'] as String?;
    if (startIso == null || endIso == null) {
      throw Exception('start_ymd, end_ymd가 필요합니다.');
    }

    final startUtc = DateTime.parse(startIso).toUtc();
    final endUtc = DateTime.parse(endIso).toUtc();

    final rid = _parseOptionalInt(payload['repeat_id']);
    final repeatEndRaw = payload['repeat_end_ymd'] as String?;
    final repeatEnd =
        repeatEndRaw != null && repeatEndRaw.trim().isNotEmpty
            ? repeatEndRaw.trim()
            : null;

    var occ = computeRepeatOccurrences(
      startUtc: startUtc,
      endUtc: endUtc,
      repeatId: rid,
      repeatEndIso: repeatEnd,
      repeatCycle: _parseOptionalInt(payload['repeat_cycle']),
      repeatUser: _parseOptionalInt(payload['repeat_user']),
      weekdayFlags: _weekdayFlagsFromPayload(payload),
    );

    if (occ.isEmpty) {
      occ = [
        RepeatOccurrence(startUtc: startUtc, endUtc: endUtc),
      ];
    }

    final policy = await getRoomConfirmAndDuplicate(roomId);
    final statusFuture = resolveStatusForNewReservation(roomId);
    final overlapFutures = occ
        .map(
          (o) => assertNoOverlapIfRequired(
            roomId: roomId,
            startUtc: o.startUtc,
            endUtc: o.endUtc,
            duplicateYn: policy.duplicateYn,
          ),
        )
        .toList(growable: false);
    await Future.wait<dynamic>([...overlapFutures, statusFuture]);
    final status = await statusFuture;

    Map<String, dynamic> baseRow(String s, String e, {String? groupId}) {
      final m = <String, dynamic>{
        'title': payload['title'],
        'room_id': roomId,
        'allday_yn': payload['allday_yn'] ?? 'N',
        'start_ymd': s,
        'end_ymd': e,
        'create_user': uid,
        'status': status,
        'update_at': DateTime.now().toUtc().toIso8601String(),
        'sun_yn': payload['sun_yn'] ?? 'N',
        'mon_yn': payload['mon_yn'] ?? 'N',
        'tue_yn': payload['tue_yn'] ?? 'N',
        'wed_yn': payload['wed_yn'] ?? 'N',
        'thu_yn': payload['thu_yn'] ?? 'N',
        'fri_yn': payload['fri_yn'] ?? 'N',
        'sat_yn': payload['sat_yn'] ?? 'N',
      };
      final rp = payload['repeat_id'];
      if (rp != null && '$rp'.trim().isNotEmpty) {
        m['repeat_id'] = '$rp'.trim();
      }
      if (repeatEnd != null) {
        m['repeat_end_ymd'] = repeatEnd;
      }
      final rc = _parseOptionalInt(payload['repeat_cycle']);
      if (rc != null) {
        m['repeat_cycle'] = rc;
      }
      final ru = payload['repeat_user'];
      if (ru != null && '$ru'.trim().isNotEmpty) {
        m['repeat_user'] = '$ru'.trim();
      }
      final rcond = payload['repeat_condition'];
      if (rcond != null && '$rcond'.trim().isNotEmpty) {
        m['repeat_condition'] = rcond;
      }
      if (groupId != null) {
        m['repeat_group_id'] = groupId;
      }
      return m;
    }

    final first = occ.first;
    final firstRow = baseRow(
      first.startUtc.toUtc().toIso8601String(),
      first.endUtc.toUtc().toIso8601String(),
    );

    final inserted = await _client
        .from('mr_reservations')
        .insert(firstRow)
        .select('reservation_id')
        .single();
    final groupId = inserted['reservation_id']?.toString();
    if (groupId == null || groupId.isEmpty) {
      throw Exception('예약 저장 후 ID를 확인할 수 없습니다.');
    }

    final hasRepeatMeta =
        repeatEnd != null && rid != null && rid != kRepeatNone;
    if (hasRepeatMeta) {
      await _client
          .from('mr_reservations')
          .update({'repeat_group_id': groupId}).eq('reservation_id', groupId);
    }

    if (occ.length > 1) {
      final bulk = <Map<String, dynamic>>[];
      for (var i = 1; i < occ.length; i++) {
        final o = occ[i];
        bulk.add(
          baseRow(
            o.startUtc.toUtc().toIso8601String(),
            o.endUtc.toUtc().toIso8601String(),
            groupId: groupId,
          ),
        );
      }
      await _client.from('mr_reservations').insert(bulk);
    }
  }

  /// 반복 시리즈 전체 저장.
  /// 선택한 occurrence의 변경량(delta)을 시리즈 전체에 동일 적용한다.
  Future<void> saveAllInSeries({
    required String repeatGroupId,
    required Map<String, dynamic> payload,
    required DateTime oldStartUtc,
    required DateTime oldEndUtc,
    required DateTime newStartUtc,
    required DateTime newEndUtc,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final rows = await _client
        .from('mr_reservations')
        .select('reservation_id, start_ymd, end_ymd')
        .or('repeat_group_id.eq.$repeatGroupId,reservation_id.eq.$repeatGroupId')
        .order('start_ymd', ascending: true);

    final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
    if (list.isEmpty) throw Exception('반복 일정을 찾을 수 없습니다.');

    final deltaStart = newStartUtc.difference(oldStartUtc);
    final deltaEnd = newEndUtc.difference(oldEndUtc);
    final updates = list.map((r) {
      final start = DateTime.parse(r['start_ymd'] as String).toUtc();
      final end = DateTime.parse(r['end_ymd'] as String).toUtc();
      return {
        'reservation_id': r['reservation_id'] as String,
        'start_ymd': start.add(deltaStart).toIso8601String(),
        'end_ymd': end.add(deltaEnd).toIso8601String(),
      };
    }).toList();

    final roomId = payload['room_id'] as String?;
    if (roomId == null || roomId.isEmpty) {
      throw Exception('room_id가 필요합니다.');
    }
    final policy = await getRoomConfirmAndDuplicate(roomId);
    final excludeIds =
        list.map((r) => r['reservation_id'] as String).toList(growable: false);
    if (duplicateYnRequiresOverlapCheck(policy.duplicateYn)) {
      for (final u in updates) {
        await assertNoOverlapExcludingIfRequired(
          roomId: roomId,
          startUtc: DateTime.parse(u['start_ymd'] as String).toUtc(),
          endUtc: DateTime.parse(u['end_ymd'] as String).toUtc(),
          duplicateYn: policy.duplicateYn,
          excludeReservationIds: excludeIds,
        );
      }
    }

    await _client.rpc(
      'update_repeat_group_dates_bulk',
      params: {'p_updates': updates},
    );

    await _client
        .from('mr_reservations')
        .update({
          'title': payload['title'],
          'room_id': payload['room_id'],
          'allday_yn': payload['allday_yn'] ?? 'N',
          'update_at': DateTime.now().toUtc().toIso8601String(),
        })
        .or('repeat_group_id.eq.$repeatGroupId,reservation_id.eq.$repeatGroupId');
  }

  /// 담당자(`mr_users.user_type` 110) 또는 해당 회의실 `mr_approver`에 등록된 사용자만 true.
  Future<bool> canActorApproveForRoom(String roomId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;

    final userRow = await _client
        .from('mr_users')
        .select('user_type')
        .eq('user_uid', uid)
        .maybeSingle();
    final ut = userRow?['user_type'];
    if (ut is num && ut.toInt() == 110) return true;

    final ap = await _client
        .from('mr_approver')
        .select('room_id')
        .eq('user_uid', uid)
        .eq('room_id', roomId)
        .maybeSingle();
    return ap != null;
  }

  /// `docs/RPC_CONTRACT.md` §3. 전이·권한은 서버에서 최종 검증.
  /// [scope]: `this` | `all` (반복 시 웹과 동일하게 모달에서 선택)
  Future<ChangeReservationStatusResult> changeReservationStatus({
    required String targetReservationId,
    required int nextStatus,
    required String scope,
    String? returnComment,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final raw = await _client.rpc(
      'rpc_change_reservation_status',
      params: {
        'p_actor_uid': uid,
        'p_target_reservation_id': targetReservationId,
        'p_next_status': nextStatus,
        'p_scope': scope,
        'p_return_comment': returnComment,
      },
    );

    final list = raw as List<dynamic>?;
    if (list == null || list.isEmpty) {
      throw Exception('서버 응답이 비어 있습니다.');
    }
    final row = Map<String, dynamic>.from(list.first as Map);
    final ok = row['ok'] as bool? ?? false;
    final message = (row['message'] as String?) ?? '';
    if (!ok) {
      throw Exception(message.isEmpty ? '상태 변경에 실패했습니다.' : message);
    }
    final idsRaw = row['affected_ids'];
    final ids = <String>[];
    if (idsRaw is List) {
      for (final e in idsRaw) {
        if (e != null) ids.add(e.toString());
      }
    }
    return ChangeReservationStatusResult(
      ok: ok,
      message: message,
      affectedCount: (row['affected_count'] as num?)?.toInt() ?? ids.length,
      affectedIds: ids,
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

  /// 현재 로그인 사용자 UID (본인 예약 여부 판별 등).
  String? get actorUid => _client.auth.currentUser?.id;

  /// 웹 `deleteReservation` — 단일 행 삭제.
  Future<void> deleteReservation({required String reservationId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');
    await _client.from('mr_reservations').delete().eq(
          'reservation_id',
          reservationId,
        );
  }

  /// 웹 `deleteReservationThisAndFollowing`.
  Future<void> deleteReservationThisAndFollowing({
    required String reservationId,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');
    final row = await _client
        .from('mr_reservations')
        .select('repeat_group_id, start_ymd')
        .eq('reservation_id', reservationId)
        .maybeSingle();
    if (row == null) throw Exception('예약을 찾을 수 없습니다.');
    final gid = row['repeat_group_id'] as String?;
    final startYmd = row['start_ymd'] as String?;
    if (gid == null || gid.isEmpty || startYmd == null) {
      throw Exception('반복 그룹 정보가 없습니다.');
    }
    await _client
        .from('mr_reservations')
        .delete()
        .eq('repeat_group_id', gid)
        .gte('start_ymd', startYmd);
  }

  /// 웹 `deleteReservationAllInGroup`.
  Future<void> deleteReservationAllInGroup({required String repeatGroupId}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('로그인이 필요합니다.');
    await _client.from('mr_reservations').delete().eq(
          'repeat_group_id',
          repeatGroupId,
        );
  }

  /// `create_user`(mr_users) + 직분 lookup(타입 130, 웹 `LOOKUP_POSITION`과 동일).
  Future<ReservationBookerInfo?> fetchBookerInfo({required String userUid}) async {
    if (userUid.isEmpty) return null;
    final row = await _client
        .from('mr_users')
        .select('user_name, phone, user_position, create_ymd')
        .eq('user_uid', userUid)
        .maybeSingle();
    if (row == null) return null;

    final name = (row['user_name'] as String?)?.trim() ?? '';
    final phoneRaw = row['phone'] as String?;
    final posCd = (row['user_position'] as num?)?.toInt();
    final createYmd = row['create_ymd'] as String?;

    String positionName = '';
    if (posCd != null) {
      positionName = await _resolvePositionName(
        lookupValueCd: posCd,
        userCreateYmd: createYmd,
      );
    }

    return ReservationBookerInfo(
      name: name,
      positionName: positionName.isEmpty ? null : positionName,
      phone: _formatPhoneDisplay(phoneRaw),
    );
  }

  Future<String> _resolvePositionName({
    required int lookupValueCd,
    String? userCreateYmd,
  }) async {
    final typeRow = await _client
        .from('mr_lookup_type')
        .select('lookup_type_id')
        .eq('lookup_type_cd', 130)
        .maybeSingle();
    final typeId = typeRow?['lookup_type_id'];
    if (typeId == null) return '';

    final rawList = await _client
        .from('mr_lookup_value')
        .select('lookup_value_nm, start_ymd, end_ymd')
        .eq('lookup_type_id', typeId)
        .eq('lookup_value_cd', lookupValueCd);

    final list = (rawList as List<dynamic>?) ?? [];
    if (list.isEmpty) return '';

    String nameOf(Map<String, dynamic> m) =>
        (m['lookup_value_nm'] as String?)?.trim() ?? '';

    final ymd = (userCreateYmd ?? '').replaceAll(RegExp(r'\D'), '');
    if (ymd.length < 8) {
      return nameOf(Map<String, dynamic>.from(list.first as Map));
    }

    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      final s = (m['start_ymd'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      final e = (m['end_ymd'] as String?)?.replaceAll(RegExp(r'\D'), '') ?? '';
      if (s.isNotEmpty && ymd.compareTo(s) < 0) continue;
      if (e.isNotEmpty && ymd.compareTo(e) > 0) continue;
      final nm = nameOf(m);
      if (nm.isNotEmpty) return nm;
    }
    return nameOf(Map<String, dynamic>.from(list.first as Map));
  }
}
