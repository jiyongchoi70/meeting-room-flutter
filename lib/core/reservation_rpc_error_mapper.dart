/// `rpc_change_reservation_status` 등 결재 RPC의 예외·메시지를 사용자용 한글로 정리.
/// 서버는 `[E_xxx]` 태그 + 설명 또는 순수 한글 메시지를 반환할 수 있음.
String mapReservationStatusRpcUserMessage(Object error) {
  final raw = _extractMessage(error);
  return mapReservationStatusRpcRawMessage(raw);
}

String _extractMessage(Object error) {
  try {
    final dynamic d = error;
    final m = d.message;
    if (m is String && m.isNotEmpty) return m;
  } catch (_) {}
  return error.toString();
}

/// 이미 문자열로 뽑힌 메시지(또는 `message` 컬럼)에 태그 매핑 적용.
String mapReservationStatusRpcRawMessage(String raw) {
  final t = raw.trim();
  if (t.contains('[E_NOT_APPROVER]')) {
    return '해당 회의실에 대한 승인 권한이 없습니다.';
  }
  if (t.contains('[E_INVALID_STATE]')) {
    return '현재 상태에서는 이 처리를 할 수 없습니다.';
  }
  if (t.contains('[E_NOT_FOUND]')) {
    return '예약을 찾을 수 없습니다.';
  }
  if (t.contains('[E_INVALID_SCOPE]')) {
    return '선택한 범위로 처리할 수 없습니다.';
  }
  if (t.contains('[E_NOT_OWNER]')) {
    return '본인 예약만 처리할 수 있습니다.';
  }
  if (t.contains('[E_OVERLAP]')) {
    return '다른 예약과 시간이 겹칩니다.';
  }
  return t;
}
