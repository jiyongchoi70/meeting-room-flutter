class CalendarEventModel {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String roomId;
  final String roomName;
  final String? repeatGroupId;
  final int? status;
  final String? createUser;
  /// 반려(130) 시 승인자가 남긴 사유 (`mr_reservations.return_comment`).
  final String? returnComment;

  /// `Y` / `N` / null
  final String? alldayYn;

  /// `mr_lookup_value` 반복 유형(110=없음, 120=매일 …).
  final int? repeatId;
  final String? repeatEndYmd;
  final int? repeatCycle;
  final int? repeatUser;
  final List<bool> weekdayFlags;

  CalendarEventModel({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.roomId,
    required this.roomName,
    this.repeatGroupId,
    this.status,
    this.createUser,
    this.returnComment,
    this.alldayYn,
    this.repeatId,
    this.repeatEndYmd,
    this.repeatCycle,
    this.repeatUser,
    List<bool>? weekdayFlags,
  }) : weekdayFlags = weekdayFlags ?? const [];

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v'.trim());
  }

  static List<bool> _weekdayFlagsFromMap(Map<String, dynamic> map) => [
        map['sun_yn'] == 'Y',
        map['mon_yn'] == 'Y',
        map['tue_yn'] == 'Y',
        map['wed_yn'] == 'Y',
        map['thu_yn'] == 'Y',
        map['fri_yn'] == 'Y',
        map['sat_yn'] == 'Y',
      ];

  factory CalendarEventModel.fromMap(Map<String, dynamic> map) {
    return CalendarEventModel(
      id: map['reservation_id'] as String,
      title: (map['title'] ?? '') as String,
      start: DateTime.parse(map['start_ymd'] as String),
      end: DateTime.parse(map['end_ymd'] as String),
      roomId: map['room_id'] as String,
      roomName: (map['room_nm'] ?? '') as String,
      repeatGroupId: map['repeat_group_id'] as String?,
      status: (map['status'] as num?)?.toInt(),
      createUser: map['create_user'] as String?,
      returnComment: map['return_comment'] as String?,
      alldayYn: map['allday_yn'] as String?,
      repeatId: _parseInt(map['repeat_id']),
      repeatEndYmd: map['repeat_end_ymd'] as String?,
      repeatCycle: _parseInt(map['repeat_cycle']),
      repeatUser: _parseInt(map['repeat_user']),
      weekdayFlags: _weekdayFlagsFromMap(map),
    );
  }
}
