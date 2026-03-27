# MEETING_ROOM 아키텍처 개요

## 목적
- 웹(`meeting_room`)과 향후 Flutter 앱이 같은 업무 규칙을 공유하도록 기준을 정리한다.

## 현재 구성
- **Frontend(Web)**: React + Vite + TypeScript
- **Backend**: Supabase(PostgreSQL + RPC)
- **주요 도메인**: 회의실 예약, 반복 예약, 승인/반려

## 핵심 데이터
- `mr_reservations`: 예약 본문, 반복 옵션, 상태
- `mr_room`: 회의실 정책(`confirm_yn`, `duplicate_yn`, 예약 가능 기간)
- `mr_users`: 사용자/권한
- `mr_approver`: 회의실 승인자
- `mr_lookup_type`, `mr_lookup_value`: 공통코드

## 반복 예약 모델
- `repeat_group_id`로 시리즈를 식별
- `"이 일정"` 수정 시 대상 행은 분리하고(자기 그룹), 필요 시 남은 행을 새 대표 그룹으로 재배정
- `"모든 일정"` 수정/이동 시 시리즈 단위 처리

## 권장 원칙
- **클라이언트는 UX**, **서버는 검증/상태변경/트랜잭션** 담당
- Web/Flutter 모두 동일 RPC를 호출해 규칙 일관성을 유지

## 상태 규칙(요약)
- 신청/승인/반려/완료 상태에 따라 허용 동작이 다름
- 이동/수정 가능 여부는 서버 검증이 최종 기준
