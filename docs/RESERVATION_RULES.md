# 예약/반복 규칙 정리

## 공통
- 중복 검사는 같은 회의실/시간 겹침 기준
- 회의실 정책(`duplicate_yn`, `confirm_yn`, 예약 가능 기간)을 따른다

## 저장 시 검증·신규 status (Flutter `ReservationRemoteDs` / 웹 `reservations.ts` 정합)
- **중복 검사**: **`duplicate_yn = 110` 인 회의실만** 시간 중복 허용. **NULL·120·기타**는 모두 겹침 검사(미설정 NULL로 중복이 쌓이는 경우 방지). 반려(130) 제외.
- (웹 TS는 여전히 `duplicate_yn === 120` 일 때만 RPC 호출 — 웹도 동일 정책으로 맞추는 것을 권장.)
- **신규 예약 `status`**: `mr_users.user_type = 110` → 140; 아니면 해당 `room_id`의 `mr_approver`에 본인이 있으면 140; 그 외 `confirm_yn = 120` → 140, 아니면 110.
- **`rpc_split_series_this_occurrence_save` / `_move`**: `mr_room.duplicate_yn = 120`일 때만 RPC 내부에서 동일 중복 검사(배포된 SQL 기준).
- **트리거 `tr_reservation_overlap_guard`**: `duplicate_yn = 120`인 회의실은 `mr_reservations` INSERT·일시 UPDATE 시 DB에서 한 번 더 겹침 차단(동시 저장 레이스 대비). `supabase/trigger_reservation_overlap_guard.sql` 배포 필요.

## 반복 생성
- 반복 종류(`repeat_id`) + 종료일(`repeat_end_ymd`) 조합으로 occurrence 생성
- `repeat_end_ymd`를 초과하는 occurrence는 생성하지 않는다

## 수정 scope
- **이 일정(this)**: 대상 occurrence만 수정
- **모든 일정(all)**: 시리즈 전체를 규칙에 맞춰 재적용

## 대표행 분리
- 대상이 대표행(`repeat_group_id == reservation_id`)이면:
  - 대상은 단건 그룹으로 분리
  - 남은 occurrence는 새 대표 `reservation_id`를 `repeat_group_id`로 재배정
- 대상이 대표행이 아니면 대상만 분리

## 캘린더 이동
- this/all scope 선택 후 처리
- all 이동은 시리즈 anchor 기준 delta 적용
- 이동 결과가 `repeat_end_ymd`를 넘는 건은 제거/비생성

## 날짜 규칙
- 시작일과 종료일이 다르면 반복은 `반복없음`으로 강제

## 상태/권한
- 본인 예약만 수정/이동 허용(정책 기준)
- 승인/반려/완료 상태별 허용 동작은 정책에 따른다

### 서버 측 결재 RPC (권장)
- `supabase/rpc_change_reservation_status.sql` 배포 후 사용
- **lookup 180 (앱과 동일)**: `110` 신청 → `120` 승인 / `130` 반려; `120` 승인 → `140` 완료
- **권한**: `mr_users.user_type = 110`(담당자) 이거나 `mr_approver`에 `(로그인 user_uid, 예약 room_id)` 행이 있을 때만 승인·반려·완료 처리 가능
- **`rpc_change_reservation_status`**: 한 건을 앵커로 `this`(해당 행만) 또는 `all`(같은 `repeat_group_id` 시리즈 전체) 갱신
- **`rpc_change_reservation_status_many`**: ID 배열을 각각 단건으로 갱신(그리드에서 서로 다른 예약 다중 선택 시). 시리즈 전체를 한 번에 바꾸려면 앵커 + `all` RPC 사용
- 상세 계약: `docs/RPC_CONTRACT.md` §3
