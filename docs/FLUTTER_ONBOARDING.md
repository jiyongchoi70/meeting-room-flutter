# Flutter 연동 온보딩 가이드

## 1. 프로젝트 생성 권장 위치
- 웹과 분리:
  - `C:\MyProject\BTA\meeting_room` (기존 웹)
  - `C:\MyProject\BTA\meeting_room_flutter` (신규 Flutter)

## 2. 백엔드 공유 방식
- Flutter도 기존과 동일한 Supabase 프로젝트를 사용
- 같은 테이블/RPC를 호출하면 규칙 설명을 다시 반복할 필요가 줄어든다

## 3. 필수 문서 먼저 읽기
- `docs/ARCHITECTURE.md`
- `docs/RESERVATION_RULES.md`
- `docs/RPC_CONTRACT.md`

## 4. Flutter 패키지(기본)
- `supabase_flutter`
- 상태관리 패키지(팀 표준 선택: Riverpod/Bloc 등)

## 5. 최소 구현 순서
1. 로그인/세션 유지
2. 캘린더 조회(read)
3. 단건 저장(single)
4. 반복 저장/수정(this/all)
5. 캘린더 이동(this/all)

## 6. 재사용 전략
- UI는 Flutter로 새로 구현
- 검증/반복/권한은 서버 RPC 재사용
- 클라이언트는 입력/표시/로딩에 집중

## 7. 체크리스트
- [ ] Supabase URL/anon key 연결
- [ ] 인증/권한 흐름 확인
- [ ] RPC 호출 공통 에러 처리(`E_OVERLAP`, `[E_NOT_APPROVER]`, `[E_INVALID_STATE]` 등)
- [x] 결재: `rpc_change_reservation_status` (예약 상세·`ReservationEditorPage`) — `docs/RPC_CONTRACT.md` §3 / §3a
- [ ] (선택) 그리드 일괄 시에만 `rpc_change_reservation_status_many` — Flutter에 해당 UI 없으면 생략
- [ ] 반복 this/all 시나리오 테스트
- [ ] 대표행 분리/재그룹핑 시나리오 테스트
