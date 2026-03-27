# Supabase Auth 구현 필요사항 (로그인 / 회원가입 / 비밀번호 재설정)

이미지에 나온 BTA 로그인, 회원가입, 비밀번호 재설정 화면을 Supabase Auth로 구현하기 위해 필요한 사항을 정리했습니다.

---

## 1. Supabase 대시보드 설정

### 1-1. Authentication 활성화

- **Authentication** → **Providers** 에서 **Email** 사용 설정
- (선택) **Confirm email**: 켜면 가입 시 이메일 인증 링크 발송, 끄면 바로 로그인 가능

### 1-2. Redirect URL 등록

- **Authentication** → **URL Configuration**
- **Site URL**: 실제 서비스 주소 (예: `https://your-app.com`) 또는 로컬 개발 시 `http://localhost:5173`
- **Redirect URLs**에 다음 추가:
  - `http://localhost:5173/**` (로컬 개발)
  - `http://localhost:5173` (SPA 루트)
  - 배포 시 실제 도메인 (예: `https://your-app.web.app/**`)

비밀번호 재설정·이메일 인증 후 돌아올 주소로 사용됩니다.

### 1-3. 이메일 템플릿 (선택)

- **Authentication** → **Email Templates**
- **Confirm signup**: 회원가입 인증 메일
- **Reset password**: 비밀번호 재설정 메일  
한글 문구나 회사 로고로 수정할 수 있습니다.

### 1-4. 추가 설정 (선택)

- **Auth** → **Settings**:
  - **Minimum password length**: 비밀번호 최소 길이 (기본 6)
  - **Enable phone confirmations**: 전화번호 인증 사용 시

---

## 2. 프론트엔드 필요사항

### 2-1. 패키지

- `@supabase/supabase-js` (이미 DB 연동 시 설치됨)
- 라우팅: **react-router-dom** (로그인/회원가입/비밀번호재설정/메인 화면 경로 분리)

```bash
npm install react-router-dom
```

### 2-2. Supabase 클라이언트

- DB 가이드와 동일하게 `.env`의 `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`로 `createClient()` 한 번만 생성해 사용
- Auth 메서드는 모두 이 클라이언트에서 제공: `supabase.auth.signInWithPassword()`, `supabase.auth.signUp()`, `supabase.auth.resetPasswordForEmail()` 등

### 2-3. 화면(라우트) 구성

| 화면 | 경로(예) | Supabase Auth API |
|------|----------|-------------------|
| 로그인 | `/login` | `signInWithPassword({ email, password })` |
| 회원가입 | `/signup` | `signUp({ email, password, options: { data: { full_name, phone } } })` |
| 비밀번호 재설정 | `/reset-password` | `resetPasswordForEmail(email, { redirectTo: '...' })` |
| 재설정 후 새 비밀번호 입력 | `/update-password` (또는 쿼리로 구분) | URL hash의 `access_token` 등으로 세션 복구 후 `updateUser({ password })` |
| 메인(예약) | `/` 또는 `/calendar` | 로그인 여부는 `supabase.auth.getUser()` 또는 `onAuthStateChange`로 판단 |

### 2-4. 로그인 화면 (이미지 1)

- **필드**: 이메일, 비밀번호
- **버튼**: 로그인 → `signInWithPassword`
- **링크**:
  - "비밀번호를 잊으셨나요?" → `/reset-password`
  - "회원가입" → `/signup`
- **에러 처리**: `signInWithPassword` 실패 시 메시지 표시 (이메일/비밀번호 불일치 등)
- **성공 시**: 메인(예약) 화면으로 이동

### 2-5. 회원가입 화면 (이미지 2)

- **필드**: 성명, 전화번호, 이메일, 비밀번호, 비밀번호 확인
- **버튼**: 회원가입 → 유효성 검사(비밀번호 일치, 형식) 후 `signUp({ email, password, options: { data: { full_name, phone } } })`
- **링크**: "로그인" → `/login`
- **성공 시**:
  - 이메일 인증 사용 시: "이메일에서 인증 링크를 확인해 주세요" 안내 후 로그인 페이지로
  - 인증 비사용 시: 바로 로그인 처리 후 메인으로 이동
- **user metadata**: Supabase는 `email`, `password`만 필수. 성명·전화번호는 `options.data`에 넣으면 `user.user_metadata.full_name`, `user.user_metadata.phone`로 저장 가능 (추가 테이블에 프로필 저장도 가능)

### 2-6. 비밀번호 재설정 화면 (이미지 3)

- **필드**: 이메일
- **버튼**: "재설정 이메일 보내기" → `resetPasswordForEmail(email, { redirectTo: `${window.location.origin}/update-password` })`
- **링크**: "로그인으로 돌아가기" → `/login`
- **성공 시**: "이메일로 재설정 링크를 보냈습니다" 안내
- **재설정 완료**: 사용자가 메일 링크 클릭 시 Supabase가 `redirectTo`로 보내며, URL에 토큰이 붙음. 해당 페이지에서 새 비밀번호 입력 후 `updateUser({ password })` 호출

---

## 3. 인증 상태 관리

- **세션 확인**: `supabase.auth.getSession()` 또는 `supabase.auth.getUser()`
- **리스너**: `supabase.auth.onAuthStateChange((event, session) => { ... })` 로 로그인/로그아웃 시 라우트 전환 또는 전역 상태 갱신
- **보호된 라우트**: 메인(예약) 화면은 로그인된 사용자만 접근하도록 하고, 비로그인 시 `/login`으로 리다이렉트

---

## 4. DB와의 연동 (선택)

- **예약 테이블에 사용자 연결**: `reservations`에 `user_id UUID REFERENCES auth.users(id)` 컬럼 추가 시, RLS로 "본인 예약만 조회/수정/삭제" 정책 적용 가능
- **프로필 테이블**: 성명·전화번호를 별도 `profiles` 테이블에 저장하려면 `auth.users`와 `id`로 연결하고, 회원가입 후 트리거나 클라이언트에서 한 번 insert

---

## 5. 체크리스트

- [ ] Supabase **Authentication** → **Providers** 에서 Email 활성화
- [ ] **URL Configuration** 에 Site URL, Redirect URLs 설정
- [ ] (선택) 이메일 인증 사용 시 Confirm email 설정 및 Email Templates 수정
- [ ] 프론트에 `react-router-dom` 설치
- [ ] 로그인/회원가입/비밀번호재설정/메인 라우트 및 컴포넌트 생성
- [ ] 각 화면에서 `signInWithPassword`, `signUp`, `resetPasswordForEmail`, `updateUser` 호출
- [ ] `onAuthStateChange`로 로그인 여부에 따른 리다이렉트 처리
- [ ] (선택) RLS 및 `user_id`로 예약 데이터 권한 제어

이 문서와 이미지 구성을 기준으로 컴포넌트와 라우트를 구현하면 Supabase Auth 기반 로그인/회원가입/비밀번호 재설정 플로우를 완성할 수 있습니다.
