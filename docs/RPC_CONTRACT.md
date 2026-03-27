# RPC 계약서(초안)

## 목적
- Web/Flutter가 동일한 서버 검증 로직을 호출하도록 입출력 계약을 표준화한다.

## 공통 응답 형식
```json
{
  "ok": true,
  "message": "saved",
  "affected_ids": []
}
```

## 1) `rpc_save_reservation`
- 용도: 신규/수정(single/this/all) 저장 통합
- 입력(예시)
```json
{
  "actor_uid": "user_uid",
  "scope": "single|this|all",
  "target_reservation_id": "uuid-or-null",
  "payload": {
    "title": "string",
    "room_id": "uuid",
    "allday_yn": "Y|N",
    "start_ymd": "ISO",
    "end_ymd": "ISO",
    "repeat_id": 120,
    "repeat_end_ymd": "YYYYMMDD"
  }
}
```

## 2) `rpc_move_reservation`
- 용도: 드래그/리사이즈 이동(this/all) 처리
- 입력(예시)
```json
{
  "actor_uid": "user_uid",
  "scope": "this|all",
  "target_reservation_id": "uuid",
  "new_start_ymd": "ISO",
  "new_end_ymd": "ISO"
}
```

## 3) `rpc_change_reservation_status`
- 용도: 승인/반려 상태 변경
- 입력(예시)
```json
{
  "actor_uid": "approver_uid",
  "scope": "this|all",
  "target_reservation_id": "uuid",
  "next_status": 120,
  "return_comment": null
}
```

## 오류 코드 권장
- `E_NOT_OWNER`: 본인 예약 아님
- `E_NOT_APPROVER`: 승인 권한 없음
- `E_OVERLAP`: 중복 발생
- `E_INVALID_SCOPE`: 잘못된 scope
- `E_INVALID_STATE`: 상태 전이 불가
- `E_NOT_FOUND`: 대상 없음
