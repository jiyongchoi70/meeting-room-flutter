import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../data/datasources/reservation_remote_ds.dart';
import '../../../../data/models/calendar_event_model.dart';
import '../../../reservation_editor/presentation/pages/reservation_editor_page.dart';

enum CalendarTabType { month, week, day }

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _ds = ReservationRemoteDs();

  CalendarTabType _tab = CalendarTabType.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  bool _loading = true;
  String? _error;

  final List<CalendarEventModel> _events = [];
  final Map<String, List<CalendarEventModel>> _eventsByYmd = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadRangeForTab();
  }

  String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _loadRangeForTab() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      DateTime start;
      DateTime end;

      if (_tab == CalendarTabType.month) {
        start = DateTime(_focusedDay.year, _focusedDay.month, 1);
        end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
      } else if (_tab == CalendarTabType.week) {
        final weekday = _focusedDay.weekday % 7; // 일요일=0
        start = _dateOnly(_focusedDay.subtract(Duration(days: weekday)));
        end = start.add(const Duration(days: 6));
      } else {
        start = _dateOnly(_selectedDay ?? _focusedDay);
        end = start;
      }

      final list = await _ds.fetchCalendarEvents(
        startDate: _ymd(start),
        endDate: _ymd(end),
      );

      final grouped = <String, List<CalendarEventModel>>{};
      for (final e in list) {
        final key = _ymd(e.start.toLocal());
        grouped.putIfAbsent(key, () => []).add(e);
      }

      if (!mounted) return;
      setState(() {
        _events
          ..clear()
          ..addAll(list);
        _eventsByYmd
          ..clear()
          ..addAll(grouped);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '캘린더 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CalendarEventModel> _eventsForDay(DateTime day) {
    return _eventsByYmd[_ymd(day)] ?? const [];
  }

  Future<void> _openEditor(CalendarEventModel event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationEditorPage(event: event),
      ),
    );
    await _loadRangeForTab();
  }

  CalendarFormat _formatFromTab() {
    switch (_tab) {
      case CalendarTabType.month:
        return CalendarFormat.month;
      case CalendarTabType.week:
        return CalendarFormat.week;
      case CalendarTabType.day:
        return CalendarFormat.week; // day는 아래 리스트에서 하루만 보여줌
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsForDay(_selectedDay ?? _focusedDay);
    final visibleList = _tab == CalendarTabType.day
        ? dayEvents
        : (_selectedDay != null
            ? _eventsForDay(_selectedDay!)
            : const <CalendarEventModel>[]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('회의실 예약'),
        actions: [
          TextButton(
            onPressed: () async {
              // 로그아웃
            },
            child: const Text('로그아웃'),
          )
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SegmentedButton<CalendarTabType>(
                segments: const [
                  ButtonSegment(value: CalendarTabType.month, label: Text('월')),
                  ButtonSegment(value: CalendarTabType.week, label: Text('주')),
                  ButtonSegment(value: CalendarTabType.day, label: Text('일')),
                ],
                selected: {_tab},
                onSelectionChanged: (v) async {
                  setState(() => _tab = v.first);
                  await _loadRangeForTab();
                },
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          TableCalendar<CalendarEventModel>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            locale: 'ko_KR',
            calendarFormat: _formatFromTab(),
            availableCalendarFormats: const {
              CalendarFormat.month: '월',
              CalendarFormat.week: '주',
              CalendarFormat.twoWeeks: '2주',
            },
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            eventLoader: _eventsForDay,
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) async {
              _focusedDay = focused;
              await _loadRangeForTab();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: visibleList.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = visibleList[i];
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text(
                    '${DateFormat('yyyy-MM-dd HH:mm').format(e.start.toLocal())} ~ '
                    '${DateFormat('HH:mm').format(e.end.toLocal())}\n${e.roomName}',
                  ),
                  isThreeLine: true,
                  onTap: () => _openEditor(e),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
