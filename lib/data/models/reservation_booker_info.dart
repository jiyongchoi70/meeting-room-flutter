/// 예약 상세에 표시하는 예약자(작성자) 표시용 정보.
class ReservationBookerInfo {
  const ReservationBookerInfo({
    required this.name,
    this.positionName,
    this.phone = '',
  });

  final String name;
  final String? positionName;
  final String phone;

  /// 콜론 뒤에 붙는 본문: `이름 (직분) 010-…`
  String get detailAfterColon {
    final n = name.trim();
    final p = positionName?.trim() ?? '';
    final ph = phone.trim();
    if (n.isEmpty && p.isEmpty && ph.isEmpty) return '—';
    final mid = p.isNotEmpty ? ' ($p)' : '';
    final gap =
        (n.isNotEmpty || p.isNotEmpty) && ph.isNotEmpty ? ' ' : '';
    return '$n$mid$gap$ph';
  }
}
