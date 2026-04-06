import 'package:flutter/material.dart';

/// `src/api/reservations.ts` STATUS_* 와 동일 (lookup 예약상태).
const int kReservationStatusApplied = 110;
const int kReservationStatusApproved = 120;
const int kReservationStatusRejected = 130;
const int kReservationStatusCompleted = 140;

String reservationStatusLabel(int? status) {
  switch (status) {
    case kReservationStatusApplied:
      return '신청';
    case kReservationStatusApproved:
      return '승인';
    case kReservationStatusRejected:
      return '반려';
    case kReservationStatusCompleted:
      return '완료';
    default:
      return '—';
  }
}

(Color background, Color foreground, Color border) reservationStatusColors(
  int? status,
) {
  switch (status) {
    case kReservationStatusApplied:
      return (
        Colors.transparent,
        Colors.blue.shade900,
        Colors.blue.shade700,
      );
    case kReservationStatusApproved:
      return (
        Colors.transparent,
        Colors.blue.shade900,
        Colors.blue.shade700,
      );
    case kReservationStatusRejected:
      return (
        Colors.transparent,
        Colors.red.shade800,
        Colors.red,
      );
    case kReservationStatusCompleted:
      return (
        Colors.transparent,
        Colors.blueGrey.shade900,
        Colors.blueGrey.shade600,
      );
    default:
      return (
        Colors.transparent,
        Colors.grey.shade700,
        Colors.grey.shade400,
      );
  }
}

/// 예약 상태(신청·승인·반려·완료)를 캘린더·예약 상세와 동일한 스타일로 표시.
class ReservationStatusChip extends StatelessWidget {
  const ReservationStatusChip({super.key, required this.status});

  final int? status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = reservationStatusColors(status);
    final label = reservationStatusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bd, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
