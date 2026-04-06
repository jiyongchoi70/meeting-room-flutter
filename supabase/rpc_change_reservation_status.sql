-- 예약 결재 상태 변경 RPC (Web/Flutter 공통)
-- 근거: docs/RESERVATION_RULES.md 상태/권한, docs/RPC_CONTRACT.md §3
-- lookup 180 (앱 코드와 동일): 110=신청, 120=승인, 130=반려, 140=완료
-- 권한: mr_users.user_type = 110(담당자) 이거나 mr_approver에 (actor, room_id) 존재
--
-- 사전 조건: mr_reservations.repeat_group_id 컬럼 존재 (반복 시리즈). 없으면 추가:
--   ALTER TABLE mr_reservations ADD COLUMN IF NOT EXISTS repeat_group_id VARCHAR(100);

CREATE OR REPLACE FUNCTION public.rpc_change_reservation_status(
  p_actor_uid text,
  p_target_reservation_id uuid,
  p_next_status integer,
  p_scope text DEFAULT 'this',
  p_return_comment text DEFAULT NULL
)
RETURNS TABLE(
  ok boolean,
  message text,
  affected_count integer,
  affected_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope text := lower(trim(coalesce(p_scope, 'this')));
  v_room_id uuid;
  v_group_key text;
  v_ids uuid[];
  v_distinct_rooms integer;
  v_actor_ok boolean;
  v_all_valid boolean;
BEGIN
  IF p_actor_uid IS NULL OR trim(p_actor_uid) = '' THEN
    RAISE EXCEPTION '로그인 사용자 정보가 없습니다.';
  END IF;

  IF v_scope NOT IN ('this', 'all') THEN
    RAISE EXCEPTION '[E_INVALID_SCOPE] scope는 this 또는 all 이어야 합니다.';
  END IF;

  IF p_next_status NOT IN (120, 130, 140) THEN
    RAISE EXCEPTION '[E_INVALID_STATE] next_status는 120(승인), 130(반려), 140(완료)만 허용됩니다.';
  END IF;

  SELECT
    r.room_id,
    COALESCE(NULLIF(trim(r.repeat_group_id::text), ''), r.reservation_id::text)
  INTO v_room_id, v_group_key
  FROM mr_reservations r
  WHERE r.reservation_id = p_target_reservation_id;

  IF v_room_id IS NULL THEN
    RAISE EXCEPTION '[E_NOT_FOUND] 대상 예약이 없습니다.';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM mr_users u
    WHERE u.user_uid = p_actor_uid AND u.user_type = 110
  )
  OR EXISTS (
    SELECT 1 FROM mr_approver a
    WHERE a.user_uid = p_actor_uid AND a.room_id = v_room_id
  )
  INTO v_actor_ok;

  IF NOT v_actor_ok THEN
    RAISE EXCEPTION '[E_NOT_APPROVER] 해당 회의실에 대한 승인 권한이 없습니다.';
  END IF;

  IF v_scope = 'this' THEN
    v_ids := ARRAY[p_target_reservation_id];
  ELSE
    SELECT coalesce(array_agg(r.reservation_id ORDER BY r.start_ymd), ARRAY[]::uuid[])
    INTO v_ids
    FROM mr_reservations r
    WHERE COALESCE(NULLIF(trim(r.repeat_group_id::text), ''), r.reservation_id::text) = v_group_key;
  END IF;

  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RAISE EXCEPTION '[E_NOT_FOUND] 갱신할 예약이 없습니다.';
  END IF;

  SELECT count(DISTINCT r.room_id)::integer
  INTO v_distinct_rooms
  FROM mr_reservations r
  WHERE r.reservation_id = ANY(v_ids);

  IF v_distinct_rooms <> 1 THEN
    RAISE EXCEPTION '[E_INVALID_STATE] 동일 시리즈에 서로 다른 회의실이 섞여 있어 처리할 수 없습니다.';
  END IF;

  SELECT bool_and(
    (p_next_status = 120 AND r.status = 110)
    OR (p_next_status = 130 AND r.status = 110)
    OR (p_next_status = 140 AND r.status = 120)
  )
  INTO v_all_valid
  FROM mr_reservations r
  WHERE r.reservation_id = ANY(v_ids);

  IF v_all_valid IS DISTINCT FROM true THEN
    RAISE EXCEPTION '[E_INVALID_STATE] 상태 전이가 허용되지 않습니다. 신청(110)→승인(120)/반려(130), 승인(120)→완료(140)만 가능합니다.';
  END IF;

  UPDATE mr_reservations r
  SET
    status = p_next_status,
    update_at = now(),
    approver = p_actor_uid,
    return_comment = CASE
      WHEN p_next_status = 130 THEN p_return_comment
      WHEN p_next_status = 120 THEN NULL
      WHEN p_next_status = 140 THEN NULL
      ELSE r.return_comment
    END
  WHERE r.reservation_id = ANY(v_ids);

  RETURN QUERY
  SELECT
    true,
    'updated'::text,
    cardinality(v_ids),
    v_ids;
END;
$$;

COMMENT ON FUNCTION public.rpc_change_reservation_status(text, uuid, integer, text, text) IS
  '결재 상태 변경(단일 앵커 + this|all 시리즈). 담당자( user_type 110 ) 또는 mr_approver 권한 검증.';


CREATE OR REPLACE FUNCTION public.rpc_change_reservation_status_many(
  p_actor_uid text,
  p_reservation_ids uuid[],
  p_next_status integer,
  p_return_comment text DEFAULT NULL
)
RETURNS TABLE(
  ok boolean,
  message text,
  affected_count integer,
  affected_ids uuid[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_room_id uuid;
  v_status integer;
  v_actor_ok boolean;
  v_processed uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_actor_uid IS NULL OR trim(p_actor_uid) = '' THEN
    RAISE EXCEPTION '로그인 사용자 정보가 없습니다.';
  END IF;

  IF p_reservation_ids IS NULL OR cardinality(p_reservation_ids) = 0 THEN
    RETURN QUERY SELECT true, 'no-op'::text, 0, ARRAY[]::uuid[];
    RETURN;
  END IF;

  IF p_next_status NOT IN (120, 130, 140) THEN
    RAISE EXCEPTION '[E_INVALID_STATE] next_status는 120(승인), 130(반려), 140(완료)만 허용됩니다.';
  END IF;

  FOR v_id IN SELECT DISTINCT unnest(p_reservation_ids)
  LOOP
    SELECT r.room_id, r.status
    INTO v_room_id, v_status
    FROM mr_reservations r
    WHERE r.reservation_id = v_id;

    IF v_room_id IS NULL THEN
      RAISE EXCEPTION '[E_NOT_FOUND] 예약을 찾을 수 없습니다: %', v_id;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM mr_users u
      WHERE u.user_uid = p_actor_uid AND u.user_type = 110
    )
    OR EXISTS (
      SELECT 1 FROM mr_approver a
      WHERE a.user_uid = p_actor_uid AND a.room_id = v_room_id
    )
    INTO v_actor_ok;

    IF NOT v_actor_ok THEN
      RAISE EXCEPTION '[E_NOT_APPROVER] 예약 %에 대한 승인 권한이 없습니다.', v_id;
    END IF;

    IF NOT (
      (p_next_status = 120 AND v_status = 110)
      OR (p_next_status = 130 AND v_status = 110)
      OR (p_next_status = 140 AND v_status = 120)
    ) THEN
      RAISE EXCEPTION '[E_INVALID_STATE] 예약 %의 현재 상태에서 요청한 변경을 할 수 없습니다.', v_id;
    END IF;

    UPDATE mr_reservations r
    SET
      status = p_next_status,
      update_at = now(),
      approver = p_actor_uid,
      return_comment = CASE
        WHEN p_next_status = 130 THEN p_return_comment
        WHEN p_next_status = 120 THEN NULL
        WHEN p_next_status = 140 THEN NULL
        ELSE r.return_comment
      END
    WHERE r.reservation_id = v_id;

    v_processed := array_append(v_processed, v_id);
  END LOOP;

  RETURN QUERY
  SELECT
    true,
    'updated'::text,
    cardinality(v_processed),
    v_processed;
END;
$$;

COMMENT ON FUNCTION public.rpc_change_reservation_status_many(text, uuid[], integer, text) IS
  '선택된 예약 ID 각각에 대해 결재 상태 변경(시리즈 자동 확장 없음). 그리드 일괄 승인/반려 등.';

GRANT EXECUTE ON FUNCTION public.rpc_change_reservation_status(text, uuid, integer, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_change_reservation_status_many(text, uuid[], integer, text) TO authenticated;
