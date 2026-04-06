// 웹 `src/api/reservations.ts` 및 기획(저장 시 검증)과 동일.

/// `mr_room.duplicate_yn == 110` 일 때만 같은 회의실 시간 중복 **허용**.
/// 그 외(NULL·120·기타)는 모두 중복 검사(미설정 NULL은 실제 DB에서 중복이 생기는 경우가 많아 보수적으로 검사).
const int kDuplicateYnAllowOverlap = 110;

/// (참고) 웹 주석상 `120` = 중복 시 저장 불가. Flutter/트리거는 `110`이 아니면 검사.
const int kDuplicateYnEnforceOverlap = 120;

/// 중복 검사를 할지 여부.
bool duplicateYnRequiresOverlapCheck(int? duplicateYn) =>
    duplicateYn != kDuplicateYnAllowOverlap;

/// `mr_room.confirm_yn == 120` 이면 승인 없이 완료 처리.
const int kConfirmYnAutoComplete = 120;

/// `mr_users.user_type == 110` 담당자(관리자) → 신규 예약 `status` 140.
const int kMrUserTypeManager = 110;

const int kReservationStatusApplied = 110;
const int kReservationStatusCompleted = 140;
