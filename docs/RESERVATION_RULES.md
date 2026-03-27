# 예약/반복 규칙 정리

## 공통
- 중복 검사는 같은 회의실/시간 겹침 기준
- 회의실 정책(`duplicate_yn`, `confirm_yn`, 예약 가능 기간)을 따른다

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
