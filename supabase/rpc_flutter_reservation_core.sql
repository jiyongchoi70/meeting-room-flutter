-- Flutter 연동용 핵심 RPC
-- 목적:
-- 1) "이 일정" 저장(수정) 시 대표행 분리 + 남은 occurrence 재그룹핑
-- 2) "이 일정" 이동(드래그) 시 대표행 분리 + 남은 occurrence 재그룹핑
--
-- 주의:
-- - mr_reservations.repeat_group_id가 varchar/uuid 혼용이어도 동작하도록
--   그룹 비교는 text 기준으로 처리합니다.
-- - p_actor_uid(로그인 사용자)와 create_user가 다르면 예외를 발생시킵니다.

CREATE OR REPLACE FUNCTION public.rpc_split_series_this_occurrence_save(
  p_actor_uid text,
  p_reservation_id uuid,
  p_payload jsonb
)
RETURNS TABLE(ok boolean, message text, reservation_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_id uuid := (p_payload->>'room_id')::uuid;
  v_start_ymd timestamptz := (p_payload->>'start_ymd')::timestamptz;
  v_end_ymd timestamptz := (p_payload->>'end_ymd')::timestamptz;
  v_current_group_id text;
  v_create_user text;
  v_next_rep_id uuid;
  v_conflict text;
  v_duplicate_yn integer;
BEGIN
  IF p_actor_uid IS NULL OR trim(p_actor_uid) = '' THEN
    RAISE EXCEPTION '로그인 사용자 정보가 없습니다.';
  END IF;

  IF v_room_id IS NULL OR v_start_ymd IS NULL OR v_end_ymd IS NULL THEN
    RAISE EXCEPTION '필수값(room_id/start_ymd/end_ymd)이 없습니다.';
  END IF;

  IF v_end_ymd <= v_start_ymd THEN
    RAISE EXCEPTION '종료일시는 시작일시보다 커야 합니다.';
  END IF;

  -- 대상 행 + 소유자 + 현재 그룹 조회
  SELECT
    r.create_user,
    COALESCE(r.repeat_group_id, r.reservation_id::text)
  INTO v_create_user, v_current_group_id
  FROM mr_reservations r
  WHERE r.reservation_id = p_reservation_id;

  IF v_create_user IS NULL THEN
    RAISE EXCEPTION '대상 예약이 없습니다.';
  END IF;

  IF v_create_user <> p_actor_uid THEN
    RAISE EXCEPTION '본인 예약만 수정할 수 있습니다.';
  END IF;

  SELECT mr.duplicate_yn INTO v_duplicate_yn
  FROM mr_room mr
  WHERE mr.room_id = v_room_id;

  -- duplicate_yn = 110 만 중복 허용. 그 외(NULL·120 등)는 검사.
  IF v_duplicate_yn IS DISTINCT FROM 110 THEN
    SELECT
      (EXTRACT(MONTH FROM m.start_ymd)::int)::text || ' 월 ' || (EXTRACT(DAY FROM m.start_ymd)::int)::text || ' 일'
    INTO v_conflict
    FROM mr_reservations m
    WHERE m.room_id = v_room_id
      AND (m.status IS NULL OR m.status <> 130)
      AND m.reservation_id <> p_reservation_id
      AND v_start_ymd < m.end_ymd
      AND v_end_ymd > m.start_ymd
    LIMIT 1;

    IF v_conflict IS NOT NULL THEN
      RAISE EXCEPTION '% 중복이 됩니다.', v_conflict;
    END IF;
  END IF;

  -- 대표행 분리: 대표를 떼면 남은 행들 새 대표로 재그룹핑
  IF v_current_group_id = p_reservation_id::text THEN
    SELECT f.reservation_id
    INTO v_next_rep_id
    FROM mr_reservations f
    WHERE COALESCE(f.repeat_group_id, f.reservation_id::text) = v_current_group_id
      AND f.reservation_id <> p_reservation_id
    ORDER BY f.start_ymd ASC
    LIMIT 1;

    IF v_next_rep_id IS NOT NULL THEN
      UPDATE mr_reservations
      SET repeat_group_id = v_next_rep_id::text
      WHERE COALESCE(repeat_group_id, reservation_id::text) = v_current_group_id
        AND reservation_id <> p_reservation_id;
    END IF;
  END IF;

  -- 대상 행 단건 수정 + 자기 그룹으로 분리
  UPDATE mr_reservations
  SET
    title = COALESCE(NULLIF(p_payload->>'title', ''), title),
    room_id = v_room_id,
    allday_yn = COALESCE(NULLIF(p_payload->>'allday_yn', ''), 'N'),
    start_ymd = v_start_ymd,
    end_ymd = v_end_ymd,
    repeat_id = NULLIF(p_payload->>'repeat_id', ''),
    repeat_end_ymd = NULLIF(p_payload->>'repeat_end_ymd', ''),
    repeat_cycle = NULLIF(p_payload->>'repeat_cycle', '')::int,
    repeat_user = NULLIF(p_payload->>'repeat_user', ''),
    sun_yn = COALESCE(NULLIF(p_payload->>'sun_yn', ''), 'N'),
    mon_yn = COALESCE(NULLIF(p_payload->>'mon_yn', ''), 'N'),
    tue_yn = COALESCE(NULLIF(p_payload->>'tue_yn', ''), 'N'),
    wed_yn = COALESCE(NULLIF(p_payload->>'wed_yn', ''), 'N'),
    thu_yn = COALESCE(NULLIF(p_payload->>'thu_yn', ''), 'N'),
    fri_yn = COALESCE(NULLIF(p_payload->>'fri_yn', ''), 'N'),
    sat_yn = COALESCE(NULLIF(p_payload->>'sat_yn', ''), 'N'),
    repeat_condition = NULLIF(p_payload->>'repeat_condition', ''),
    repeat_group_id = p_reservation_id::text,
    update_at = now()
  WHERE reservation_id = p_reservation_id;

  RETURN QUERY SELECT true, 'saved(this)', p_reservation_id;
END;
$$;

COMMENT ON FUNCTION public.rpc_split_series_this_occurrence_save(text, uuid, jsonb)
IS '이 일정 저장: 대표행 분리 시 follower 그룹 재배정 + 대상 단건 수정. duplicate_yn=110이 아니면 시간 중복 검사.';


CREATE OR REPLACE FUNCTION public.rpc_split_series_this_occurrence_move(
  p_actor_uid text,
  p_reservation_id uuid,
  p_start_ymd timestamptz,
  p_end_ymd timestamptz
)
RETURNS TABLE(ok boolean, message text, reservation_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_id uuid;
  v_current_group_id text;
  v_create_user text;
  v_next_rep_id uuid;
  v_conflict text;
  v_duplicate_yn integer;
BEGIN
  IF p_actor_uid IS NULL OR trim(p_actor_uid) = '' THEN
    RAISE EXCEPTION '로그인 사용자 정보가 없습니다.';
  END IF;

  IF p_start_ymd IS NULL OR p_end_ymd IS NULL OR p_end_ymd <= p_start_ymd THEN
    RAISE EXCEPTION '이동 일시가 올바르지 않습니다.';
  END IF;

  -- 대상 행 + 소유자 + 현재 그룹 조회
  SELECT
    r.room_id,
    r.create_user,
    COALESCE(r.repeat_group_id, r.reservation_id::text)
  INTO v_room_id, v_create_user, v_current_group_id
  FROM mr_reservations r
  WHERE r.reservation_id = p_reservation_id;

  IF v_room_id IS NULL THEN
    RAISE EXCEPTION '대상 예약이 없습니다.';
  END IF;

  IF v_create_user <> p_actor_uid THEN
    RAISE EXCEPTION '본인 예약만 이동할 수 있습니다.';
  END IF;

  SELECT mr.duplicate_yn INTO v_duplicate_yn
  FROM mr_room mr
  WHERE mr.room_id = v_room_id;

  IF v_duplicate_yn IS DISTINCT FROM 110 THEN
    SELECT
      (EXTRACT(MONTH FROM m.start_ymd)::int)::text || ' 월 ' || (EXTRACT(DAY FROM m.start_ymd)::int)::text || ' 일'
    INTO v_conflict
    FROM mr_reservations m
    WHERE m.room_id = v_room_id
      AND (m.status IS NULL OR m.status <> 130)
      AND m.reservation_id <> p_reservation_id
      AND p_start_ymd < m.end_ymd
      AND p_end_ymd > m.start_ymd
    LIMIT 1;

    IF v_conflict IS NOT NULL THEN
      RAISE EXCEPTION '% 중복이 됩니다.', v_conflict;
    END IF;
  END IF;

  -- 대표행 분리: 대표를 떼면 남은 행들 새 대표로 재그룹핑
  IF v_current_group_id = p_reservation_id::text THEN
    SELECT f.reservation_id
    INTO v_next_rep_id
    FROM mr_reservations f
    WHERE COALESCE(f.repeat_group_id, f.reservation_id::text) = v_current_group_id
      AND f.reservation_id <> p_reservation_id
    ORDER BY f.start_ymd ASC
    LIMIT 1;

    IF v_next_rep_id IS NOT NULL THEN
      UPDATE mr_reservations
      SET repeat_group_id = v_next_rep_id::text
      WHERE COALESCE(repeat_group_id, reservation_id::text) = v_current_group_id
        AND reservation_id <> p_reservation_id;
    END IF;
  END IF;

  -- 대상 행 이동 + 자기 그룹으로 분리
  UPDATE mr_reservations
  SET
    start_ymd = p_start_ymd,
    end_ymd = p_end_ymd,
    repeat_group_id = p_reservation_id::text,
    update_at = now()
  WHERE reservation_id = p_reservation_id;

  RETURN QUERY SELECT true, 'moved(this)', p_reservation_id;
END;
$$;

COMMENT ON FUNCTION public.rpc_split_series_this_occurrence_move(text, uuid, timestamptz, timestamptz)
IS '이 일정 이동: 대표행 분리 시 follower 그룹 재배정 + 대상 단건 이동. duplicate_yn=110이 아니면 시간 중복 검사.';


GRANT EXECUTE ON FUNCTION public.rpc_split_series_this_occurrence_save(text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_split_series_this_occurrence_move(text, uuid, timestamptz, timestamptz) TO authenticated;
