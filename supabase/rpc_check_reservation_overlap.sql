-- 중복 예약 검사 RPC (RLS와 관계없이 전체 예약 조회)
-- Supabase 대시보드 → SQL Editor에서 실행 후, 앱에서 checkOverlap 시 이 RPC를 사용합니다.
-- 같은 회의실(room_id)만 비교, 반려(status=130) 제외, 겹침: (새_시작일 < end_ymd AND 새_종료일 > start_ymd)
-- p_exclude_reservation_id: 수정/드래그 시 자기 자신 제외용 (NULL이면 제외 없음)

CREATE OR REPLACE FUNCTION public.check_reservation_overlap(
  p_room_id UUID,
  p_start_ymd TIMESTAMPTZ,
  p_end_ymd TIMESTAMPTZ,
  p_exclude_reservation_id UUID DEFAULT NULL
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
    AND (p_exclude_reservation_id IS NULL OR mr.reservation_id <> p_exclude_reservation_id)
    AND p_start_ymd < mr.end_ymd
    AND p_end_ymd > mr.start_ymd
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, NULL::TEXT;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.check_reservation_overlap(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID) IS
  '회의실 중복 예약 검사. duplicate_yn=120일 때 사용. 반려(130) 제외. p_exclude_reservation_id로 수정/드래그 시 자기 제외.';

-- RPC 호출 권한 (클라이언트에서 호출 가능하도록)
GRANT EXECUTE ON FUNCTION public.check_reservation_overlap(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.check_reservation_overlap(UUID, TIMESTAMPTZ, TIMESTAMPTZ, UUID) TO authenticated;
