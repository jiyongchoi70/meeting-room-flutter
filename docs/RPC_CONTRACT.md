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
- 용도: 한 예약을 앵커로 승인(120) / 반려(130) / 완료(140) 처리. `scope=all`이면 동일 `repeat_group_id` 시리즈 전체(같은 회의실·동일 전이 가능 상태일 때만).
- Supabase RPC 파라미터(스네이크 케이스)

| 파라미터 | 타입 | 설명 |
|----------|------|------|
| `p_actor_uid` | text | 로그인 사용자 UID (Auth `sub`) |
| `p_target_reservation_id` | uuid | 앵커 예약 ID |
| `p_next_status` | int | `120` 승인, `130` 반려, `140` 완료 |
| `p_scope` | text | `this` \| `all` (기본 `this`) |
| `p_return_comment` | text? | 반려(130) 시 사유(선택). 승인 시 `return_comment`는 NULL로 정리 |

- 응답 행 1건: `ok`, `message`, `affected_count`, `affected_ids` (uuid 배열)

### §3a) `scope` 선택 (웹·Flutter 공통)
- `repeat_group_id`가 비어 있지 않으면(반복 시리즈): 사용자에게 **이 일정(`this`)** / **모든 일정(`all`)** 를 묻는다.
- `repeat_group_id`가 없거나 빈 문자열이면 `this`만 사용한다(다이얼로그 생략 가능).

### §3a-2) 실패 시 메시지(Flutter `mapReservationStatusRpcRawMessage` 와 동일 권장)
| 서버 메시지에 포함되는 태그 | 사용자 표시(한글) |
|---------------------------|------------------|
| `[E_NOT_APPROVER]` | 해당 회의실에 대한 승인 권한이 없습니다. |
| `[E_INVALID_STATE]` | 현재 상태에서는 이 처리를 할 수 없습니다. |
| `[E_NOT_FOUND]` | 예약을 찾을 수 없습니다. |
| `[E_INVALID_SCOPE]` | 선택한 범위로 처리할 수 없습니다. |
| `[E_NOT_OWNER]` | 본인 예약만 처리할 수 있습니다. |
| `[E_OVERLAP]` | 다른 예약과 시간이 겹칩니다. |

- `RAISE EXCEPTION` 으로만 오는 경우 PostgREST 예외의 `message` 문자열에 위 태그 또는 순수 한글이 온다. 태그가 없으면 원문을 그대로 보여도 된다.

### §3a-3) Flutter 구현 위치
- 호출: `ReservationRemoteDs.changeReservationStatus` → `supabase.rpc('rpc_change_reservation_status', …)`
- 성공 후: 화면을 닫고 캘린더에서 `fetchCalendarEvents` 등으로 **다시 조회**
- 권한 UX: `canActorApproveForRoom` 으로 버튼 표시 여부 결정(담당자 110 또는 `mr_approver`). 권한 없으면 결재 버튼을 숨긴다.

## 3b) `rpc_change_reservation_status_many`
- 용도: 서로 무관한 예약 ID 여러 개를 각각 단건 갱신(예: 웹 예약현황 그리드 다중 선택). **시리즈 자동 확장 없음.**
- Flutter 앱에 그리드 일괄 처리 UI가 없으면 **호출하지 않아도 된다.**
- 파라미터: `p_actor_uid`, `p_reservation_ids` (uuid[]), `p_next_status`, `p_return_comment`
- 응답: 위와 동일 형식 (`affected_ids` = 실제 갱신된 ID 목록)

## 오류 코드 권장
- `E_NOT_OWNER`: 본인 예약 아님
- `E_NOT_APPROVER`: 승인 권한 없음
- `E_OVERLAP`: 중복 발생
- `E_INVALID_SCOPE`: 잘못된 scope
- `E_INVALID_STATE`: 상태 전이 불가
- `E_NOT_FOUND`: 대상 없음
