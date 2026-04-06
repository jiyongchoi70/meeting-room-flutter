import 'package:flutter/material.dart';

/// 회의실 카드(예약 생성·수정 공통) — 라벨은 작은 회색, 값은 본문 크기의 짙은 회색.
abstract final class MeetingRoomCardStyles {
  static const Color labelColor = Color(0xFF666666);
  static const Color valueColor = Color(0xFF333333);

  static TextStyle? labelStyle(TextTheme theme) => theme.bodySmall?.copyWith(
        color: labelColor,
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w400,
      );

  static TextStyle? fieldStyle(TextTheme theme) => theme.bodyLarge?.copyWith(
        color: valueColor,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w400,
      );
}
