import 'package:flutter/material.dart';

/// 폼 안에 삽입하는 날짜·오전/오후·시(12h)·분(15분 단위) 휠 피커.
class InlineDateTimeWheelPicker extends StatefulWidget {
  const InlineDateTimeWheelPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final DateTime initial;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<InlineDateTimeWheelPicker> createState() =>
      _InlineDateTimeWheelPickerState();
}

class _InlineDateTimeWheelPickerState extends State<InlineDateTimeWheelPicker> {
  static const int _itemExtent = 40;
  static const List<int> _minuteSteps = [0, 15, 30, 45];

  List<DateTime> _dates = [];
  FixedExtentScrollController? _dateC;
  FixedExtentScrollController? _ampmC;
  FixedExtentScrollController? _hourC;
  FixedExtentScrollController? _minuteC;

  int _di = 0;
  int _ai = 0;
  int _hi = 0;
  int _mi = 0;

  @override
  void initState() {
    super.initState();
    _rebuildFrom(widget.initial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_compose());
    });
  }

  void _disposeControllers() {
    _dateC?.dispose();
    _ampmC?.dispose();
    _hourC?.dispose();
    _minuteC?.dispose();
    _dateC = null;
    _ampmC = null;
    _hourC = null;
    _minuteC = null;
  }

  void _rebuildFrom(DateTime initial) {
    _disposeControllers();

    final first = widget.firstDate ?? DateTime(2020, 1, 1);
    final last = widget.lastDate ?? DateTime(2100, 12, 31);
    _dates = _eachCalendarDay(first, last);

    final local = initial.toLocal();
    final minIdx = _nearestMinuteIndex(local.minute);
    var adjusted = DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      _minuteSteps[minIdx],
    );

    var di = _indexOfDate(adjusted);
    di = di.clamp(0, _dates.length - 1);
    final day = _dates[di];
    adjusted = DateTime(day.year, day.month, day.day, adjusted.hour, adjusted.minute);

    final parts = _to12h(adjusted);
    final mi = minIdx.clamp(0, _minuteSteps.length - 1);

    _di = di;
    _ai = parts.$1;
    _hi = parts.$2 - 1;
    _mi = mi;

    _dateC = FixedExtentScrollController(initialItem: _di);
    _ampmC = FixedExtentScrollController(initialItem: _ai);
    _hourC = FixedExtentScrollController(initialItem: _hi);
    _minuteC = FixedExtentScrollController(initialItem: _mi);
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  int _nearestMinuteIndex(int minute) {
    var best = 0;
    var bestDiff = 999;
    for (var i = 0; i < _minuteSteps.length; i++) {
      final d = (minute - _minuteSteps[i]).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return best;
  }

  static List<DateTime> _eachCalendarDay(DateTime first, DateTime last) {
    final out = <DateTime>[];
    var d = DateTime(first.year, first.month, first.day);
    final end = DateTime(last.year, last.month, last.day);
    while (!d.isAfter(end)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  int _indexOfDate(DateTime dt) {
    final t = DateTime(dt.year, dt.month, dt.day);
    final i = _dates.indexWhere(
      (e) => e.year == t.year && e.month == t.month && e.day == t.day,
    );
    return i >= 0 ? i : 0;
  }

  /// (ampm: 0 오전, 1 오후), hour12: 1..12
  (int, int) _to12h(DateTime dt) {
    final h = dt.hour;
    if (h == 0) return (0, 12);
    if (h < 12) return (0, h);
    if (h == 12) return (1, 12);
    return (1, h - 12);
  }

  int _to24h(int hour12, int ampm) {
    if (ampm == 0) {
      if (hour12 == 12) return 0;
      return hour12;
    }
    if (hour12 == 12) return 12;
    return hour12 + 12;
  }

  DateTime _compose() {
    final di = _di.clamp(0, _dates.length - 1);
    final day = _dates[di];
    final ampm = _ai.clamp(0, 1);
    final h12 = _hi.clamp(0, 11) + 1;
    final mix = _mi.clamp(0, _minuteSteps.length - 1);
    final h24 = _to24h(h12, ampm);
    final m = _minuteSteps[mix];
    return DateTime(day.year, day.month, day.day, h24, m);
  }

  void _notifyChanged() {
    widget.onChanged(_compose());
  }

  @override
  Widget build(BuildContext context) {
    final cDate = _dateC;
    final cAmpm = _ampmC;
    final cHour = _hourC;
    final cMin = _minuteC;
    if (_dates.isEmpty || cDate == null || cAmpm == null || cHour == null || cMin == null) {
      return const SizedBox(height: 120);
    }

    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final body = Theme.of(context).textTheme.bodyLarge;

    Widget wheel({
      required FixedExtentScrollController controller,
      required int itemCount,
      required ValueChanged<int> onPick,
      required Widget Function(int index) itemBuilder,
      int flex = 1,
    }) {
      return Expanded(
        flex: flex,
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _itemExtent.toDouble(),
          physics: const FixedExtentScrollPhysics(),
          perspective: 0.003,
          diameterRatio: 1.35,
          offAxisFraction: 0,
          onSelectedItemChanged: (i) {
            onPick(i);
            setState(() {});
            _notifyChanged();
          },
          overAndUnderCenterOpacity: 0.32,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) {
              if (index < 0 || index >= itemCount) return null;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: itemBuilder(index),
                ),
              );
            },
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: _itemExtent * 5 + 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: _itemExtent.toDouble(),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: accent.withValues(alpha: 0.45)),
                      bottom: BorderSide(color: accent.withValues(alpha: 0.45)),
                    ),
                    color: accent.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    wheel(
                      controller: cDate,
                      itemCount: _dates.length,
                      onPick: (i) => _di = i,
                      flex: 2,
                      itemBuilder: (i) {
                        final d = _dates[i];
                        final sel = _di == i;
                        return Text(
                          '${d.month}월 ${d.day}일(${_weekdayKo(d.weekday)})',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: body?.copyWith(
                            fontSize: 15,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel ? accent : scheme.onSurface,
                          ),
                        );
                      },
                    ),
                    wheel(
                      controller: cAmpm,
                      itemCount: 2,
                      onPick: (i) => _ai = i,
                      flex: 1,
                      itemBuilder: (i) {
                        final sel = _ai == i;
                        return Text(
                          i == 0 ? '오전' : '오후',
                          style: body?.copyWith(
                            fontSize: 15,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel ? accent : scheme.onSurface,
                          ),
                        );
                      },
                    ),
                    wheel(
                      controller: cHour,
                      itemCount: 12,
                      onPick: (i) => _hi = i,
                      itemBuilder: (i) {
                        final sel = _hi == i;
                        return Text(
                          '${i + 1}',
                          style: body?.copyWith(
                            fontSize: 16,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                            color: sel ? accent : scheme.onSurface,
                          ),
                        );
                      },
                    ),
                    wheel(
                      controller: cMin,
                      itemCount: _minuteSteps.length,
                      onPick: (i) => _mi = i,
                      itemBuilder: (i) {
                        final sel = _mi == i;
                        final m = _minuteSteps[i];
                        return Text(
                          m.toString().padLeft(2, '0'),
                          style: body?.copyWith(
                            fontSize: 16,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                            color: sel ? accent : scheme.onSurface,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _weekdayKo(int weekday) {
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    return names[(weekday - 1) % 7];
  }
}
