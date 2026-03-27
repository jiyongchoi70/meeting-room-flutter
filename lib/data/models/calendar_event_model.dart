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
  });

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
    );
  }
}
