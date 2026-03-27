// @ts-nocheck
// 임시: Flutter 전환 중 레거시 TS 참조 파일의 타입 오류 무시
import { supabase } from '../lib/supabase'
import type { LookupValue, MrReservation, MrRoom, MrUser, ReservationRow } from '../types'
import { fetchApproversByRoomIds, fetchRooms } from './rooms'
import { fetchLookupValuesByTypeCd } from './lookup'
import { fetchMrUserByUid, formatPhone } from './users'

const LOOKUP_APPROVAL_STATUS = 180
const LOOKUP_POSITION = 130
const STATUS_APPLIED = 110
const STATUS_APPROVED = 120
const STATUS_REJECTED = 130
const STATUS_COMPLETED = 140
/** mr_room.confirm_yn 값: 110=승인필요(예약 시 status 110), 120=승인불필요(예약 시 status 140) */
const CONFIRM_YN_AUTO_COMPLETE = 120
/** mr_room.duplicate_yn: 110=중복 검증 없음, 120=중복 시 저장 불가 */
const DUPLICATE_YN_CHECK = 120
/** repeat_id (lookup 160): 120=매일, 130=매주, 140=매월, 150=사용자설정 */
const REPEAT_DAILY = 120
const REPEAT_WEEKLY = 130
const REPEAT_MONTHLY = 140
const REPEAT_CUSTOM = 150
/** repeat_user (lookup 170): 110=주, 120=개월 */
const REPEAT_USER_WEEK = 110
const REPEAT_USER_MONTH = 120

export interface ReservationListFilters {
  startDate: string
  endDate: string
  roomId: string | null
  applicant: string
  status: number | null
}

/** timestamptz → YYYY-MM-DD HH:MI (로컬) */
function formatDateTime(iso: string): string {
  const d = new Date(iso)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  const h = d.getHours()
  const min = String(d.getMinutes()).padStart(2, '0')
  const ampm = h < 12 ? 'AM' : 'PM'
  const hour = h % 12 || 12
  return `${y}-${m}-${day} ${ampm} ${hour.toString().padStart(2, '0')}:${min}`
}

/** 예약 목록 조회 (필터·권한 반영). 관리자: 전체 회의실, 승인자: mr_approver 기준 회의실만 */
export async function fetchReservationList(
  filters: ReservationListFilters,
  isAdmin: boolean,
  currentUserUid: string
): Promise<ReservationRow[]> {
  const YYYYMMDD = /^\d{4}-\d{2}-\d{2}$/
  const rawStart = (filters.startDate ?? '').trim()
  const rawEnd = (filters.endDate ?? '').trim()
  const defaultStartYmd = (): string => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }
  const defaultEndYmd = (): string => {
    const d = new Date()
    d.setMonth(d.getMonth() + 3)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }
  const startDate = YYYYMMDD.test(rawStart) ? rawStart : defaultStartYmd()
  const endDate = YYYYMMDD.test(rawEnd) ? rawEnd : defaultEndYmd()

  // 타임존 보정: 한국 등에서 "시작일" 당일 00:00은 UTC로 전날이므로, 조회 구간을 하루 앞으로 넓힌 뒤 결과를 날짜로 필터링
  const endDayUtc = endDate + 'T23:59:59.999Z'
  const prevDay = (() => {
    const d = new Date(startDate + 'T12:00:00.000Z')
    d.setUTCDate(d.getUTCDate() - 1)
    return d.toISOString().slice(0, 10)
  })()

  let query = supabase
    .from('mr_reservations')
    .select('*')
    .order('start_ymd', { ascending: false })

  const queryStart = prevDay + 'T00:00:00.000Z'
  query = query.gte('start_ymd', queryStart).lte('start_ymd', endDayUtc)

  if (filters.roomId != null && filters.roomId !== '') {
    query = query.eq('room_id', filters.roomId)
  }
  if (filters.status != null && filters.status !== undefined) {
    query = query.eq('status', filters.status)
  }

  if (!isAdmin) {
    const approvers = await supabase
      .from('mr_approver')
      .select('room_id')
      .eq('user_uid', currentUserUid)
    const roomIds = (approvers.data ?? []).map((r: { room_id: string }) => r.room_id)
    if (roomIds.length === 0) return []
    query = query.in('room_id', roomIds)
  }

  if (filters.applicant.trim()) {
    const { data: users } = await supabase
      .from('mr_users')
      .select('user_uid')
      .ilike('user_name', `%${filters.applicant.trim()}%`)
    const uids = (users ?? []).map((u: { user_uid: string }) => u.user_uid)
    if (uids.length === 0) return []
    query = query.in('create_user', uids)
  }

  const { data: rows, error } = await query
  if (error) {
    console.error('[fetchReservationList]', error.message)
    throw new Error(error.message || '예약 목록 조회 실패')
  }
  const rawList = (rows ?? []) as MrReservation[]
  // 타임존 보정: 조회 구간을 넓혀 가져온 뒤, 시작일/종료일은 "로컬 날짜" 기준으로 다시 필터
  const toLocalYmd = (iso: string) => {
    const d = new Date(iso)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }
  const list = rawList.filter((r) => {
    const ymd = toLocalYmd(r.start_ymd)
    return ymd >= startDate && ymd <= endDate
  })

  const roomIds = [...new Set(list.map((r) => r.room_id))]
  const { data: roomsData } = await supabase
    .from('mr_room')
    .select('room_id, room_nm, seq')
    .in('room_id', roomIds)
  const rooms = (roomsData ?? []) as (MrRoom & { seq?: number | null })[]
  const roomMap = new Map(rooms.map((r) => [r.room_id, r]))

  const userUids = new Set<string>()
  list.forEach((r) => {
    if (r.create_user) userUids.add(r.create_user)
    if (r.approver) userUids.add(r.approver)
  })
  const uids = Array.from(userUids)
  let users: MrUser[] = []
  if (uids.length > 0) {
    const { data: usersData } = await supabase
      .from('mr_users')
      .select('*')
      .in('user_uid', uids)
    users = (usersData ?? []) as MrUser[]
  }
  const userMap = new Map(users.map((u) => [u.user_uid, u]))

  /** 결재상태(lookup_type_cd=180) 조회 */
  const today = new Date().toISOString().slice(0, 10)
  const [statusOptions, positionOptions] = await Promise.all([
    fetchLookupValuesByTypeCd(LOOKUP_APPROVAL_STATUS, { validAt: today }),
    fetchLookupValuesByTypeCd(LOOKUP_POSITION, { validAt: today }),
  ])
  const getLookupName = (
    options: LookupValue[],
    valueCd: number | null,
    dateYmd: string | null
  ): string => {
    if (valueCd == null) return ''
    const ymd = (dateYmd ?? '').replace(/\D/g, '')
    const numCode = Number(valueCd)
    if (Number.isNaN(numCode)) return ''
    const v = options.find((o) => Number(o.lookup_value_cd) === numCode)
    if (!v) return ''
    if (ymd && v.start_ymd && String(v.start_ymd).replace(/-/g, '') > ymd) return ''
    if (ymd && v.end_ymd && String(v.end_ymd).replace(/-/g, '') < ymd) return ''
    return v.lookup_value_nm ?? ''
  }

  const result: ReservationRow[] = list.map((r) => {
    const room = roomMap.get(r.room_id)
    const applicant = userMap.get(r.create_user)
    const approverUser = r.approver ? userMap.get(r.approver) : null
    const selectable =
      r.status === STATUS_APPLIED && (r.repeat_cycle == null || r.repeat_cycle === undefined)
    const applicantYmd = applicant?.create_ymd
      ? String(applicant.create_ymd).replace(/\D/g, '').slice(0, 8)
      : null
    const applicantPositionNm =
      applicant != null
        ? getLookupName(
            positionOptions,
            applicant.user_position ?? null,
            applicantYmd ? `${applicantYmd.slice(0, 4)}-${applicantYmd.slice(4, 6)}-${applicantYmd.slice(6, 8)}` : null
          )
        : ''
    const applicantPhone = applicant ? formatPhone(applicant.phone) : ''
    return {
      reservation_id: r.reservation_id,
      title: r.title,
      room_id: r.room_id,
      room_nm: room?.room_nm ?? '',
      allday_yn: r.allday_yn ?? 'N',
      start_ymd: r.start_ymd,
      end_ymd: r.end_ymd,
      start_date_time: formatDateTime(r.start_ymd),
      end_date_time: formatDateTime(r.end_ymd),
      applicant_name: applicant?.user_name ?? '',
      applicant_position_nm: applicantPositionNm,
      applicant_phone: applicantPhone,
      approver_name: approverUser?.user_name ?? '',
      create_user: r.create_user,
      repeat_yn: r.repeat_group_id != null && String(r.repeat_group_id).trim() !== '' ? 'Y' : 'N',
      repeat_group_id: r.repeat_group_id ?? null,
      status: r.status ?? null,
      status_nm: getLookupName(
        statusOptions,
        r.status ?? null,
        r.start_ymd ? String(r.start_ymd).slice(0, 10) : null
      ),
      return_comment: r.return_comment ?? null,
      repeat_id:
        r.repeat_id != null && String(r.repeat_id).trim() !== ''
          ? Number(r.repeat_id)
          : null,
      repeat_end_ymd: r.repeat_end_ymd ?? null,
      repeat_cycle:
        r.repeat_cycle != null && String(r.repeat_cycle).trim() !== ''
          ? Number(r.repeat_cycle)
          : null,
      repeat_user:
        r.repeat_user != null && String(r.repeat_user).trim() !== ''
          ? Number(r.repeat_user)
          : null,
      sun_yn: r.sun_yn ?? null,
      mon_yn: r.mon_yn ?? null,
      tue_yn: r.tue_yn ?? null,
      wed_yn: r.wed_yn ?? null,
      thu_yn: r.thu_yn ?? null,
      fri_yn: r.fri_yn ?? null,
      sat_yn: r.sat_yn ?? null,
      repeat_condition: r.repeat_condition ?? null,
      selectable,
    }
  })

  result.sort((a, b) => {
    const ra = list.find((r) => r.reservation_id === a.reservation_id)!
    const rb = list.find((r) => r.reservation_id === b.reservation_id)!
    // 1차: repeat_group_id ASC (null/빈값은 뒤로)
    const ga = String(ra.repeat_group_id ?? '')
    const gb = String(rb.repeat_group_id ?? '')
    if (ga !== gb) return ga < gb ? -1 : 1
    // 2차: start_ymd DESC
    if (ra.start_ymd !== rb.start_ymd) return ra.start_ymd > rb.start_ymd ? -1 : 1
    // 3차: mr_room.seq ASC
    const aSeq = roomMap.get(ra.room_id)?.seq ?? 0
    const bSeq = roomMap.get(rb.room_id)?.seq ?? 0
    return aSeq - bSeq
  })
  return result
}

/** 캘린더용 예약 목록 (드래그 시 DB 반영·이동 권한 확인·예약자 표시를 위해 id/reservationId/createUser/bookerInfo 포함). roomId 있으면 해당 회의실만 조회.
 *  join=110(예약 가능) 사용자도 캘린더에서는 전체 회의실 예약 현황을 조회할 수 있도록 제한하지 않음. (예약 목록/승인은 fetchReservationList에서 mr_approver 기준 유지) */
export async function fetchReservationsForCalendar(
  startDate: string,
  endDate: string,
  _isAdmin: boolean,
  _currentUserUid: string,
  roomId?: string | null
): Promise<
  Array<{
    id: string
    title: string
    start: string
    end: string
    roomId: string
    roomName: string
    extendedProps?: {
      isAllDay?: boolean
      reservationId: string
      createUser?: string
      status?: number
      /** 예약자 표시용 (모달에서 바로 사용) */
      bookerName?: string
      bookerPositionName?: string
      bookerPhone?: string
    }
  }>
> {
  const YYYYMMDD = /^\d{4}-\d{2}-\d{2}$/
  const rawStart = (startDate ?? '').trim()
  const rawEnd = (endDate ?? '').trim()
  const defaultStart = (): string => {
    const d = new Date()
    d.setMonth(d.getMonth() - 1)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }
  const defaultEnd = (): string => {
    const d = new Date()
    d.setMonth(d.getMonth() + 3)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }
  const start = YYYYMMDD.test(rawStart) ? rawStart : defaultStart()
  const end = YYYYMMDD.test(rawEnd) ? rawEnd : defaultEnd()
  const startDay = start + 'T00:00:00.000Z'
  const endDay = end + 'T23:59:59.999Z'

  let query = supabase
    .from('mr_reservations')
    .select(
      'reservation_id, title, start_ymd, end_ymd, room_id, allday_yn, create_user, status, repeat_id, repeat_end_ymd, repeat_group_id, repeat_user, sun_yn, mon_yn, tue_yn, wed_yn, thu_yn, fri_yn, sat_yn, return_comment'
    )
    .gte('start_ymd', startDay)
    .lte('start_ymd', endDay)
    .order('start_ymd', { ascending: true })

  if (roomId != null && roomId !== '') {
    query = query.eq('room_id', roomId)
  }

  const { data: rows, error } = await query
  if (error) {
    console.error('[fetchReservationsForCalendar]', error.message)
    throw new Error(error.message || '캘린더 예약 조회 실패')
  }
  const list = (rows ?? []) as Array<{
    reservation_id: string
    title: string
    start_ymd: string
    end_ymd: string
    room_id: string
    allday_yn: string | null
    create_user: string | null
    status: number | null
    repeat_id: number | null
    repeat_end_ymd: string | null
    repeat_group_id?: string | null
    repeat_user?: string | null
    sun_yn?: string | null
    mon_yn?: string | null
    tue_yn?: string | null
    wed_yn?: string | null
    thu_yn?: string | null
    fri_yn?: string | null
    sat_yn?: string | null
    return_comment?: string | null
  }>
  const roomIds = [...new Set(list.map((r) => r.room_id))]
  const { data: roomsData } = await supabase
    .from('mr_room')
    .select('room_id, room_nm')
    .in('room_id', roomIds)
  const rooms = (roomsData ?? []) as Array<{ room_id: string; room_nm: string }>
  const roomMap = new Map(rooms.map((r) => [r.room_id, r]))

  // 예약자 정보 (mr_users) + 직분(lookup 130) 미리 조회해서 캘린더 이벤트에 포함
  const userUids = [...new Set(list.map((r) => r.create_user).filter((v): v is string => !!v))]
  let users: MrUser[] = []
  if (userUids.length > 0) {
    const { data: usersData } = await supabase
      .from('mr_users')
      .select('*')
      .in('user_uid', userUids)
    users = (usersData ?? []) as MrUser[]
  }
  const userMap = new Map(users.map((u) => [u.user_uid, u]))
  const positionOptions = await fetchLookupValuesByTypeCd(LOOKUP_POSITION)
  const getPositionName = (
    options: LookupValue[],
    valueCd: number | null,
    dateYmd: string | null
  ): string => {
    if (valueCd == null) return ''
    const ymd = (dateYmd ?? '').replace(/\D/g, '')
    const numCode = Number(valueCd)
    if (Number.isNaN(numCode)) return ''
    const v = options.find((o) => Number(o.lookup_value_cd) === numCode)
    if (!v) return ''
    if (ymd && v.start_ymd && String(v.start_ymd).replace(/-/g, '') > ymd) return ''
    if (ymd && v.end_ymd && String(v.end_ymd).replace(/-/g, '') < ymd) return ''
    return v.lookup_value_nm ?? ''
  }

  /** 월 보기에서 같은 날 여러 예약 구분용 색상 (파란점만 있으면 가독성 저하 → 예약별 색 할당) */
  const EVENT_COLORS = [
    '#2563eb', /* blue */
    '#059669', /* emerald */
    '#7c3aed', /* violet */
    '#dc2626', /* red */
    '#ea580c', /* orange */
    '#0891b2', /* cyan */
    '#4f46e5', /* indigo */
    '#ca8a04', /* yellow/amber */
  ]
  const hashId = (id: string) => {
    let h = 0
    for (let i = 0; i < id.length; i++) h = ((h << 5) - h + id.charCodeAt(i)) | 0
    return Math.abs(h)
  }

  /** 종일 예약: FullCalendar는 end를 제외(exclusive)로 씀 → 시작일~종료일(포함) 표시를 위해 end를 종료일+1일로 */
  const toCalendarEnd = (start_ymd: string, end_ymd: string, isAllDay: boolean): string => {
    if (!isAllDay) return end_ymd
    const startStr = start_ymd.slice(0, 10)
    const endStr = end_ymd.slice(0, 10)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startStr) || !/^\d{4}-\d{2}-\d{2}$/.test(endStr)) return end_ymd
    const endDate = new Date(endStr + 'T12:00:00.000Z')
    endDate.setUTCDate(endDate.getUTCDate() + 1)
    const next = endDate.toISOString().slice(0, 10)
    return end_ymd.replace(/^\d{4}-\d{2}-\d{2}/, next)
  }
  const repeatCountMap = new Map<string, number>()
  for (const r of list) {
    const key = String(r.repeat_group_id ?? r.reservation_id)
    repeatCountMap.set(key, (repeatCountMap.get(key) ?? 0) + 1)
  }

  return list.map((r) => {
    const isAllDay = r.allday_yn === 'Y'
    const calendarEnd = toCalendarEnd(r.start_ymd, r.end_ymd, isAllDay)
    const selectedDaysForModal: boolean[] | undefined =
      r.repeat_id != null && Number(r.repeat_id) === REPEAT_CUSTOM
        ? [
            r.sun_yn === 'Y',
            r.mon_yn === 'Y',
            r.tue_yn === 'Y',
            r.wed_yn === 'Y',
            r.thu_yn === 'Y',
            r.fri_yn === 'Y',
            r.sat_yn === 'Y',
          ]
        : undefined
    const hasCustomDay = selectedDaysForModal?.some(Boolean)
    return {
    id: r.reservation_id,
    title: r.title,
    start: r.start_ymd,
    end: calendarEnd,
    roomId: r.room_id,
    roomName: roomMap.get(r.room_id)?.room_nm ?? '',
    extendedProps: {
      isAllDay: r.allday_yn === 'Y',
      reservationId: r.reservation_id,
      createUser: r.create_user ?? undefined,
      status: r.status ?? undefined,
      repeatGroupId: r.repeat_group_id ?? undefined,
      repeatCount: repeatCountMap.get(String(r.repeat_group_id ?? r.reservation_id)) ?? 1,
      startYmd: r.start_ymd != null ? String(r.start_ymd).slice(0, 10) : undefined,
      color: EVENT_COLORS[hashId(r.repeat_group_id ?? r.reservation_id) % EVENT_COLORS.length],
      recurrenceCd: r.repeat_id != null ? Number(r.repeat_id) : undefined,
      recurrenceEndYmd: r.repeat_end_ymd != null && String(r.repeat_end_ymd).trim() !== '' ? String(r.repeat_end_ymd).trim() : undefined,
      repeatUser:
        r.repeat_user != null && String(r.repeat_user).trim() !== ''
          ? Number(r.repeat_user)
          : undefined,
      selectedDays: hasCustomDay ? selectedDaysForModal : undefined,
      returnComment: r.status === STATUS_REJECTED ? r.return_comment ?? null : undefined,
      ...(r.create_user
        ? (() => {
            const user = userMap.get(r.create_user!)
            if (!user) return {}
            const bookerName = user.user_name ?? ''
            const bookerPositionName = getPositionName(
              positionOptions,
              user.user_position ?? null,
              user.create_ymd
            )
            const bookerPhone = formatPhone(user.phone)
            return {
              bookerName,
              bookerPositionName,
              bookerPhone,
            }
          })()
        : {}),
    },
  }
  })
}

/** user_uid로 예약자 표시용 이름·직분·연락처 조회 (저장 직후 로컬 이벤트에 넣어 모달에서 즉시 표시) */
export async function fetchBookerInfoByUserUid(userUid: string): Promise<{
  bookerName: string
  bookerPositionName: string
  bookerPhone: string
}> {
  const { data: row } = await supabase
    .from('mr_users')
    .select('*')
    .eq('user_uid', userUid)
    .maybeSingle()
  if (!row) return { bookerName: '', bookerPositionName: '', bookerPhone: '' }
  const user = row as MrUser
  const ymdDigits = (user.create_ymd ?? '').replace(/\D/g, '')
  const validAt =
    ymdDigits.length >= 8
      ? `${ymdDigits.slice(0, 4)}-${ymdDigits.slice(4, 6)}-${ymdDigits.slice(6, 8)}`
      : new Date().toISOString().slice(0, 10)
  const positionOptions = await fetchLookupValuesByTypeCd(LOOKUP_POSITION, { validAt })
  const getPositionName = (
    options: LookupValue[],
    valueCd: number | null,
    dateYmd: string | null
  ): string => {
    if (valueCd == null) return ''
    const ymd = (dateYmd ?? '').replace(/\D/g, '')
    const numCode = Number(valueCd)
    if (Number.isNaN(numCode)) return ''
    const v = options.find((o) => Number(o.lookup_value_cd) === numCode)
    if (!v) return ''
    if (ymd && v.start_ymd && String(v.start_ymd).replace(/-/g, '') > ymd) return ''
    if (ymd && v.end_ymd && String(v.end_ymd).replace(/-/g, '') < ymd) return ''
    return v.lookup_value_nm ?? ''
  }
  return {
    bookerName: user.user_name ?? '',
    bookerPositionName: getPositionName(positionOptions, user.user_position ?? null, user.create_ymd),
    bookerPhone: formatPhone(user.phone),
  }
}

/** 예약현황 회의실명 드롭다운: 관리자=전체 mr_room, 승인자=권한 회의실만 */
export async function fetchRoomOptionsForReservationStatus(
  isAdmin: boolean,
  currentUserUid: string
): Promise<{ room_id: string; room_nm: string }[]> {
  if (isAdmin) {
    const rooms = await fetchRooms()
    return rooms.map((r) => ({ room_id: r.room_id, room_nm: r.room_nm }))
  }
  const { data, error } = await supabase
    .from('mr_approver')
    .select('room_id')
    .eq('user_uid', currentUserUid)
  if (error) return []
  const roomIds = (data ?? []).map((r: { room_id: string }) => r.room_id)
  if (roomIds.length === 0) return []
  const { data: roomsData } = await supabase
    .from('mr_room')
    .select('room_id, room_nm')
    .in('room_id', roomIds)
    .order('seq', { ascending: true, nullsFirst: true })
  return (roomsData ?? []) as { room_id: string; room_nm: string }[]
}

/** 결재상태 드롭다운 (lookup 180) */
export async function fetchApprovalStatusOptions(): Promise<LookupValue[]> {
  return fetchLookupValuesByTypeCd(LOOKUP_APPROVAL_STATUS, {
    validAt: new Date().toISOString().slice(0, 10),
  })
}

/** 일괄 승인(120) 또는 반려(130). 정상 처리 시 approver에 로그인 user_uid 저장. 반려(130) 시 return_comment 저장. */
export async function batchUpdateReservationStatus(
  reservationIds: string[],
  status: number,
  approverUserUid: string,
  returnComment?: string | null
): Promise<void> {
  if (reservationIds.length === 0) return
  const payload: { status: number; update_at: string; approver: string; return_comment?: string | null } = {
    status,
    update_at: new Date().toISOString(),
    approver: approverUserUid,
  }
  if (status === STATUS_REJECTED && returnComment !== undefined) {
    payload.return_comment = returnComment ?? null
  }
  const { error } = await supabase
    .from('mr_reservations')
    .update(payload)
    .in('reservation_id', reservationIds)
  if (error) throw new Error(error.message || '상태 변경 실패')
}

/** 승인/반려 시 갱신할 reservation_id 목록. repeat_group_id 있으면 동일 그룹 전체, 없으면 해당 1건. */
export async function fetchReservationIdsForStatusUpdate(
  reservationId: string,
  repeatGroupId?: string | null
): Promise<string[]> {
  if (repeatGroupId && String(repeatGroupId).trim() !== '') {
    const { data, error } = await supabase
      .from('mr_reservations')
      .select('reservation_id')
      .eq('repeat_group_id', repeatGroupId)
    if (error) throw new Error(error.message || '예약 조회 실패')
    return (data ?? []).map((r: { reservation_id: string }) => r.reservation_id)
  }
  return [reservationId]
}

export { STATUS_APPLIED, STATUS_APPROVED, STATUS_REJECTED }

/** mr_users.user_type: 110 = 담당자(관리자). 담당자/승인자면 status 140, 그 외는 회의실 confirm_yn 기준 */
const USER_TYPE_MANAGER = 110

/** room_id로 mr_room.confirm_yn 조회 후 저장할 status 반환 (110 → 110, 120 → 140, 그 외 → 110) */
async function getStatusByRoomConfirmYn(roomId: string): Promise<number> {
  const { data } = await supabase
    .from('mr_room')
    .select('confirm_yn')
    .eq('room_id', roomId)
    .maybeSingle()
  const confirmYn = (data as { confirm_yn: number | null } | null)?.confirm_yn ?? null
  return confirmYn === CONFIRM_YN_AUTO_COMPLETE ? STATUS_COMPLETED : STATUS_APPLIED
}

/** 예약자( userUid ) 기준 저장할 status: 담당자(110) 또는 해당 회의실 승인자 → 140, 그 외 → getStatusByRoomConfirmYn */
async function getStatusForReserver(roomId: string, userUid: string): Promise<number> {
  const mrUser = await fetchMrUserByUid(userUid)
  if (mrUser?.user_type === USER_TYPE_MANAGER) return STATUS_COMPLETED
  const approvers = await fetchApproversByRoomIds([roomId])
  if (approvers.some((a) => a.user_uid === userUid)) return STATUS_COMPLETED
  return getStatusByRoomConfirmYn(roomId)
}

/** room_id로 mr_room의 confirm_yn, duplicate_yn 조회 */
async function getRoomConfirmAndDuplicate(roomId: string): Promise<{
  confirm_yn: number | null
  duplicate_yn: number | null
}> {
  const { data } = await supabase
    .from('mr_room')
    .select('confirm_yn, duplicate_yn')
    .eq('room_id', roomId)
    .maybeSingle()
  const row = data as { confirm_yn: number | null; duplicate_yn: number | null } | null
  return {
    confirm_yn: row?.confirm_yn ?? null,
    duplicate_yn: row?.duplicate_yn ?? null,
  }
}

/** 반복 종료일 문자열을 YYYY-MM-DD로 정규화. YYYYMMDD(8자리) 또는 YYYY-MM-DD 지원 */
function parseRepeatEndYmd(repeat_end_ymd: string): string {
  const s = repeat_end_ymd.trim().replace(/-/g, '').slice(0, 8)
  if (/^\d{8}$/.test(s)) {
    return `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`
  }
  const withHyphen = repeat_end_ymd.trim().slice(0, 10)
  return /^\d{4}-\d{2}-\d{2}$/.test(withHyphen) ? withHyphen : repeat_end_ymd
}

/** 반복 구간 목록 생성. 매월(140)은 해당 월에 일(day)이 없으면 그 달 건너뜀. 종료일(YYYY-MM-DD) 당일까지 포함, 그 다음 날은 제외. */
function getRepeatDateRanges(
  start_ymd: string,
  end_ymd: string,
  repeat_id: number,
  repeat_end_ymd: string
): Array<{ start_ymd: string; end_ymd: string }> {
  const endDateStr = parseRepeatEndYmd(repeat_end_ymd)
  const ranges: Array<{ start_ymd: string; end_ymd: string }> = []
  let start = new Date(start_ymd)
  let end = new Date(end_ymd)
  const durationMs = end.getTime() - start.getTime()

  const toYmd = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  const startTimeSuffix = start_ymd.includes('T') ? start_ymd.slice(10) : 'T00:00:00.000Z'
  const endTimeSuffix = end_ymd.includes('T') ? end_ymd.slice(10) : 'T00:00:00.000Z'
  const toIsoStart = (d: Date) => toYmd(d) + startTimeSuffix
  const toIsoEnd = (d: Date) => toYmd(d) + endTimeSuffix

  const addOneDay = (d: Date) => {
    d.setDate(d.getDate() + 1)
  }
  const addOneWeek = (d: Date) => {
    d.setDate(d.getDate() + 7)
  }
  const addOneMonth = (d: Date) => {
    d.setMonth(d.getMonth() + 1)
  }

  if (repeat_id === REPEAT_DAILY) {
    while (toYmd(start) <= endDateStr) {
      const e = new Date(start.getTime() + durationMs)
      ranges.push({ start_ymd: toIsoStart(start), end_ymd: toIsoEnd(e) })
      addOneDay(start)
      addOneDay(end)
    }
  } else if (repeat_id === REPEAT_WEEKLY) {
    while (toYmd(start) <= endDateStr) {
      const e = new Date(start.getTime() + durationMs)
      ranges.push({ start_ymd: toIsoStart(start), end_ymd: toIsoEnd(e) })
      addOneWeek(start)
      addOneWeek(end)
    }
  } else if (repeat_id === REPEAT_MONTHLY) {
    const dayOfMonth = new Date(start_ymd).getDate()
    while (toYmd(start) <= endDateStr) {
      const daysInMonth = new Date(start.getFullYear(), start.getMonth() + 1, 0).getDate()
      if (dayOfMonth <= daysInMonth) {
        const e = new Date(start.getTime() + durationMs)
        ranges.push({ start_ymd: toIsoStart(start), end_ymd: toIsoEnd(e) })
      }
      addOneMonth(start)
      start.setDate(Math.min(dayOfMonth, new Date(start.getFullYear(), start.getMonth() + 1, 0).getDate()))
      end = new Date(start.getTime() + durationMs)
    }
  }
  return ranges
}

/** 해당 날짜가 속한 주의 일요일 00:00 (로컬 기준, 한 주 시작) */
function getSundayOfWeek(d: Date): Date {
  const copy = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  const diff = -copy.getDay()
  copy.setDate(copy.getDate() + diff)
  return copy
}

/** 요일 Y/N 플래그 [일,월,화,수,목,금,토] → 해당 요일(0=일..6=토) 인덱스에 대응 */
function getWeekdayFlags(payload: SaveReservationPayload): boolean[] {
  return [
    payload.sun_yn === 'Y',
    payload.mon_yn === 'Y',
    payload.tue_yn === 'Y',
    payload.wed_yn === 'Y',
    payload.thu_yn === 'Y',
    payload.fri_yn === 'Y',
    payload.sat_yn === 'Y',
  ]
}

/** 해당 월에서 n번째 요일(0=일..6=토)의 날짜. 없으면 null */
function getNthWeekdayInMonth(year: number, month: number, dayOfWeek: number, n: number): Date | null {
  const first = new Date(year, month, 1)
  const firstDow = first.getDay()
  let offset = (dayOfWeek - firstDow + 7) % 7
  if (offset === 0 && dayOfWeek !== firstDow) offset = 7
  const day = 1 + offset + (n - 1) * 7
  const lastDay = new Date(year, month + 1, 0).getDate()
  if (day > lastDay) return null
  return new Date(year, month, day)
}

/** 시작일 기준 "몇 번째 요일" (1~5). 일(7) 단위로 올림 */
function getOrdinalFromDate(d: Date): number {
  return Math.min(5, Math.ceil(d.getDate() / 7))
}

/**
 * 사용자 지정 반복(150) 날짜 구간 생성.
 * repeat_user 110=주(주차는 일요일 시작, repeat_cycle주마다, 선택 요일만), 120=개월(n번째 요일, repeat_cycle개월마다).
 * 시작일~반복종료일 사이의 모든 occurrence 반환 (과거일도 포함해 여러 건으로 저장).
 */
function getCustomRepeatDateRanges(
  payload: SaveReservationPayload,
  repeatEndYmd: string,
  _todayYmd: string
): Array<{ start_ymd: string; end_ymd: string }> {
  const endDateStr = parseRepeatEndYmd(repeatEndYmd) // YYYY-MM-DD, 종료일 당일까지 포함
  const start = new Date(payload.start_ymd)
  const startTimeSuffix = payload.start_ymd.includes('T') ? payload.start_ymd.slice(10) : 'T00:00:00.000Z'
  const endTimeSuffix = payload.end_ymd.includes('T') ? payload.end_ymd.slice(10) : 'T00:00:00.000Z'
  const toYmd = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  const toIsoStart = (d: Date) => toYmd(d) + startTimeSuffix
  const toIsoEnd = (d: Date) => toYmd(d) + endTimeSuffix

  const ranges: Array<{ start_ymd: string; end_ymd: string }> = []
  const repeatUser = Number(payload.repeat_user)
  const cycle = Math.max(1, Number(payload.repeat_cycle) || 1)

  if (repeatUser === REPEAT_USER_WEEK) {
    const flags = getWeekdayFlags(payload)
    const startYmd = toYmd(start)
    const msPerDay = 24 * 60 * 60 * 1000
    let weekIndex = 0
    while (true) {
      const refDate = new Date(start.getTime() + weekIndex * cycle * 7 * msPerDay)
      const weekStart = getSundayOfWeek(refDate)
      const weekStartYmd = toYmd(weekStart)
      if (weekStartYmd > endDateStr) break
      for (let dayOffset = 0; dayOffset < 7; dayOffset++) {
        if (!flags[dayOffset]) continue
        const d = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + dayOffset)
        const ymd = toYmd(d)
        if (ymd > endDateStr) continue
        if (ymd < startYmd) continue
        ranges.push({ start_ymd: toIsoStart(d), end_ymd: toIsoEnd(d) })
      }
      weekIndex++
    }
  } else if (repeatUser === REPEAT_USER_MONTH) {
    const dayOfWeek = start.getDay()
    const ordinal = getOrdinalFromDate(start)
    const startYmd = toYmd(start)
    let y = start.getFullYear()
    let m = start.getMonth()
    while (true) {
      const d = getNthWeekdayInMonth(y, m, dayOfWeek, ordinal)
      if (!d) break
      const ymd = toYmd(d)
      if (ymd > endDateStr) break
      if (ymd >= startYmd) {
        ranges.push({ start_ymd: toIsoStart(d), end_ymd: toIsoEnd(d) })
      }
      m += cycle
      if (m > 11) {
        y += Math.floor(m / 12)
        m = m % 12
      }
    }
  }
  return ranges
}

/**
 * 해당 회의실에서 기간 겹치는 예약 존재 여부. duplicate_yn=120일 때 사용.
 * RPC(check_reservation_overlap): 같은 room_id만, 반려(status=130) 제외, 겹침 조건 새_시작일 < end_ymd AND 새_종료일 > start_ymd.
 * excludeReservationId: 수정/드래그 시 자기 자신 제외 (insert 시 생략)
 */
async function checkOverlap(
  roomId: string,
  start_ymd: string,
  end_ymd: string,
  excludeReservationId?: string | null
): Promise<{ hasOverlap: boolean; conflictYmd?: string }> {
  const { data, error } = await supabase.rpc('check_reservation_overlap', {
    p_room_id: roomId,
    p_start_ymd: start_ymd,
    p_end_ymd: end_ymd,
    p_exclude_reservation_id: excludeReservationId ?? null,
  })
  if (error) {
    console.error('[checkOverlap] RPC error', error.message)
    throw new Error(error.message || '중복 검사 실패')
  }
  const row = Array.isArray(data) ? data[0] : data
  if (!row || row.has_overlap !== true) return { hasOverlap: false }
  return { hasOverlap: true, conflictYmd: row.conflict_ymd ?? undefined }
}

/** 여러 예약을 제외하고 중복 검사 (반복 그룹 일괄 이동·교체) */
async function checkOverlapExcluding(
  roomId: string,
  start_ymd: string,
  end_ymd: string,
  excludeReservationIds: string[]
): Promise<{ hasOverlap: boolean; conflictYmd?: string }> {
  const { data, error } = await supabase.rpc('check_reservation_overlap_excluding', {
    p_room_id: roomId,
    p_start_ymd: start_ymd,
    p_end_ymd: end_ymd,
    p_exclude_ids: excludeReservationIds.length > 0 ? excludeReservationIds : [],
  })
  if (error) {
    console.error('[checkOverlapExcluding] RPC error', error.message)
    throw new Error(error.message || '중복 검사 실패')
  }
  const row = Array.isArray(data) ? data[0] : data
  if (!row || row.has_overlap !== true) return { hasOverlap: false }
  return { hasOverlap: true, conflictYmd: row.conflict_ymd ?? undefined }
}

/** insertReservation과 동일한 조건으로 반복 펼침 여부 */
export function shouldExpandRepeatPayload(payload: SaveReservationPayload): boolean {
  const repeatId = payload.repeat_id ?? null
  const repeatEndYmd = payload.repeat_end_ymd?.trim()
  const rawRepeatUser = payload.repeat_user
  const repeatUser =
    rawRepeatUser != null && String(rawRepeatUser).trim() !== '' ? Number(rawRepeatUser) : null
  const shouldExpandStandard =
    repeatId != null &&
    !!repeatEndYmd &&
    [REPEAT_DAILY, REPEAT_WEEKLY, REPEAT_MONTHLY].includes(Number(repeatId))
  const shouldExpandCustom =
    Number(repeatId) === REPEAT_CUSTOM &&
    !!repeatEndYmd &&
    (repeatUser === REPEAT_USER_WEEK || repeatUser === REPEAT_USER_MONTH)
  return shouldExpandStandard || shouldExpandCustom
}

/** insertReservation과 동일한 날짜 구간 목록 */
export function getDateRangesForPayload(payload: SaveReservationPayload): Array<{
  start_ymd: string
  end_ymd: string
}> {
  const repeatId = payload.repeat_id ?? null
  const repeatEndYmd = payload.repeat_end_ymd?.trim()
  if (!repeatEndYmd) return [{ start_ymd: payload.start_ymd, end_ymd: payload.end_ymd }]
  const rawRepeatUser = payload.repeat_user
  const repeatUser =
    rawRepeatUser != null && String(rawRepeatUser).trim() !== '' ? Number(rawRepeatUser) : null
  const shouldExpandStandard =
    repeatId != null &&
    !!repeatEndYmd &&
    [REPEAT_DAILY, REPEAT_WEEKLY, REPEAT_MONTHLY].includes(Number(repeatId))
  const shouldExpandCustom =
    Number(repeatId) === REPEAT_CUSTOM &&
    !!repeatEndYmd &&
    (repeatUser === REPEAT_USER_WEEK || repeatUser === REPEAT_USER_MONTH)
  if (!shouldExpandStandard && !shouldExpandCustom) {
    return [{ start_ymd: payload.start_ymd, end_ymd: payload.end_ymd }]
  }
  const today = new Date()
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
  if (shouldExpandCustom) {
    return getCustomRepeatDateRanges(payload, repeatEndYmd, todayYmd)
  }
  return getRepeatDateRanges(payload.start_ymd, payload.end_ymd, Number(repeatId), repeatEndYmd)
}

/** 같은 반복 그룹에 속한 reservation_id 목록 (그룹 대표 행 포함) */
export async function fetchReservationIdsInRepeatGroup(repeatGroupId: string): Promise<string[]> {
  const { data: byGroup, error: err1 } = await supabase
    .from('mr_reservations')
    .select('reservation_id')
    .eq('repeat_group_id', repeatGroupId)
  if (err1) throw new Error(err1.message || '예약 조회 실패')
  const { data: byId, error: err2 } = await supabase
    .from('mr_reservations')
    .select('reservation_id')
    .eq('reservation_id', repeatGroupId)
    .maybeSingle()
  if (err2) throw new Error(err2.message || '예약 조회 실패')
  const set = new Set<string>()
  ;(byGroup ?? []).forEach((r: { reservation_id: string }) => set.add(r.reservation_id))
  if (byId?.reservation_id) set.add(byId.reservation_id)
  return Array.from(set)
}

function randomUuid(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID()
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

/** replace_repeat_group_reservations RPC용 행 JSON (첫 행 id = 그룹 id) */
function buildRpcRowsForPayload(
  payload: SaveReservationPayload,
  createUserUid: string,
  status: number,
  ranges: Array<{ start_ymd: string; end_ymd: string }>
): Record<string, unknown>[] {
  const groupId = randomUuid()
  return ranges.map((r, i) => {
    const reservationId = i === 0 ? groupId : randomUuid()
    const base = buildReservationRow(
      payload,
      createUserUid,
      status,
      r.start_ymd,
      r.end_ymd,
      groupId
    )
    return {
      ...base,
      reservation_id: reservationId,
      repeat_group_id: groupId,
      create_at: new Date().toISOString(),
      update_at: new Date().toISOString(),
    }
  })
}

/**
 * 반복 시리즈 전체를 삭제 후 payload 기준으로 재등록 (한 RPC 트랜잭션).
 * repeat_id=150 & repeat_user=110 인 시리즈는 UI에서 "모든 일정" 비활성 — 호출 금지.
 */
export async function replaceRepeatGroupWithPayload(
  repeatGroupId: string,
  payload: SaveReservationPayload,
  createUserUid: string
): Promise<void> {
  const { duplicate_yn } = await getRoomConfirmAndDuplicate(payload.room_id)
  const status = await getStatusForReserver(payload.room_id, createUserUid)
  let ranges = getDateRangesForPayload(payload)
  if (ranges.length === 0) {
    ranges = [{ start_ymd: payload.start_ymd, end_ymd: payload.end_ymd }]
  }
  const excludeIds = await fetchReservationIdsInRepeatGroup(repeatGroupId)
  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    for (const r of ranges) {
      const { hasOverlap, conflictYmd } = await checkOverlapExcluding(
        payload.room_id,
        r.start_ymd,
        r.end_ymd,
        excludeIds
      )
      if (hasOverlap && conflictYmd) {
        throw new Error(`${conflictYmd} 중복이 됩니다.`)
      }
    }
  }
  const rows = buildRpcRowsForPayload(payload, createUserUid, status, ranges)
  const { error } = await supabase.rpc('replace_repeat_group_reservations', {
    p_repeat_group_id: repeatGroupId,
    p_rows: rows,
  })
  if (!error) return

  // DB 타입 불일치(예: repeat_group_id varchar vs RPC uuid 파라미터) 환경 fallback
  const msg = String(error.message ?? '')
  const typeMismatch =
    msg.includes('character varying = uuid') ||
    msg.includes('operator does not exist')
  if (!typeMismatch) throw new Error(error.message || '반복 일정 일괄 수정 실패')

  const ids = await fetchReservationIdsInRepeatGroup(repeatGroupId)
  if (ids.length > 0) {
    const { error: delErr } = await supabase
      .from('mr_reservations')
      .delete()
      .in('reservation_id', ids)
    if (delErr) throw new Error(delErr.message || '반복 일정 일괄 수정 실패')
  }
  const { error: insErr } = await supabase
    .from('mr_reservations')
    .insert(rows as Record<string, unknown>[])
  if (insErr) throw new Error(insErr.message || '반복 일정 일괄 수정 실패')
}

/** 이 일정만: 일시 변경 + repeat_group_id = reservation_id (시리즈에서 분리) */
export async function updateReservationDatesThisEvent(
  reservationId: string,
  start_ymd: string,
  end_ymd: string
): Promise<void> {
  const { data: row } = await supabase
    .from('mr_reservations')
    .select('room_id, repeat_group_id')
    .eq('reservation_id', reservationId)
    .single()
  if (!row) throw new Error('예약을 찾을 수 없습니다.')
  const rowData = row as { room_id: string; repeat_group_id?: string | null }
  const roomId = rowData.room_id
  const currentGroupId = String(rowData.repeat_group_id ?? reservationId)
  const { duplicate_yn } = await getRoomConfirmAndDuplicate(roomId)
  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    const { hasOverlap, conflictYmd } = await checkOverlap(roomId, start_ymd, end_ymd, reservationId)
    if (hasOverlap && conflictYmd) {
      throw new Error(`${conflictYmd} 중복이 됩니다.`)
    }
  }
  if (currentGroupId === reservationId) {
    // 대표 행을 "이 일정"으로 떼어낼 때, 남은 행들의 그룹 키를 새 대표로 재지정
    const { data: followers, error: followersErr } = await supabase
      .from('mr_reservations')
      .select('reservation_id, start_ymd')
      .eq('repeat_group_id', currentGroupId)
      .neq('reservation_id', reservationId)
      .order('start_ymd', { ascending: true })
    if (followersErr) throw new Error(followersErr.message || '반복 그룹 재배정 실패')
    const nextRepresentativeId = (followers?.[0] as { reservation_id: string } | undefined)?.reservation_id
    if (nextRepresentativeId) {
      const followerIds = (followers ?? [])
        .map((r) => (r as { reservation_id: string }).reservation_id)
        .filter((id) => id !== reservationId)
      if (followerIds.length > 0) {
        const { error: regroupErr } = await supabase
          .from('mr_reservations')
          .update({ repeat_group_id: nextRepresentativeId })
          .in('reservation_id', followerIds)
        if (regroupErr) throw new Error(regroupErr.message || '반복 그룹 재배정 실패')
      }
    }
  }
  const { error } = await supabase
    .from('mr_reservations')
    .update({
      start_ymd,
      end_ymd,
      repeat_group_id: reservationId,
      update_at: new Date().toISOString(),
    })
    .eq('reservation_id', reservationId)
  if (error) throw new Error(error.message || '예약 일시 변경 실패')
}

/** 반복 그룹 전체를 같은 시간 차이만큼 이동 (드래그 "모든 일정") */
export async function updateRepeatGroupDatesAll(
  repeatGroupId: string,
  draggedReservationId: string,
  newStart: Date,
  newEnd: Date
): Promise<void> {
  const { data: rows, error } = await supabase
    .from('mr_reservations')
    .select(
      'reservation_id, title, room_id, allday_yn, start_ymd, end_ymd, repeat_id, repeat_end_ymd, repeat_cycle, repeat_user, sun_yn, mon_yn, tue_yn, wed_yn, thu_yn, fri_yn, sat_yn, repeat_condition, create_user'
    )
    .or(`repeat_group_id.eq.${repeatGroupId},reservation_id.eq.${repeatGroupId}`)
  if (error) throw new Error(error.message || '예약 조회 실패')
  const list = (rows ?? []) as Array<{
    reservation_id: string
    title: string
    room_id: string
    allday_yn: string | null
    start_ymd: string
    end_ymd: string
    repeat_id?: string | null
    repeat_end_ymd?: string | null
    repeat_cycle?: number | null
    repeat_user?: string | null
    sun_yn?: 'Y' | 'N' | null
    mon_yn?: 'Y' | 'N' | null
    tue_yn?: 'Y' | 'N' | null
    wed_yn?: 'Y' | 'N' | null
    thu_yn?: 'Y' | 'N' | null
    fri_yn?: 'Y' | 'N' | null
    sat_yn?: 'Y' | 'N' | null
    repeat_condition?: string | null
    create_user?: string | null
  }>
  if (list.length === 0) throw new Error('반복 일정을 찾을 수 없습니다.')
  const dragged = list.find((r) => r.reservation_id === draggedReservationId)
  if (!dragged) throw new Error('이동할 예약을 찾을 수 없습니다.')
  const anchor = list.reduce((min, cur) =>
    new Date(cur.start_ymd).getTime() < new Date(min.start_ymd).getTime() ? cur : min
  )
  const draggedStart = new Date(dragged.start_ymd)
  const draggedEnd = new Date(dragged.end_ymd)
  const deltaStartMs = newStart.getTime() - draggedStart.getTime()
  const deltaEndMs = newEnd.getTime() - draggedEnd.getTime()
  const anchorMovedStart = new Date(new Date(anchor.start_ymd).getTime() + deltaStartMs)
  const anchorMovedEnd = new Date(new Date(anchor.end_ymd).getTime() + deltaEndMs)
  const createUserUid = dragged.create_user ?? ''
  if (!createUserUid) throw new Error('예약 작성자 정보가 없습니다.')
  const payload: SaveReservationPayload = {
    title: dragged.title,
    room_id: dragged.room_id,
    allday_yn: dragged.allday_yn === 'Y' ? 'Y' : 'N',
    // "모든 일정" 이동은 드래그한 건이 아니라 시리즈 첫 occurrence를 기준으로 재생성해야
    // 마지막 건을 이동해도 전체 시리즈가 1건으로 축소되지 않는다.
    start_ymd: anchorMovedStart.toISOString(),
    end_ymd: anchorMovedEnd.toISOString(),
    repeat_id:
      dragged.repeat_id != null && String(dragged.repeat_id).trim() !== ''
        ? Number(dragged.repeat_id)
        : null,
    repeat_end_ymd: dragged.repeat_end_ymd ?? null,
    repeat_cycle: dragged.repeat_cycle ?? null,
    repeat_user:
      dragged.repeat_user != null && String(dragged.repeat_user).trim() !== ''
        ? Number(dragged.repeat_user)
        : null,
    sun_yn: dragged.sun_yn ?? 'N',
    mon_yn: dragged.mon_yn ?? 'N',
    tue_yn: dragged.tue_yn ?? 'N',
    wed_yn: dragged.wed_yn ?? 'N',
    thu_yn: dragged.thu_yn ?? 'N',
    fri_yn: dragged.fri_yn ?? 'N',
    sat_yn: dragged.sat_yn ?? 'N',
    repeat_condition: dragged.repeat_condition ?? null,
  }
  await replaceRepeatGroupWithPayload(repeatGroupId, payload, createUserUid)
}

/** 이 일정만 수정: 필드 갱신 + 시리즈에서 분리(repeat_group_id = reservation_id) */
export async function updateReservationThisInSeries(
  reservationId: string,
  payload: SaveReservationPayload
): Promise<MrReservation> {
  const { duplicate_yn } = await getRoomConfirmAndDuplicate(payload.room_id)
  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    const { hasOverlap, conflictYmd } = await checkOverlap(
      payload.room_id,
      payload.start_ymd,
      payload.end_ymd,
      reservationId
    )
    if (hasOverlap && conflictYmd) {
      throw new Error(`${conflictYmd} 중복이 됩니다.`)
    }
  }
  const { data: existing } = await supabase
    .from('mr_reservations')
    .select('create_user, repeat_group_id')
    .eq('reservation_id', reservationId)
    .maybeSingle()
  const existingRow = existing as { create_user: string | null; repeat_group_id?: string | null } | null
  const createUser = existingRow?.create_user ?? null
  const currentGroupId = String(existingRow?.repeat_group_id ?? reservationId)
  if (currentGroupId === reservationId) {
    // 대표 행을 "이 일정"으로 떼어낼 때, 남은 행들의 그룹 키를 새 대표로 재지정
    const { data: followers, error: followersErr } = await supabase
      .from('mr_reservations')
      .select('reservation_id, start_ymd')
      .eq('repeat_group_id', currentGroupId)
      .neq('reservation_id', reservationId)
      .order('start_ymd', { ascending: true })
    if (followersErr) throw new Error(followersErr.message || '반복 그룹 재배정 실패')
    const nextRepresentativeId = (followers?.[0] as { reservation_id: string } | undefined)?.reservation_id
    if (nextRepresentativeId) {
      const followerIds = (followers ?? [])
        .map((r) => (r as { reservation_id: string }).reservation_id)
        .filter((id) => id !== reservationId)
      if (followerIds.length > 0) {
        const { error: regroupErr } = await supabase
          .from('mr_reservations')
          .update({ repeat_group_id: nextRepresentativeId })
          .in('reservation_id', followerIds)
        if (regroupErr) throw new Error(regroupErr.message || '반복 그룹 재배정 실패')
      }
    }
  }
  const reserverUid = createUser ?? ''
  const status = await getStatusForReserver(payload.room_id, reserverUid)
  const row = {
    title: payload.title,
    room_id: payload.room_id,
    allday_yn: payload.allday_yn ?? 'N',
    start_ymd: payload.start_ymd,
    end_ymd: payload.end_ymd,
    repeat_id: payload.repeat_id ?? null,
    repeat_end_ymd: payload.repeat_end_ymd ?? null,
    repeat_cycle: payload.repeat_cycle ?? null,
    repeat_user: payload.repeat_user ?? null,
    sun_yn: payload.sun_yn ?? 'N',
    mon_yn: payload.mon_yn ?? 'N',
    tue_yn: payload.tue_yn ?? 'N',
    wed_yn: payload.wed_yn ?? 'N',
    thu_yn: payload.thu_yn ?? 'N',
    fri_yn: payload.fri_yn ?? 'N',
    sat_yn: payload.sat_yn ?? 'N',
    repeat_condition: payload.repeat_condition ?? null,
    repeat_group_id: reservationId,
    status,
    update_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('mr_reservations')
    .update(row)
    .eq('reservation_id', reservationId)
    .select()
    .single()
  if (error) throw new Error(error.message || '예약 수정 실패')
  return data as MrReservation
}

/** 예약 저장용 payload (메인 예약/수정 모달 → mr_reservations) */
export interface SaveReservationPayload {
  title: string
  room_id: string
  allday_yn: 'Y' | 'N'
  start_ymd: string
  end_ymd: string
  repeat_id?: number | null
  repeat_end_ymd?: string | null
  repeat_cycle?: number | null
  repeat_user?: number | null
  sun_yn?: 'Y' | 'N'
  mon_yn?: 'Y' | 'N'
  tue_yn?: 'Y' | 'N'
  wed_yn?: 'Y' | 'N'
  thu_yn?: 'Y' | 'N'
  fri_yn?: 'Y' | 'N'
  sat_yn?: 'Y' | 'N'
  repeat_condition?: string | null
}

/** 공통 row 필드 (repeat_group_id 제외) */
function buildReservationRow(
  payload: SaveReservationPayload,
  createUserUid: string,
  status: number,
  start_ymd: string,
  end_ymd: string,
  repeat_group_id: string | null
): Record<string, unknown> {
  return {
    title: payload.title,
    room_id: payload.room_id,
    allday_yn: payload.allday_yn ?? 'N',
    start_ymd,
    end_ymd,
    repeat_id: payload.repeat_id ?? null,
    repeat_end_ymd: payload.repeat_end_ymd ?? null,
    repeat_cycle: payload.repeat_cycle ?? null,
    repeat_user: payload.repeat_user ?? null,
    sun_yn: payload.sun_yn ?? 'N',
    mon_yn: payload.mon_yn ?? 'N',
    tue_yn: payload.tue_yn ?? 'N',
    wed_yn: payload.wed_yn ?? 'N',
    thu_yn: payload.thu_yn ?? 'N',
    fri_yn: payload.fri_yn ?? 'N',
    sat_yn: payload.sat_yn ?? 'N',
    repeat_condition: payload.repeat_condition ?? null,
    repeat_group_id,
    status,
    approver: null,
    create_user: createUserUid,
  }
}

export type InsertReservationResult =
  | MrReservation
  | { reservation: MrReservation; isRepeat: true }

/** 신규 예약 insert. confirm_yn=120이고 repeat_id 120/130/140이면 repeat_end_ymd까지 여러 행 insert. */
export async function insertReservation(
  payload: SaveReservationPayload,
  createUserUid: string
): Promise<InsertReservationResult> {
  console.log('[insertReservation] payload', {
    room_id: payload.room_id,
    repeat_id: payload.repeat_id,
    repeat_end_ymd: payload.repeat_end_ymd,
    start_ymd: payload.start_ymd,
    end_ymd: payload.end_ymd,
  })

  const { confirm_yn, duplicate_yn } = await getRoomConfirmAndDuplicate(payload.room_id)
  console.log('[insertReservation] room', { confirm_yn, duplicate_yn })

  const status = await getStatusForReserver(payload.room_id, createUserUid)

  const repeatId = payload.repeat_id ?? null
  const repeatEndYmd = payload.repeat_end_ymd?.trim()
  const rawRepeatUser = payload.repeat_user
  const repeatUser =
    rawRepeatUser != null && String(rawRepeatUser).trim() !== '' ? Number(rawRepeatUser) : null
  const shouldExpandStandard =
    repeatId != null &&
    repeatEndYmd &&
    [REPEAT_DAILY, REPEAT_WEEKLY, REPEAT_MONTHLY].includes(Number(repeatId))
  const shouldExpandCustom =
    Number(repeatId) === REPEAT_CUSTOM &&
    repeatEndYmd &&
    (repeatUser === REPEAT_USER_WEEK || repeatUser === REPEAT_USER_MONTH)
  const shouldExpand = shouldExpandStandard || shouldExpandCustom

  console.log('[insertReservation] shouldExpand', shouldExpand, {
    shouldExpandStandard,
    shouldExpandCustom,
    repeatId,
    repeatEndYmd,
    repeatUser,
    repeat_cycle: payload.repeat_cycle,
  })

  if (!shouldExpand) {
    console.log('[insertReservation] 단일 행 저장')
    if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
      const { hasOverlap, conflictYmd } = await checkOverlap(
        payload.room_id,
        payload.start_ymd,
        payload.end_ymd
      )
      if (hasOverlap && conflictYmd) {
        throw new Error(`${conflictYmd} 중복이 됩니다.`)
      }
    }
    const row = buildReservationRow(
      payload,
      createUserUid,
      status,
      payload.start_ymd,
      payload.end_ymd,
      null
    ) as Record<string, unknown>
    const { data, error } = await supabase.from('mr_reservations').insert(row).select().single()
    if (error) throw new Error(error.message || '예약 등록 실패')
    return data as MrReservation
  }

  const today = new Date()
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`
  const ranges = shouldExpandCustom
    ? getCustomRepeatDateRanges(payload, repeatEndYmd, todayYmd)
    : getRepeatDateRanges(
        payload.start_ymd,
        payload.end_ymd,
        Number(repeatId),
        repeatEndYmd
      )
  console.log('[insertReservation] 반복 구간 수', ranges.length, '첫 3건', ranges.slice(0, 3))

  if (ranges.length === 0) {
    console.log('[insertReservation] 구간 0건 → 단일 행 저장')
    if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
      const { hasOverlap, conflictYmd } = await checkOverlap(
        payload.room_id,
        payload.start_ymd,
        payload.end_ymd
      )
      if (hasOverlap && conflictYmd) {
        throw new Error(`${conflictYmd} 중복이 됩니다.`)
      }
    }
    const row = buildReservationRow(
      payload,
      createUserUid,
      status,
      payload.start_ymd,
      payload.end_ymd,
      null
    ) as Record<string, unknown>
    const { data, error } = await supabase.from('mr_reservations').insert(row).select().single()
    if (error) throw new Error(error.message || '예약 등록 실패')
    return data as MrReservation
  }

  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    for (const r of ranges) {
      const { hasOverlap, conflictYmd } = await checkOverlap(
        payload.room_id,
        r.start_ymd,
        r.end_ymd
      )
      if (hasOverlap && conflictYmd) {
        throw new Error(`${conflictYmd} 중복이 됩니다.`)
      }
    }
  }

  const first = buildReservationRow(
    payload,
    createUserUid,
    status,
    ranges[0].start_ymd,
    ranges[0].end_ymd,
    null
  ) as Record<string, unknown>
  const { data: firstData, error: firstError } = await supabase
    .from('mr_reservations')
    .insert(first)
    .select()
    .single()
  if (firstError) throw new Error(firstError.message || '예약 등록 실패')
  const firstRow = firstData as MrReservation & { repeat_group_id?: string | null }
  const groupId = firstRow.reservation_id
  console.log('[insertReservation] 첫 행 ID( repeat_group_id )', groupId, '추가 행 수', ranges.length - 1)

  await supabase
    .from('mr_reservations')
    .update({ repeat_group_id: groupId })
    .eq('reservation_id', groupId)

  for (let i = 1; i < ranges.length; i++) {
    const r = ranges[i]
    const row = buildReservationRow(
      payload,
      createUserUid,
      status,
      r.start_ymd,
      r.end_ymd,
      groupId
    ) as Record<string, unknown>
    const { error } = await supabase.from('mr_reservations').insert(row)
    if (error) throw new Error(error.message || '예약 등록 실패')
  }
  console.log('[insertReservation] 반복 저장 완료', ranges.length, '건')

  return { reservation: firstRow as MrReservation, isRepeat: true }
}

/** 예약 수정 update. 같은 회의실·시간 중복은 항상 검사(반려 제외). 예약자(create_user)가 담당자/승인자이면 140, 아니면 기존 로직. */
export async function updateReservation(
  reservationId: string,
  payload: SaveReservationPayload
): Promise<MrReservation> {
  const { duplicate_yn } = await getRoomConfirmAndDuplicate(payload.room_id)
  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    const { hasOverlap, conflictYmd } = await checkOverlap(
      payload.room_id,
      payload.start_ymd,
      payload.end_ymd,
      reservationId
    )
    if (hasOverlap && conflictYmd) {
      throw new Error(`${conflictYmd} 중복이 됩니다.`)
    }
  }
  const { data: existing } = await supabase
    .from('mr_reservations')
    .select('create_user')
    .eq('reservation_id', reservationId)
    .maybeSingle()
  const createUser = (existing as { create_user: string | null } | null)?.create_user ?? null
  const reserverUid = createUser ?? ''
  const status = await getStatusForReserver(payload.room_id, reserverUid)
  const row = {
    title: payload.title,
    room_id: payload.room_id,
    allday_yn: payload.allday_yn ?? 'N',
    start_ymd: payload.start_ymd,
    end_ymd: payload.end_ymd,
    repeat_id: payload.repeat_id ?? null,
    repeat_end_ymd: payload.repeat_end_ymd ?? null,
    repeat_cycle: payload.repeat_cycle ?? null,
    repeat_user: payload.repeat_user ?? null,
    sun_yn: payload.sun_yn ?? 'N',
    mon_yn: payload.mon_yn ?? 'N',
    tue_yn: payload.tue_yn ?? 'N',
    wed_yn: payload.wed_yn ?? 'N',
    thu_yn: payload.thu_yn ?? 'N',
    fri_yn: payload.fri_yn ?? 'N',
    sat_yn: payload.sat_yn ?? 'N',
    repeat_condition: payload.repeat_condition ?? null,
    status,
    update_at: new Date().toISOString(),
  }
  const { data, error } = await supabase
    .from('mr_reservations')
    .update(row)
    .eq('reservation_id', reservationId)
    .select()
    .single()
  if (error) throw new Error(error.message || '예약 수정 실패')
  return data as MrReservation
}

/** 드래그/리사이즈로 일시만 변경. 같은 회의실·시간 중복은 항상 검사(반려 제외, duplicate_yn 무관). */
export async function updateReservationDates(
  reservationId: string,
  start_ymd: string,
  end_ymd: string
): Promise<void> {
  const { data: row } = await supabase
    .from('mr_reservations')
    .select('room_id')
    .eq('reservation_id', reservationId)
    .single()
  if (!row) throw new Error('예약을 찾을 수 없습니다.')
  const roomId = (row as { room_id: string }).room_id
  const { duplicate_yn } = await getRoomConfirmAndDuplicate(roomId)
  if (Number(duplicate_yn) === DUPLICATE_YN_CHECK) {
    const { hasOverlap, conflictYmd } = await checkOverlap(
      roomId,
      start_ymd,
      end_ymd,
      reservationId
    )
    if (hasOverlap && conflictYmd) {
      throw new Error(`${conflictYmd} 중복이 됩니다.`)
    }
  }
  const { error } = await supabase
    .from('mr_reservations')
    .update({
      start_ymd,
      end_ymd,
      update_at: new Date().toISOString(),
    })
    .eq('reservation_id', reservationId)
  if (error) throw new Error(error.message || '예약 일시 변경 실패')
}

/** 예약 삭제 (mr_reservations) - 단일 건 */
export async function deleteReservation(reservationId: string): Promise<void> {
  const { error } = await supabase
    .from('mr_reservations')
    .delete()
    .eq('reservation_id', reservationId)
  if (error) throw new Error(error.message || '예약 삭제 실패')
}

/** 반복 일정: 이 일정 + 향후 일정 삭제 (같은 repeat_group_id, start_ymd >= 선택 건) */
export async function deleteReservationThisAndFollowing(reservationId: string): Promise<void> {
  const { data: row, error: fetchErr } = await supabase
    .from('mr_reservations')
    .select('repeat_group_id, start_ymd')
    .eq('reservation_id', reservationId)
    .single()
  if (fetchErr || !row?.repeat_group_id) {
    if (fetchErr) throw new Error(fetchErr.message || '예약 조회 실패')
    throw new Error('반복 그룹 정보가 없습니다.')
  }
  const { error } = await supabase
    .from('mr_reservations')
    .delete()
    .eq('repeat_group_id', row.repeat_group_id)
    .gte('start_ymd', row.start_ymd)
  if (error) throw new Error(error.message || '예약 삭제 실패')
}

/** 반복 일정: 같은 repeat_group_id 전체 삭제 */
export async function deleteReservationAllInGroup(repeatGroupId: string): Promise<void> {
  const { error } = await supabase
    .from('mr_reservations')
    .delete()
    .eq('repeat_group_id', repeatGroupId)
  if (error) throw new Error(error.message || '예약 삭제 실패')
}

/** 이 일정만: 반복 펼침이 필요하면 해당 행 삭제 후 insertReservation과 동일하게 재등록 */
export async function updateReservationThisInstanceReexpand(
  reservationId: string,
  payload: SaveReservationPayload,
  createUserUid?: string
): Promise<InsertReservationResult> {
  let ownerUid = (createUserUid ?? '').trim()
  if (!ownerUid) {
    const { data: existing, error } = await supabase
      .from('mr_reservations')
      .select('create_user')
      .eq('reservation_id', reservationId)
      .maybeSingle()
    if (error) throw new Error(error.message || '예약 조회 실패')
    ownerUid = ((existing as { create_user?: string | null } | null)?.create_user ?? '').trim()
  }
  if (!ownerUid) throw new Error('예약 작성자 정보가 없습니다.')
  await deleteReservation(reservationId)
  return insertReservation(payload, ownerUid)
}
