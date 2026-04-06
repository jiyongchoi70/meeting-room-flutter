-- duplicate_yn = 110 인 회의실만 시간 중복 허용. NULL·120·기타는 모두 검사(미설정 시 중복 방지).
-- 클라이언트 검사·레이스 보강용 서버 최종 차단. 반려(130)만 제외 — check_reservation_overlap 과 동일.

CREATE OR REPLACE FUNCTION public.tr_fn_reservation_overlap_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dup integer;
  v_conflict text;
BEGIN
  SELECT mr.duplicate_yn INTO v_dup
  FROM mr_room mr
  WHERE mr.room_id = NEW.room_id;

  -- 110만 명시적 중복 허용(IS NOT DISTINCT FROM 로 NULL 과 구분).
  IF v_dup IS NOT DISTINCT FROM 110 THEN
    RETURN NEW;
  END IF;

  IF NEW.end_ymd <= NEW.start_ymd THEN
    RETURN NEW;
  END IF;

  SELECT
    (EXTRACT(MONTH FROM mr.start_ymd)::int)::text || ' 월 ' ||
    (EXTRACT(DAY FROM mr.start_ymd)::int)::text || ' 일'
  INTO v_conflict
  FROM mr_reservations mr
  WHERE mr.room_id = NEW.room_id
    AND (mr.status IS NULL OR mr.status <> 130)
    AND mr.reservation_id IS DISTINCT FROM NEW.reservation_id
    AND NEW.start_ymd < mr.end_ymd
    AND NEW.end_ymd > mr.start_ymd
  LIMIT 1;

  IF v_conflict IS NOT NULL THEN
    RAISE EXCEPTION '% 중복이 됩니다.', v_conflict;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_reservation_overlap_guard ON public.mr_reservations;

CREATE TRIGGER tr_reservation_overlap_guard
  BEFORE INSERT OR UPDATE OF room_id, start_ymd, end_ymd ON public.mr_reservations
  FOR EACH ROW
  EXECUTE PROCEDURE public.tr_fn_reservation_overlap_guard();

COMMENT ON FUNCTION public.tr_fn_reservation_overlap_guard() IS
  'duplicate_yn이 110이 아닌 회의실: 동일 room_id·시간 겹침 INSERT/UPDATE 차단(반려 130 제외).';
