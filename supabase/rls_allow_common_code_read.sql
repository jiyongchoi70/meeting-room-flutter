-- 공통코드 테이블 조회 허용 (DB에 데이터가 있는데 앱에서 조회가 안 될 때)
-- Supabase 대시보드 → SQL Editor에서 이 스크립트를 실행하세요.
-- Row Level Security(RLS)가 켜져 있으면 정책이 없을 때 SELECT가 빈 결과를 반환합니다.

-- 기존 정책이 있으면 제거 후 생성 (한 번만 실행)
DROP POLICY IF EXISTS "Allow public read mr_lookup_type" ON public.mr_lookup_type;
CREATE POLICY "Allow public read mr_lookup_type"
ON public.mr_lookup_type
FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "Allow public read mr_lookup_value" ON public.mr_lookup_value;
CREATE POLICY "Allow public read mr_lookup_value"
ON public.mr_lookup_value
FOR SELECT
TO anon, authenticated
USING (true);

-- (선택) 추가/수정/삭제도 허용하려면 아래 정책을 추가하세요.
-- INSERT
-- CREATE POLICY "Allow insert mr_lookup_type" ON public.mr_lookup_type FOR INSERT TO anon, authenticated WITH CHECK (true);
-- CREATE POLICY "Allow insert mr_lookup_value" ON public.mr_lookup_value FOR INSERT TO anon, authenticated WITH CHECK (true);
-- UPDATE
-- CREATE POLICY "Allow update mr_lookup_type" ON public.mr_lookup_type FOR UPDATE TO anon, authenticated USING (true);
-- CREATE POLICY "Allow update mr_lookup_value" ON public.mr_lookup_value FOR UPDATE TO anon, authenticated USING (true);
-- DELETE
-- CREATE POLICY "Allow delete mr_lookup_value" ON public.mr_lookup_value FOR DELETE TO anon, authenticated USING (true);
