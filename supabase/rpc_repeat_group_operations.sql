-- 반복 예약 일괄 수정용 RPC (한 트랜잭션)
-- Supabase SQL Editor에서 실행 후 사용합니다.

-- 여러 예약 ID를 제외하고 중복 검사 (그룹 일괄 이동·교체 시)
CREATE OR REPLACE FUNCTION public.check_reservation_overlap_excluding(
  p_room_id UUID,
  p_start_ymd TIMESTAMPTZ,
  p_end_ymd TIMESTAMPTZ,
  p_exclude_ids UUID[] DEFAULT ARRAY[]::UUID[]
)
RETURNS TABLE (has_overlap BOOLEAN, conflict_ymd TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    TRUE,
    (EXTRACT(MONTH FROM mr.start_ymd)::INT)::TEXT || ' 월 ' || (EXTRACT(DAY FROM mr.start_ymd)::INT)::TEXT || ' 일'
  FROM mr_reservations mr
  WHERE mr.room_id = p_room_id
    AND (mr.status IS NULL OR mr.status <> 130)
    AND NOT (mr.reservation_id = ANY(p_exclude_ids))
    AND p_start_ymd < mr.end_ymd
    AND p_end_ymd > mr.start_ymd
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::TEXT;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.check_reservation_overlap_excluding(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID[]) IS
  '중복 검사. p_exclude_ids에 있는 예약은 제외(같은 반복 그룹 일괄 이동 시).';

GRANT EXECUTE ON FUNCTION public.check_reservation_overlap_excluding(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID[]) TO anon;
GRANT EXECUTE ON FUNCTION public.check_reservation_overlap_excluding(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID[]) TO authenticated;

-- 반복 그룹의 여러 예약 일시만 일괄 갱신
CREATE OR REPLACE FUNCTION public.update_repeat_group_dates_bulk(
  p_updates JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  u JSONB;
BEGIN
  FOR u IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    UPDATE mr_reservations
    SET
      start_ymd = (u->>'start_ymd')::timestamptz,
      end_ymd = (u->>'end_ymd')::timestamptz,
      update_at = now()
    WHERE reservation_id = (u->>'reservation_id')::uuid;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.update_repeat_group_dates_bulk(JSONB) IS
  '반복 그룹 내 예약들의 start_ymd/end_ymd 일괄 수정.';

GRANT EXECUTE ON FUNCTION public.update_repeat_group_dates_bulk(JSONB) TO anon;
GRANT EXECUTE ON FUNCTION public.update_repeat_group_dates_bulk(JSONB) TO authenticated;

-- 같은 repeat_group_id 전부 삭제 후 새 행 삽입 (모든 일정 수정 = 삭제 후 재등록)
CREATE OR REPLACE FUNCTION public.replace_repeat_group_reservations(
  p_repeat_group_id UUID,
  p_rows JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  elem JSONB;
BEGIN
  DELETE FROM mr_reservations
  WHERE repeat_group_id = p_repeat_group_id
     OR reservation_id = p_repeat_group_id;

  FOR elem IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    INSERT INTO mr_reservations (
      reservation_id,
      title,
      room_id,
      allday_yn,
      start_ymd,
      end_ymd,
      repeat_id,
      repeat_end_ymd,
      repeat_cycle,
      repeat_user,
      sun_yn,
      mon_yn,
      tue_yn,
      wed_yn,
      thu_yn,
      fri_yn,
      sat_yn,
      repeat_condition,
      status,
      approver,
      return_comment,
      create_user,
      repeat_group_id,
      create_at,
      update_at
    ) VALUES (
      (elem->>'reservation_id')::uuid,
      elem->>'title',
      (elem->>'room_id')::uuid,
      COALESCE(elem->>'allday_yn', 'N'),
      (elem->>'start_ymd')::timestamptz,
      (elem->>'end_ymd')::timestamptz,
      NULLIF(elem->>'repeat_id', '')::varchar,
      NULLIF(elem->>'repeat_end_ymd', ''),
      NULLIF(elem->>'repeat_cycle', '')::integer,
      NULLIF(elem->>'repeat_user', ''),
      COALESCE(elem->>'sun_yn', 'N'),
      COALESCE(elem->>'mon_yn', 'N'),
      COALESCE(elem->>'tue_yn', 'N'),
      COALESCE(elem->>'wed_yn', 'N'),
      COALESCE(elem->>'thu_yn', 'N'),
      COALESCE(elem->>'fri_yn', 'N'),
      COALESCE(elem->>'sat_yn', 'N'),
      NULLIF(elem->>'repeat_condition', ''),
      NULLIF(elem->>'status', '')::integer,
      NULLIF(elem->>'approver', ''),
      NULLIF(elem->>'return_comment', ''),
      elem->>'create_user',
      NULLIF(elem->>'repeat_group_id', '')::uuid,
      COALESCE((elem->>'create_at')::timestamptz, now()),
      COALESCE((elem->>'update_at')::timestamptz, now())
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.replace_repeat_group_reservations(UUID, JSONB) IS
  '반복 그룹 전체 삭제 후 p_rows JSON 배열로 재삽입.';

GRANT EXECUTE ON FUNCTION public.replace_repeat_group_reservations(UUID, JSONB) TO anon;
GRANT EXECUTE ON FUNCTION public.replace_repeat_group_reservations(UUID, JSONB) TO authenticated;
