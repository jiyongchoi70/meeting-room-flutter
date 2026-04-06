import 'package:intl/intl.dart';

import '../../../../core/repeat_date_ranges.dart';

/// 반복 UI 모드. `매주` 는 저장 시 [kRepeatCustom]+[kRepeatUserWeek] 로 매핑.
enum RepeatUiMode {
  none,
  daily,
  weekly,
  monthlyByDate,
  monthlyByWeekday,
}

class RepeatScheduleSelection {
  const RepeatScheduleSelection({
    required this.mode,
    required this.repeatUntil,
    this.dailyInterval = 1,
    this.weeklyInterval = 1,
    this.monthlyInterval = 1,
    List<bool>? weekdayFlags,
  }) : weekdayFlags = weekdayFlags ?? const [];

  final RepeatUiMode mode;
  final DateTime repeatUntil;

  /// 매일 N일 간격 (>=1)
  final int dailyInterval;

  /// 매주 N주 간격 (>=1)
  final int weeklyInterval;

  /// 매월 n번째 요일 반복 시 몇 개월마다 (>=1)
  final int monthlyInterval;

  /// 일~토 (인덱스 0=일)
  final List<bool> weekdayFlags;

  bool get isRepeating => mode != RepeatUiMode.none;

  /// DB `repeat_end_ymd` 가 `varchar(8)` (YYYYMMDD) 일 때 — ISO 문자열은 길이 초과(22001) 발생
  static String repeatEndYmdForDb(DateTime d) {
    final l = d.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final day = l.day.toString().padLeft(2, '0');
    return '$y$m$day';
  }

  static List<bool> _defaultWeekdayFromStart(DateTime start) {
    final flags = List<bool>.filled(7, false);
    flags[start.weekday % 7] = true;
    return flags;
  }

  factory RepeatScheduleSelection.initial({
    required DateTime reservationStart,
    required DateTime reservationEnd,
  }) {
    final endDay = DateTime(
      reservationEnd.year,
      reservationEnd.month,
      reservationEnd.day,
    );
    var until = endDay.add(const Duration(days: 30));
    final startDay = DateTime(
      reservationStart.year,
      reservationStart.month,
      reservationStart.day,
    );
    if (until.isBefore(startDay)) {
      until = startDay;
    }
    return RepeatScheduleSelection(
      mode: RepeatUiMode.none,
      repeatUntil: until,
      weekdayFlags: _defaultWeekdayFromStart(reservationStart),
    );
  }

  RepeatScheduleSelection copyWith({
    RepeatUiMode? mode,
    DateTime? repeatUntil,
    int? dailyInterval,
    int? weeklyInterval,
    int? monthlyInterval,
    List<bool>? weekdayFlags,
  }) {
    return RepeatScheduleSelection(
      mode: mode ?? this.mode,
      repeatUntil: repeatUntil ?? this.repeatUntil,
      dailyInterval: dailyInterval ?? this.dailyInterval,
      weeklyInterval: weeklyInterval ?? this.weeklyInterval,
      monthlyInterval: monthlyInterval ?? this.monthlyInterval,
      weekdayFlags: weekdayFlags ?? List<bool>.from(this.weekdayFlags),
    );
  }

  /// `createReservation` 에 합치는 반복 필드 (반복 없으면 비움)
  Map<String, dynamic> repeatFieldsForPayload() {
    if (!isRepeating) return {};
    final untilYmd = repeatEndYmdForDb(repeatUntil);
    switch (mode) {
      case RepeatUiMode.none:
        return {};
      case RepeatUiMode.daily:
        return {
          'repeat_id': '$kRepeatDaily',
          'repeat_end_ymd': untilYmd,
          'repeat_cycle': dailyInterval,
        };
      case RepeatUiMode.weekly:
        return {
          'repeat_id': '$kRepeatCustom',
          'repeat_user': '$kRepeatUserWeek',
          'repeat_end_ymd': untilYmd,
          'repeat_cycle': weeklyInterval,
          'sun_yn': weekdayFlags[0] ? 'Y' : 'N',
          'mon_yn': weekdayFlags[1] ? 'Y' : 'N',
          'tue_yn': weekdayFlags[2] ? 'Y' : 'N',
          'wed_yn': weekdayFlags[3] ? 'Y' : 'N',
          'thu_yn': weekdayFlags[4] ? 'Y' : 'N',
          'fri_yn': weekdayFlags[5] ? 'Y' : 'N',
          'sat_yn': weekdayFlags[6] ? 'Y' : 'N',
        };
      case RepeatUiMode.monthlyByDate:
        return {
          'repeat_id': '$kRepeatMonthly',
          'repeat_end_ymd': untilYmd,
        };
      case RepeatUiMode.monthlyByWeekday:
        return {
          'repeat_id': '$kRepeatCustom',
          'repeat_user': '$kRepeatUserMonth',
          'repeat_end_ymd': untilYmd,
          'repeat_cycle': monthlyInterval,
        };
    }
  }

  static final _untilFmt = DateFormat('yyyy년 M월 d일(E)', 'ko_KR');
  static const _dowShort = ['일', '월', '화', '수', '목', '금', '토'];

  String _untilLabel() => _untilFmt.format(repeatUntil);

  static String _ordinalKo(int n) {
    const names = ['', '첫 번째', '두 번째', '세 번째', '네 번째', '다섯 번째'];
    if (n >= 1 && n < names.length) return names[n];
    return '$n번째';
  }

  static String _weekdayLongKo(DateTime d) {
    const long = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];
    return long[d.weekday % 7];
  }

  /// 매월 n번째 요일 칩 라벨 (예: 첫 번째 월요일)
  static String monthlyNthPillLabel(DateTime reservationStart) {
    final ord = ordinalFromDate(reservationStart);
    final w = _weekdayLongKo(reservationStart);
    return '${_ordinalKo(ord)} $w';
  }

  /// 메인 폼 요약 칩
  String summaryLine({required DateTime reservationStart}) {
    if (!isRepeating) return '반복 없음';
    final until = _untilLabel();
    switch (mode) {
      case RepeatUiMode.none:
        return '반복 없음';
      case RepeatUiMode.daily:
        if (dailyInterval <= 1) {
          return '매일, $until 까지';
        }
        return '$dailyInterval일 간격, $until 까지';
      case RepeatUiMode.weekly:
        final parts = <String>[];
        for (var i = 0; i < 7; i++) {
          if (i < weekdayFlags.length && weekdayFlags[i]) {
            parts.add(_dowShort[i]);
          }
        }
        final days = parts.join(', ');
        if (weeklyInterval <= 1) {
          return '매주 ($days), $until 까지';
        }
        return '$weeklyInterval주 간격으로 ($days) 마다, $until 까지';
      case RepeatUiMode.monthlyByDate:
        final day = reservationStart.day;
        return '매월 ($day일마다), $until 까지';
      case RepeatUiMode.monthlyByWeekday:
        final ord = ordinalFromDate(reservationStart);
        final w = _weekdayLongKo(reservationStart);
        return '매월 (${_ordinalKo(ord)} $w 마다), $until 까지';
    }
  }

  /// 반복 설정 화면 상단 안내 문구
  String statusMessage({required DateTime reservationStart}) {
    if (!isRepeating) {
      return '반복되지 않는 일정입니다.';
    }
    switch (mode) {
      case RepeatUiMode.none:
        return '반복되지 않는 일정입니다.';
      case RepeatUiMode.daily:
        final n = dailyInterval;
        return '$n일마다 반복되는 일정입니다.';
      case RepeatUiMode.weekly:
        final parts = <String>[];
        for (var i = 0; i < 7; i++) {
          if (i < weekdayFlags.length && weekdayFlags[i]) {
            parts.add(_dowShort[i]);
          }
        }
        final days = parts.join(', ');
        final head = weeklyInterval <= 1 ? '매주' : '$weeklyInterval주마다';
        return '$head $days에 반복되는 일정입니다.';
      case RepeatUiMode.monthlyByDate:
        return '매월 ${reservationStart.day}일에 반복되는 일정입니다.';
      case RepeatUiMode.monthlyByWeekday:
        final ord = ordinalFromDate(reservationStart);
        final w = _weekdayLongKo(reservationStart);
        return '매월 ${_ordinalKo(ord)} $w 마다 반복되는 일정입니다.';
    }
  }
}
