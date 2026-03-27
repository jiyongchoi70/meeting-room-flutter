목적
이 문서는 Supabase SQL을 어떤 순서로 실행해야 안전한지 정리합니다.
웹(meeting_room)과 Flutter(meeting_room_flutter) 모두 같은 DB/RPC를 공유합니다.

대상 파일
docs/SETUP_DATABASE.md
supabase/rpc_check_reservation_overlap.sql
supabase/rpc_repeat_group_operations.sql
supabase/rpc_flutter_reservation_core.sql
supabase/rls_allow_common_code_read.sql (선택)

0. 사전 확인
Supabase 프로젝트/DB 연결 확인
SQL Editor 접속
운영 DB라면 백업 또는 스냅샷 권장

1. 기본 스키마/테이블 생성
먼저 docs/SETUP_DATABASE.md에 있는 테이블/인덱스 생성 SQL을 실행합니다.

필수 테이블(예시):

mr_users
mr_room
mr_reservations
mr_approver
mr_lookup_type, mr_lookup_value
확인 포인트:

mr_reservations에 아래 컬럼이 있어야 함
reservation_id
start_ymd, end_ymd
repeat_id, repeat_end_ymd, repeat_cycle, repeat_user
repeat_group_id
status, create_user


2. 중복 검사 RPC
supabase/rpc_check_reservation_overlap.sql 실행

목적:

단건 저장/수정/이동 중복 검사
확인:

함수 생성됨: check_reservation_overlap(...)
GRANT EXECUTE가 authenticated에 적용됨


3. 반복 그룹 공통 RPC
supabase/rpc_repeat_group_operations.sql 실행

목적:

그룹 일괄 이동/교체용 함수
exclude 중복 검사
delete + recreate 기반 처리
확인 함수(예):

check_reservation_overlap_excluding
update_repeat_group_dates_bulk
replace_repeat_group_reservations


4. Flutter 전용 핵심 RPC
supabase/rpc_flutter_reservation_core.sql 실행

목적:

"이 일정" 저장/이동 시 대표행 분리 + follower 재그룹핑
모바일에서도 웹과 동일한 규칙 보장
확인 함수:

rpc_split_series_this_occurrence_save
rpc_split_series_this_occurrence_move


5. RLS 정책 (환경별)
개발/테스트:

필요 시 supabase/rls_allow_common_code_read.sql 적용
운영:

최소권한 원칙으로 정책 재검토 후 적용
authenticated 기준 read/write 범위 명확화


6. 실행 후 검증 시나리오 (필수)
반복 예약 생성 (예: 매주, 종료일 지정)
"이 일정" 수정 (대표행/비대표행 각각)
"모든 일정" 이동
repeat_end_ymd 초과 occurrence 비생성 확인
중복 케이스에서 오류 메시지 확인


7. 롤백/재실행 주의
함수는 CREATE OR REPLACE FUNCTION 기반이라 재실행 가능
다만 스키마 변경(컬럼 타입 변경)은 별도 마이그레이션으로 관리
운영 반영 시 변경 이력(날짜/담당자/SQL 파일 버전) 기록 권장