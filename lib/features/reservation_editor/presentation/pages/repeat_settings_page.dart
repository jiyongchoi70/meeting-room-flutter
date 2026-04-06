import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../data/datasources/reservation_remote_ds.dart';
import '../models/repeat_schedule_selection.dart';

/// 반복 유형 라디오 (lookup 160: 110·120·130·140)
class RepeatSettingsPage extends StatefulWidget {
  const RepeatSettingsPage({
    super.key,
    required this.reservationStart,
    required this.reservationEnd,
    this.initial,
  });

  final DateTime reservationStart;
  final DateTime reservationEnd;
  final RepeatScheduleSelection? initial;

  @override
  State<RepeatSettingsPage> createState() => _RepeatSettingsPageState();
}

class _RepeatSettingsPageState extends State<RepeatSettingsPage> {
  final _ds = ReservationRemoteDs();
  static const _green = Color(0xFF1B5E20);
  static final _untilDisplay = DateFormat('M월 d일', 'ko_KR');

  late RepeatScheduleSelection _sel;
  Map<int, String> _lookupLabels = {};
  bool _loadingLookup = true;

  /// 종료일 인라인 달력 펼침 (pop-up 대신 본문 삽입)
  bool _untilCalendarExpanded = false;

  static const _radioCodes = [110, 120, 130, 140];

  @override
  void initState() {
    super.initState();
    _sel = widget.initial ??
        RepeatScheduleSelection.initial(
          reservationStart: widget.reservationStart,
          reservationEnd: widget.reservationEnd,
        );
    _loadLookup();
  }

  Future<void> _loadLookup() async {
    try {
      final m = await _ds.fetchRepeatScheduleLookupLabels();
      if (mounted) setState(() => _lookupLabels = m);
    } catch (_) {
      if (mounted) {
        setState(() => _lookupLabels = ReservationRemoteDs.kFallbackRepeatLabels);
      }
    } finally {
      if (mounted) setState(() => _loadingLookup = false);
    }
  }

  String _labelForCode(int code) =>
      _lookupLabels[code] ?? ReservationRemoteDs.kFallbackRepeatLabels[code] ?? '';

  RepeatUiMode _modeForRadio(int code) {
    switch (code) {
      case 110:
        return RepeatUiMode.none;
      case 120:
        return RepeatUiMode.daily;
      case 130:
        return RepeatUiMode.weekly;
      case 140:
        return RepeatUiMode.monthlyByDate;
      default:
        return RepeatUiMode.none;
    }
  }

  int _radioForMode(RepeatUiMode m) {
    switch (m) {
      case RepeatUiMode.none:
        return 110;
      case RepeatUiMode.daily:
        return 120;
      case RepeatUiMode.weekly:
        return 130;
      case RepeatUiMode.monthlyByDate:
      case RepeatUiMode.monthlyByWeekday:
        return 140;
    }
  }

  void _setModeFromRadio(int code) {
    setState(() {
      if (code == 140) {
        final wasMonthly = _sel.mode == RepeatUiMode.monthlyByDate ||
            _sel.mode == RepeatUiMode.monthlyByWeekday;
        final sub = wasMonthly && _sel.mode == RepeatUiMode.monthlyByWeekday
            ? RepeatUiMode.monthlyByWeekday
            : RepeatUiMode.monthlyByDate;
        _sel = _sel.copyWith(mode: sub);
      } else {
        _sel = _sel.copyWith(mode: _modeForRadio(code));
        if (_modeForRadio(code) == RepeatUiMode.none) {
          _untilCalendarExpanded = false;
        }
      }
    });
  }

  DateTime get _firstUntilDate {
    final a = DateTime(
      widget.reservationStart.year,
      widget.reservationStart.month,
      widget.reservationStart.day,
    );
    final b = DateTime(
      widget.reservationEnd.year,
      widget.reservationEnd.month,
      widget.reservationEnd.day,
    );
    return a.isAfter(b) ? a : b;
  }

  void _toggleUntilCalendar() {
    setState(() {
      _untilCalendarExpanded = !_untilCalendarExpanded;
    });
  }

  void _onUntilDateChanged(DateTime picked) {
    final first = _firstUntilDate;
    var next = DateTime(picked.year, picked.month, picked.day);
    if (next.isBefore(first)) next = first;
    setState(() {
      _sel = _sel.copyWith(repeatUntil: next);
    });
  }

  DateTime get _effectiveUntilDate {
    final first = _firstUntilDate;
    final u = _sel.repeatUntil;
    final d = DateTime(u.year, u.month, u.day);
    return d.isBefore(first) ? first : d;
  }

  /// 매주 요일 칩 라벨: 일=빨강, 토=파랑, 그 외는 선택 시 녹색
  Color _weekdayChipLabelColor(BuildContext context, int index, bool selected) {
    if (index == 0) return const Color(0xFFC62828);
    if (index == 6) return const Color(0xFF1565C0);
    return selected ? _green : Theme.of(context).colorScheme.onSurfaceVariant;
  }

  void _popWithResult() {
    if (_sel.mode == RepeatUiMode.weekly) {
      final any = _sel.weekdayFlags.any((e) => e);
      if (!any) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('요일을 하나 이상 선택해주세요.')),
        );
        return;
      }
    }
    if (_sel.mode == RepeatUiMode.daily && _sel.dailyInterval < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('간격은 1 이상이어야 합니다.')),
      );
      return;
    }
    if (_sel.mode == RepeatUiMode.weekly && _sel.weeklyInterval < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('주 간격은 1 이상이어야 합니다.')),
      );
      return;
    }
    Navigator.pop(context, _sel);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radioGroup = _radioForMode(_sel.mode);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _popWithResult,
        ),
        title: const Text(
          '반복',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loadingLookup)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          const SizedBox(height: 8),
          Text(
            _sel.statusMessage(reservationStart: widget.reservationStart),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          ..._radioCodes.map((code) {
            return RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              value: code,
              groupValue: radioGroup,
              onChanged: _loadingLookup ? null : (v) => _setModeFromRadio(code),
              title: Text(_labelForCode(code)),
            );
          }),
          if (_sel.mode == RepeatUiMode.daily) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    initialValue: '${_sel.dailyInterval}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (s) {
                      final n = int.tryParse(s) ?? 1;
                      setState(() {
                        _sel = _sel.copyWith(dailyInterval: n.clamp(1, 366));
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '일마다',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _green,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ],
          if (_sel.mode == RepeatUiMode.weekly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextFormField(
                    initialValue: '${_sel.weeklyInterval}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onChanged: (s) {
                      final n = int.tryParse(s) ?? 1;
                      setState(() {
                        _sel = _sel.copyWith(weeklyInterval: n.clamp(1, 52));
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '주마다',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _green,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final on = i < _sel.weekdayFlags.length && _sel.weekdayFlags[i];
                final labels = ['일', '월', '화', '수', '목', '금', '토'];
                return FilterChip(
                  showCheckmark: false,
                  label: Text(labels[i]),
                  selected: on,
                  onSelected: (_) {
                    setState(() {
                      final next = List<bool>.from(_sel.weekdayFlags);
                      if (next.length != 7) {
                        next.clear();
                        next.addAll(List<bool>.filled(7, false));
                      }
                      next[i] = !next[i];
                      _sel = _sel.copyWith(weekdayFlags: next);
                    });
                  },
                  selectedColor: scheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: _weekdayChipLabelColor(context, i, on),
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  ),
                );
              }),
            ),
          ],
          if (_sel.mode == RepeatUiMode.monthlyByDate ||
              _sel.mode == RepeatUiMode.monthlyByWeekday) ...[
            const SizedBox(height: 12),
            Text('매월 반복 방식', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(
                    '${widget.reservationStart.day}일 마다 반복',
                  ),
                  selected: _sel.mode == RepeatUiMode.monthlyByDate,
                  onSelected: (_) {
                    setState(() {
                      _sel = _sel.copyWith(mode: RepeatUiMode.monthlyByDate);
                    });
                  },
                ),
                ChoiceChip(
                  label: Text(
                    '${RepeatScheduleSelection.monthlyNthPillLabel(widget.reservationStart)} 마다 반복',
                  ),
                  selected: _sel.mode == RepeatUiMode.monthlyByWeekday,
                  onSelected: (_) {
                    setState(() {
                      _sel = _sel.copyWith(mode: RepeatUiMode.monthlyByWeekday);
                    });
                  },
                ),
              ],
            ),
          ],
          if (_sel.mode != RepeatUiMode.none) ...[
            const SizedBox(height: 24),
            Text('기간', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('종료일'),
              subtitle: Text(
                '${_untilDisplay.format(_sel.repeatUntil)} 까지',
              ),
              trailing: Icon(
                _untilCalendarExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 22,
              ),
              onTap: _toggleUntilCalendar,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _untilCalendarExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _RepeatUntilInlineCalendar(
                        key: ValueKey<String>(
                          '${_effectiveUntilDate.year}-${_effectiveUntilDate.month}-${_effectiveUntilDate.day}',
                        ),
                        firstDate: _firstUntilDate,
                        selectedDate: _effectiveUntilDate,
                        onDateChanged: _onUntilDateChanged,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 반복 종료일 전용 인라인 달력 (`회의실 예약` 하루 종일 달력과 동일 패턴)
class _RepeatUntilInlineCalendar extends StatelessWidget {
  const _RepeatUntilInlineCalendar({
    super.key,
    required this.firstDate,
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime firstDate;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  static final _lastDate = DateTime(2100, 12, 31);

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
        firstDate: firstDate,
        lastDate: _lastDate,
        onDateChanged: onDateChanged,
      ),
    );
  }
}
