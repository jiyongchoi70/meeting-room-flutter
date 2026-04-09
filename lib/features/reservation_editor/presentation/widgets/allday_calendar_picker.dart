import 'package:flutter/material.dart';

/// 하루 종일 일정용 인라인 날짜 선택 (예약 생성·수정 공통).
class AllDayCalendarPicker extends StatelessWidget {
  const AllDayCalendarPicker({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: CalendarDatePicker(
        initialDate: selectedDate,
        currentDate: DateTime.now(),
        firstDate: DateTime(2020, 1, 1),
        lastDate: DateTime(2100, 12, 31),
        onDateChanged: onDateChanged,
      ),
    );
  }
}
