export interface LookupValue {
  lookup_value_cd: number | string
  lookup_value_nm?: string | null
  start_ymd?: string | null
  end_ymd?: string | null
  [key: string]: unknown
}

export interface MrReservation {
  reservation_id: string
  title: string
  room_id: string
  allday_yn?: string | null
  start_ymd: string
  end_ymd: string
  create_user: string
  approver?: string | null
  repeat_group_id?: string | null
  status?: number | null
  return_comment?: string | null
  repeat_id?: number | string | null
  repeat_end_ymd?: string | null
  repeat_cycle?: number | string | null
  repeat_user?: number | string | null
  repeat_num_json?: string | null
  create_date?: string | null
  [key: string]: unknown
}

export interface MrRoom {
  room_id: string
  room_nm?: string | null
  confirm_yn?: number | null
  duplicate_yn?: number | null
  [key: string]: unknown
}

export interface MrUser {
  user_uid: string
  user_name?: string | null
  user_position?: number | null
  phone?: string | null
  create_ymd?: string | null
  [key: string]: unknown
}

export interface ReservationRow {
  reservation_id: string
  title: string
  room_id: string
  room_nm: string
  allday_yn?: string | null
  start_ymd: string
  end_ymd: string
  start_date_time?: string
  end_date_time?: string
  applicant_name?: string
  applicant_position_nm?: string
  applicant_phone?: string
  approver_name?: string
  create_user: string
  repeat_yn?: string
  repeat_group_id?: string | null
  status?: number | null
  status_nm?: string
  return_comment?: string | null
  repeat_id?: number | null
  repeat_end_ymd?: string | null
  repeat_cycle?: number | null
  repeat_user?: number | null
  repeat_num_json?: string | null
  create_date?: string | null
  selectable?: boolean
  [key: string]: unknown
}
