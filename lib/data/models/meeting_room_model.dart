class MeetingRoom {
  const MeetingRoom({
    required this.id,
    required this.name,
    this.capacity,
  });

  final String id;
  final String name;
  final int? capacity;

  factory MeetingRoom.fromMrRoom(Map<String, dynamic> r) {
    return MeetingRoom(
      id: r['room_id'] as String,
      name: r['room_nm'] as String? ?? '',
      capacity: r['cnt'] as int?,
    );
  }
}
