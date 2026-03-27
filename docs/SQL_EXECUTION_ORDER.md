# SQL 실행 순서 가이드

## 1. 목적
- Supabase SQL을 안전한 순서로 적용하고, 적용 직후 검증까지 일관되게 수행합니다.

## 2. 대상 SQL 파일
1. `docs/SETUP_DATABASE.md` (기본 테이블/인덱스)
2. `supabase/rpc_check_reservation_overlap.sql`
3. `supabase/rpc_repeat_group_operations.sql`
4. `supabase/rpc_flutter_reservation_core.sql`
5. `supabase/rls_allow_common_code_read.sql` (선택)

## 3. 실행 전 체크
1. Supabase 프로젝트/환경(dev/stg/prod) 확인
2. 백업 또는 스냅샷 확보
3. SQL Editor 권한 확인

## 4. 권장 실행 순서
1. 기본 스키마/테이블 생성 (`SETUP_DATABASE.md`)
2. 중복 검사 RPC 배포 (`rpc_check_reservation_overlap.sql`)
3. 반복 그룹 RPC 배포 (`rpc_repeat_group_operations.sql`)
4. Flutter 연동 RPC 배포 (`rpc_flutter_reservation_core.sql`)
5. RLS 정책 적용 (`rls_allow_common_code_read.sql`, 필요 시)

## 5. 권장 실행 명령 체크리스트
- [ ] 1단계 스키마 완료
- [ ] 2단계 overlap RPC 완료
- [ ] 3단계 repeat group RPC 완료
- [ ] 4단계 flutter core RPC 완료
- [ ] 5단계 RLS 정책 점검
- [ ] 6단계 시나리오 테스트 완료

## 6. 각 SQL 실행 후 바로 돌릴 테스트 쿼리

### 6-1. 기본 스키마/테이블 생성 후
```sql
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'mr_users', 'mr_room', 'mr_reservations', 'mr_approver',
    'mr_lookup_type', 'mr_lookup_value'
  )
order by table_name;
```

```sql
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'mr_reservations'
  and column_name in (
    'reservation_id','room_id','start_ymd','end_ymd',
    'repeat_id','repeat_end_ymd','repeat_cycle','repeat_user',
    'repeat_group_id','status','create_user'
  )
order by column_name;
```

### 6-2. `rpc_check_reservation_overlap.sql` 실행 후
```sql
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'check_reservation_overlap';
```

```sql
select *
from public.check_reservation_overlap(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '2026-04-01T09:00:00+09'::timestamptz,
  '2026-04-01T10:00:00+09'::timestamptz,
  null
);
```

### 6-3. `rpc_repeat_group_operations.sql` 실행 후
```sql
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'check_reservation_overlap_excluding',
    'update_repeat_group_dates_bulk',
    'replace_repeat_group_reservations'
  )
order by routine_name;
```

```sql
select *
from public.check_reservation_overlap_excluding(
  '00000000-0000-0000-0000-000000000000'::uuid,
  '2026-04-01T09:00:00+09'::timestamptz,
  '2026-04-01T10:00:00+09'::timestamptz,
  array[]::uuid[]
);
```

### 6-4. `rpc_flutter_reservation_core.sql` 실행 후
```sql
select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'rpc_split_series_this_occurrence_save',
    'rpc_split_series_this_occurrence_move'
  )
order by routine_name;
```

```sql
select *
from public.rpc_split_series_this_occurrence_move(
  'actor_user_uid',
  '00000000-0000-0000-0000-000000000000'::uuid,
  '2026-04-07T14:30:00+09:00'::timestamptz,
  '2026-04-07T15:30:00+09:00'::timestamptz
);
```

## 7. 실패 시 빠른 점검
1. `operator does not exist: character varying = uuid`
   - `repeat_group_id` 타입과 캐스팅 로직 확인
2. `예약 작성자 정보가 없습니다`
   - `create_user` 값 존재/RLS 조회 허용 확인
3. `중복이 됩니다`
   - 실제 겹침 여부 및 exclude 대상 확인

## 8. SQL 실행 후 테스트 쿼리
1. 대표행 분리 후 그룹 재배정 확인
```sql
select reservation_id, repeat_group_id, start_ymd, end_ymd
from mr_reservations
where title ilike '%테스트%'
order by start_ymd;
```

2. `repeat_end_ymd` 컷오프 확인
```sql
select reservation_id, start_ymd, repeat_end_ymd
from mr_reservations
where title ilike '%테스트%'
order by start_ymd;
```

3. all 이동 후 anchor 기준 재생성 확인
```sql
select repeat_group_id, min(start_ymd) as first_start, max(start_ymd) as last_start, count(*) as cnt
from mr_reservations
where title ilike '%테스트%'
group by repeat_group_id
order by first_start;
```

## 9. 환경별(dev/stg/prod) 실행 체크 표

| 항목 | dev | stg | prod | 담당자 | 완료일 | 이슈링크 | 비고 |
|---|---|---|---|---|---|---|---|
| 대상 Supabase 프로젝트 확인 | [ ] | [ ] | [ ] |  |  |  | URL/Project Ref 확인 |
| 실행 전 백업/스냅샷 | [ ] | [ ] | [ ] |  |  |  | prod 필수 권장 |
| 1) 스키마/테이블 SQL 실행 | [ ] | [ ] | [ ] |  |  |  | `SETUP_DATABASE.md` 기준 |
| 2) overlap RPC 실행 | [ ] | [ ] | [ ] |  |  |  | `rpc_check_reservation_overlap.sql` |
| 3) repeat group RPC 실행 | [ ] | [ ] | [ ] |  |  |  | `rpc_repeat_group_operations.sql` |
| 4) flutter core RPC 실행 | [ ] | [ ] | [ ] |  |  |  | `rpc_flutter_reservation_core.sql` |
| 5) RLS 정책 적용/검토 | [ ] | [ ] | [ ] |  |  |  | 환경별 정책 상이 가능 |
| 6) 함수 생성 확인 쿼리 통과 | [ ] | [ ] | [ ] |  |  |  | `information_schema.routines` |
| 7) 대표행 분리 시나리오 통과 | [ ] | [ ] | [ ] |  |  |  | this scope 핵심 |
| 8) repeat_end 컷오프 통과 | [ ] | [ ] | [ ] |  |  |  | 종료일 초과 비생성 |
| 9) all 이동 재생성 통과 | [ ] | [ ] | [ ] |  |  |  | anchor 기준 이동 |
| 10) 배포/반영 이력 기록 | [ ] | [ ] | [ ] |  |  |  | 날짜/담당자/SQL 버전 |

