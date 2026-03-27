# DB 저장 설정 가이드 (Supabase + PostgreSQL)

메인 화면에서 만든 예약을 DB에 저장하려면 아래 순서대로 설정하면 됩니다.

---

## 1. Supabase 프로젝트 생성

1. [Supabase](https://supabase.com) 가입 후 **New Project** 생성
2. **Organization** 선택 → **Project name** 입력 → **Database password** 설정 후 생성  ZvX2VsSoy3ErKtPy
3. 프로젝트 대시보드에서 다음 정보를 확인합니다:
   - **Project URL** (예: `https://xxxxx.supabase.co`)  https://hlqqyeeldzinxcrqkffv.supabase.co
   - **anon public** 키 (Settings → API → Project API keys)    sb_publishable_xmZhsPITugIaBZfzl-o5ww_-oiQvfEu

---

## 2. DB 테이블 생성

Supabase 대시보드 **SQL Editor**에서 아래 SQL을 실행합니다.

### 2-1. 회의실 테이블

**방법 A – UUID 자동 생성** (기본, 추천)

```sql
-- 회의실 마스터
CREATE TABLE meeting_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  capacity INTEGER,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 예시 데이터 (선택, id 생략 시 자동 UUID)
INSERT INTO meeting_rooms (name, capacity) VALUES
  ('본당 2층 302호', 8),
  ('Open회의실 411-4', 8),
  ('본관 1층 베들레헴', 12),
  ('본관 지하 비전홀', 30);
```

**방법 B – 숫자 시퀀스(1, 2, 3, 4…) 자동 등록**

```sql
-- 회의실 마스터 (id 자동 1, 2, 3, 4 ...)
CREATE TABLE meeting_rooms (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  capacity INTEGER,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 예시 데이터 (id 생략 시 1부터 자동 증가)
INSERT INTO meeting_rooms (name, capacity) VALUES
  ('본당 2층 302호', 8),
  ('Open회의실 411-4', 8),
  ('본관 1층 베들레헴', 12),
  ('본관 지하 비전홀', 30);
```

- `BIGSERIAL`: 행이 추가될 때마다 1, 2, 3, 4 … 처럼 자동으로 숫자가 붙습니다.
- 시퀀스 방식으로 테이블을 쓰려면 **예약 테이블(2-2)** 의 `room_id`도 `BIGINT`로 맞춰야 합니다 (아래 2-2-B 참고).

### 2-2. 예약 테이블

**방법 A – meeting_rooms.id가 UUID일 때**

```sql
-- 예약
CREATE TABLE reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  room_id UUID NOT NULL REFERENCES meeting_rooms(id) ON DELETE CASCADE,
  booker TEXT,
  is_all_day BOOLEAN DEFAULT false,
  color TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 기간 조회용 인덱스
CREATE INDEX idx_reservations_dates ON reservations (start_at, end_at);
CREATE INDEX idx_reservations_room ON reservations (room_id);
```

**방법 B – meeting_rooms.id가 BIGSERIAL(숫자)일 때**

```sql
-- 예약 (room_id는 회의실의 숫자 id)
CREATE TABLE reservations (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  room_id BIGINT NOT NULL REFERENCES meeting_rooms(id) ON DELETE CASCADE,
  booker TEXT,
  is_all_day BOOLEAN DEFAULT false,
  color TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_reservations_dates ON reservations (start_at, end_at);
CREATE INDEX idx_reservations_room ON reservations (room_id);
```

- `start_at`, `end_at`: ISO 형식으로 저장 (타임존 포함)
- `room_id`: `meeting_rooms.id`와 연결 (UUID면 UUID, 숫자면 BIGINT)
- `booker`, `color`, `is_all_day`: 현재 화면에서 쓰는 필드와 맞춤

### 2-3. 공통코드 테이블 (대분류/중분류)

```sql
-- 대분류 (mr_lookup_type)
CREATE TABLE mr_lookup_type (
  lookup_type_id BIGSERIAL PRIMARY KEY,
  lookup_type_cd INTEGER NOT NULL,
  lookup_type_nm VARCHAR(100) NOT NULL
);

-- 중분류 (mr_lookup_value)
CREATE TABLE mr_lookup_value (
  lookup_value_id BIGSERIAL PRIMARY KEY,
  lookup_type_id BIGINT NOT NULL REFERENCES mr_lookup_type(lookup_type_id) ON DELETE CASCADE,
  lookup_value_cd INTEGER NOT NULL,
  lookup_value_nm VARCHAR(50) NOT NULL,
  remark VARCHAR(200),
  seq INTEGER,
  start_ymd VARCHAR(8),
  end_ymd VARCHAR(8),
  create_ymd VARCHAR(8)
);

CREATE INDEX idx_mr_lookup_value_type ON mr_lookup_value (lookup_type_id);
```

- `lookup_type_cd` / `lookup_value_cd`: 신규 저장 시 `max(코드)+10` 규칙으로 생성 (앱에서 계산 가능).
- `start_ymd`, `end_ymd`, `create_ymd`: `YYYYMMDD` 문자열 저장 권장.

---

## 3. Row Level Security (RLS, 선택)

로그인 없이 모든 사용자가 읽기/쓰기 가능하게 하려면 RLS를 끄거나, 공개 정책을 둡니다.

**옵션 A – RLS 비활성화 (개발/데모용)**  
테이블 생성 후 Table Editor에서 각 테이블 → **RLS**를 끕니다.

**옵션 B – 인증 후에만 접근**  
나중에 Supabase Auth를 붙일 때:

```sql
ALTER TABLE meeting_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;

-- 로그인한 사용자만 조회/등록/수정/삭제
CREATE POLICY "Allow all for authenticated" ON meeting_rooms
  FOR ALL USING (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated" ON reservations
  FOR ALL USING (auth.role() = 'authenticated');
```

---

## 4. 프론트엔드 환경 변수

프로젝트 루트에 `.env` 파일을 만들고 Supabase URL과 anon key를 넣습니다.

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_public_key_here
```

- 반드시 `VITE_` 접두사가 있어야 Vite에서 클라이언트로 노출됩니다.
- `.env`는 Git에 올리지 말고, `.env.example`만 커밋해 두는 것을 권장합니다.

---

## 5. 패키지 설치

```bash
npm install @supabase/supabase-js
```

---

## 6. Supabase 클라이언트 초기화

`src/lib/supabase.ts` (또는 `src/supabaseClient.ts`) 파일을 만들어 다음처럼 작성합니다.

```ts
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY must be set in .env')
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

---

## 7. 데이터 연동 흐름

| 동작           | Mock 현재 동작              | DB 연동 시 할 일                                      |
|----------------|-----------------------------|--------------------------------------------------------|
| 화면 로드      | `MOCK_ROOMS`, `MOCK_EVENTS` | `meeting_rooms` / `reservations` 테이블에서 select    |
| 예약 저장      | `setEvents` 로 state만 변경 | `reservations`에 insert 후 목록 다시 조회 또는 state 갱신 |
| 예약 수정      | `setEvents`로 해당 id 수정  | `reservations` update 후 목록/state 갱신              |
| 예약 삭제      | (미구현)                    | `reservations` delete                                 |
| 드래그/리사이즈| `handleEventDrop` 등에서 setEvents | update API 호출 후 목록/state 갱신              |

- **회의실 목록**: 앱 로드 시 한 번 `supabase.from('meeting_rooms').select('*')`로 가져와 state에 넣습니다.
- **예약 목록**: 보여줄 기간(예: 현재 달 ±1달)으로 `start_at`, `end_at` 조건을 걸어 `reservations`를 조회한 뒤, 기존 `ReservationEvent` 형태로 변환해 캘린더에 넘깁니다.
- **저장/수정**: `handleSaveReservation`과 드래그/리사이즈 핸들러 안에서 `supabase.from('reservations').insert()` / `.update()`를 호출하고, 성공 시 위에서 조회한 예약 목록을 다시 불러오거나, 반환된 행으로 state만 갱신합니다.

---

## 8. 타입/필드 매핑

- **DB → 화면**  
  `reservations`의 `id`, `title`, `start_at`, `end_at`, `room_id`, `booker`, `is_all_day`, `color`를  
  `ReservationEvent`의 `id`, `title`, `start`, `end`, `roomId`, `roomName`(rooms 조인 또는 캐시), `booker`, `extendedProps` 등으로 변환합니다.
- **화면 → DB**  
  모달/드래그에서 나온 `start`, `end`, `roomId`, `title`, `booker` 등을 `start_at`, `end_at`, `room_id`, `title`, `booker`로 넣어 insert/update합니다.

---

## 9. 체크리스트

- [ ] Supabase 프로젝트 생성
- [ ] `meeting_rooms`, `reservations` 테이블 및 인덱스 생성
- [ ] (선택) RLS 설정
- [ ] `.env`에 `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` 설정
- [ ] `npm install @supabase/supabase-js`
- [ ] `src/lib/supabase.ts` 등으로 클라이언트 초기화
- [ ] App에서 mock 대신 Supabase 조회/저장/수정/삭제로 교체

이후 실제로 `App.tsx`와 `MainCalendar` 등에서 mock을 제거하고 위 흐름대로 API를 붙이면 DB에 저장되도록 할 수 있습니다. 원하면 그 부분 코드 구조(예: `src/api/reservations.ts`, `src/hooks/useReservations.ts` 등)도 정리해 줄 수 있습니다.
