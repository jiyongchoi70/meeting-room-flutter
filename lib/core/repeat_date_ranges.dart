import 'dart:math' as math;

/// 웹 `src/api/reservations.ts` 의 반복 펼침과 정합. 매일(120)은 [repeatCycle]일 간격 지원.
const int kRepeatNone = 110;
const int kRepeatDaily = 120;
const int kRepeatWeekly = 130;
const int kRepeatMonthly = 140;
const int kRepeatCustom = 150;

const int kRepeatUserWeek = 110;
const int kRepeatUserMonth = 120;

class RepeatOccurrence {
  const RepeatOccurrence({required this.startUtc, required this.endUtc});

  final DateTime startUtc;
  final DateTime endUtc;
}

/// 반복 종료일 문자열 → `YYYY-MM-DD` (웹 `parseRepeatEndYmd`)
String parseRepeatEndYmd(String repeatEndRaw) {
  final t = repeatEndRaw.trim();
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 8) {
    final s = digits.substring(0, 8);
    return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
  }
  final head = t.length >= 10 ? t.substring(0, 10) : t;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(head)) return head;
  return t;
}

String _ymdLocal(DateTime dt) {
  final l = dt.toLocal();
  final y = l.year.toString().padLeft(4, '0');
  final m = l.month.toString().padLeft(2, '0');
  final d = l.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _timeSuffixFromIso(String iso) {
  final i = iso.indexOf('T');
  if (i >= 0) return iso.substring(i);
  return 'T00:00:00.000Z';
}

DateTime _applyYmdWithSuffix(String ymd, String fullIsoTemplate) {
  final suffix = _timeSuffixFromIso(fullIsoTemplate);
  return DateTime.parse('$ymd$suffix');
}

DateTime _addMonthsLocal(DateTime dt, int months) {
  final l = dt.toLocal();
  final totalM = l.month - 1 + months;
  final y = l.year + totalM ~/ 12;
  final m = totalM % 12 + 1;
  final dim = DateTime(y, m + 1, 0).day;
  final day = math.min(l.day, dim);
  return DateTime(
    y,
    m,
    day,
    l.hour,
    l.minute,
    l.second,
    l.millisecond,
    l.microsecond,
  );
}

/// 표준 반복(120/130/140). 매일은 [repeatCycle]일마다(기본 1).
List<RepeatOccurrence> getStandardRepeatOccurrences({
  required DateTime startUtc,
  required DateTime endUtc,
  required int repeatId,
  required String repeatEndIso,
  int repeatCycle = 1,
}) {
  final endDateStr = parseRepeatEndYmd(repeatEndIso);
  final cycle = math.max(1, repeatCycle);

  final duration = endUtc.difference(startUtc);
  final ranges = <RepeatOccurrence>[];

  var start = startUtc;
  var end = endUtc;

  String toYmd(DateTime d) => _ymdLocal(d);

  if (repeatId == kRepeatDaily) {
    while (toYmd(start).compareTo(endDateStr) <= 0) {
      ranges.add(RepeatOccurrence(startUtc: start, endUtc: end));
      start = start.add(Duration(days: cycle));
      end = start.add(duration);
    }
  } else if (repeatId == kRepeatWeekly) {
    while (toYmd(start).compareTo(endDateStr) <= 0) {
      ranges.add(RepeatOccurrence(startUtc: start, endUtc: end));
      start = start.add(Duration(days: 7 * cycle));
      end = start.add(duration);
    }
  } else if (repeatId == kRepeatMonthly) {
    final dayOfMonth = start.toLocal().day;
    var curStart = start;
    var curEnd = end;
    while (toYmd(curStart).compareTo(endDateStr) <= 0) {
      final cl = curStart.toLocal();
      final dim = DateTime(cl.year, cl.month + 1, 0).day;
      if (dayOfMonth <= dim) {
        ranges.add(RepeatOccurrence(startUtc: curStart, endUtc: curEnd));
      }
      curStart = _addMonthsLocal(curStart, 1);
      curEnd = curStart.add(duration);
    }
  }

  ranges.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return ranges;
}

bool _weekdayFlag(List<bool> flags, int i) =>
    i >= 0 && i < flags.length && flags[i];

/// 웹 `getSundayOfWeek` (로컬 날짜 기준, JS getDay 0=일)
DateTime sundayOfWeekLocal(DateTime d) {
  final l = d.toLocal();
  final day = DateTime(l.year, l.month, l.day);
  final back = l.weekday == DateTime.sunday ? 0 : l.weekday;
  return day.subtract(Duration(days: back));
}

/// 웹 `getNthWeekdayInMonth` — [month0] 0~11 (JS month)
DateTime? nthWeekdayInMonthJs(
    int year, int month0, int dayOfWeekJs, int n) {
  final first = DateTime(year, month0 + 1, 1);
  final firstDow = first.weekday % 7;
  var offset = (dayOfWeekJs - firstDow + 7) % 7;
  if (offset == 0 && dayOfWeekJs != firstDow) offset = 7;
  final day = 1 + offset + (n - 1) * 7;
  final lastDay = DateTime(year, month0 + 2, 0).day;
  if (day > lastDay) return null;
  return DateTime(year, month0 + 1, day);
}

/// 웹 `getOrdinalFromDate`
int ordinalFromDate(DateTime d) {
  final day = d.toLocal().day;
  return math.min(5, (day / 7).ceil());
}

/// 사용자설정 반복(150). [repeatUser] 110=주, 120=개월(특정 요일 n번째)
List<RepeatOccurrence> getCustomRepeatOccurrences({
  required DateTime startUtc,
  required DateTime endUtc,
  required String repeatEndIso,
  required int repeatUser,
  required int repeatCycle,
  required List<bool> weekdayFlags,
}) {
  final endDateStr = parseRepeatEndYmd(repeatEndIso);
  final cycle = math.max(1, repeatCycle);
  final duration = endUtc.difference(startUtc);

  final startSuffix = startUtc.toIso8601String();

  String toYmd(DateTime d) => _ymdLocal(d);

  DateTime toOccStart(DateTime d) =>
      _applyYmdWithSuffix(toYmd(d), startSuffix);

  DateTime toOccEnd(DateTime d) => toOccStart(d).add(duration);

  final ranges = <RepeatOccurrence>[];

  if (repeatUser == kRepeatUserWeek) {
    final startYmd = toYmd(startUtc);
    var weekIndex = 0;
    while (true) {
      final ref = startUtc.add(Duration(days: weekIndex * cycle * 7));
      final weekStart = sundayOfWeekLocal(ref);
      if (toYmd(weekStart).compareTo(endDateStr) > 0) break;
      for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
        if (!_weekdayFlag(weekdayFlags, dayOffset)) continue;
        final d = weekStart.add(Duration(days: dayOffset));
        final ymd = toYmd(d);
        if (ymd.compareTo(endDateStr) > 0) continue;
        if (ymd.compareTo(startYmd) < 0) continue;
        final occStart = toOccStart(d);
        ranges.add(RepeatOccurrence(startUtc: occStart, endUtc: toOccEnd(d)));
      }
      weekIndex++;
    }
  } else if (repeatUser == kRepeatUserMonth) {
    final sl = startUtc.toLocal();
    final dayOfWeekJs = sl.weekday % 7;
    final ord = ordinalFromDate(startUtc);
    final startYmd = toYmd(startUtc);
    var y = sl.year;
    var m0 = sl.month - 1;
    while (true) {
      final d = nthWeekdayInMonthJs(y, m0, dayOfWeekJs, ord);
      if (d == null) break;
      final ymd = toYmd(d);
      if (ymd.compareTo(endDateStr) > 0) break;
      if (ymd.compareTo(startYmd) >= 0) {
        ranges.add(
            RepeatOccurrence(startUtc: toOccStart(d), endUtc: toOccEnd(d)));
      }
      m0 += cycle;
      if (m0 > 11) {
        y += m0 ~/ 12;
        m0 = m0 % 12;
      }
    }
  }

  ranges.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  return ranges;
}

/// 웹 `shouldExpand` + 단일 행 fallback 없이 목록만 생성
List<RepeatOccurrence> computeRepeatOccurrences({
  required DateTime startUtc,
  required DateTime endUtc,
  required int? repeatId,
  required String? repeatEndIso,
  int? repeatCycle,
  int? repeatUser,
  List<bool>? weekdayFlags,
}) {
  if (repeatId == null || repeatEndIso == null || repeatEndIso.trim().isEmpty) {
    return [RepeatOccurrence(startUtc: startUtc, endUtc: endUtc)];
  }

  final rid = repeatId;
  final endIso = repeatEndIso.trim();

  final standard =
      [kRepeatDaily, kRepeatWeekly, kRepeatMonthly].contains(rid);
  final cycle = repeatCycle ?? 1;
  final ru = repeatUser;

  final custom = rid == kRepeatCustom &&
      ru != null &&
      (ru == kRepeatUserWeek || ru == kRepeatUserMonth);

  if (!standard && !custom) {
    return [RepeatOccurrence(startUtc: startUtc, endUtc: endUtc)];
  }

  if (custom) {
    final flags = weekdayFlags ??
        List<bool>.filled(7, false);
    return getCustomRepeatOccurrences(
      startUtc: startUtc,
      endUtc: endUtc,
      repeatEndIso: endIso,
      repeatUser: ru,
      repeatCycle: cycle,
      weekdayFlags: flags,
    );
  }

  return getStandardRepeatOccurrences(
    startUtc: startUtc,
    endUtc: endUtc,
    repeatId: rid,
    repeatEndIso: endIso,
    repeatCycle: cycle,
  );
}
