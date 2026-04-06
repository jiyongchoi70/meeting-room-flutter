import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../app/router.dart';
import '../../../../data/datasources/reservation_remote_ds.dart';
import '../../../../data/models/calendar_event_model.dart';
import '../../../reservation_editor/presentation/pages/reservation_create_page.dart';
import '../../../reservation_editor/presentation/pages/reservation_editor_page.dart';
import '../widgets/reservation_status_chip.dart';
import '../widgets/room_name_filter.dart';

/// 바디·달력 연·월(주·월) 헤더·일 뷰 날짜 네비 스트립 공통 배경
const Color _kPageBackground = Color(0xFFF5F7FA);

enum CalendarTabType { month, week, day }

/// 선택된 [day]의 로컬 자정 (날짜만 의미할 때도 동일한 기준으로 맞춤).
DateTime _localMidnight(DateTime day) {
  final l = day.toLocal();
  return DateTime(l.year, l.month, l.day);
}

bool _isSameLocalCalendarDay(DateTime a, DateTime b) {
  return _localMidnight(a) == _localMidnight(b);
}

/// [a]가 [b]보다 몇 분 뒤인지 (소수 분 — `inMinutes` 내림 오차 방지).
double _minutesAfter(DateTime a, DateTime b) {
  return a.difference(b).inMicroseconds / 1e6 / 60.0;
}

Color _weekendColor(DateTime date, {required Color weekdayColor}) {
  if (date.weekday == DateTime.sunday) return Colors.red.shade600;
  if (date.weekday == DateTime.saturday) return Colors.blue.shade600;
  return weekdayColor;
}

/// 목록·타임라인 취소선: **종료 시각**이 현재보다 이전이거나 같을 때만.
/// (시작 시각 기준이 아님 — 회의 진행 중에는 취소선 없음)
bool _isReservationPast(CalendarEventModel event) {
  final now = DateTime.now();
  return !event.end.isAfter(now);
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _ds = ReservationRemoteDs();

  /// null이면 전체 회의실
  String? _filterRoomId;

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
        // 월 보기에서는 달력에 함께 보이는 바깥달(앞/뒤) 날짜도 같이 조회.
        final firstOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
        final lastOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
        final leadingDays = firstOfMonth.weekday % 7; // 일요일 시작 기준
        final trailingDays = 6 - (lastOfMonth.weekday % 7);
        start = _dateOnly(firstOfMonth.subtract(Duration(days: leadingDays)));
        end = _dateOnly(lastOfMonth.add(Duration(days: trailingDays)));
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
        roomId: _filterRoomId,
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
        return CalendarFormat.week;
    }
  }

  Future<void> _shiftSelectedDay(int deltaDays) async {
    final base = _selectedDay ?? _focusedDay;
    final next = _dateOnly(base).add(Duration(days: deltaDays));
    setState(() {
      _selectedDay = next;
      _focusedDay = next;
    });
    await _loadRangeForTab();
  }

  Future<void> _goToToday() async {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _selectedDay = today;
      _focusedDay = today;
    });
    await _loadRangeForTab();
  }

  Future<void> _onAddReservationPressed() async {
    final seedDay = _selectedDay ?? _focusedDay;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationCreatePage(
          initialDay: seedDay,
          initialRoomId: _filterRoomId,
        ),
      ),
    );
    if (!mounted) return;
    await _loadRangeForTab();
  }

  Color _dowColor(DateTime date) {
    if (date.weekday == DateTime.sunday) return Colors.red.shade600;
    if (date.weekday == DateTime.saturday) return Colors.blue.shade600;
    return Colors.grey.shade800;
  }

  Color _dayNumberColor(DateTime date, {required bool outside}) {
    if (outside) {
      if (date.weekday == DateTime.sunday) return Colors.red.shade200;
      if (date.weekday == DateTime.saturday) return Colors.blue.shade200;
      return Colors.grey.shade400;
    }
    if (date.weekday == DateTime.sunday) return Colors.red.shade600;
    if (date.weekday == DateTime.saturday) return Colors.blue.shade600;
    return Colors.grey.shade800;
  }

  /// 월 보기는 6행 달력 고정 높이로 본문 Column이 넘칠 수 있어, `Expanded` + `shouldFillViewport`로
  /// 남은 세로 공간 안에 맞춘다. 주 보기는 기존처럼 자연 높이.
  Widget _buildTableCalendar({required bool fillViewport}) {
    return TableCalendar<CalendarEventModel>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2035, 12, 31),
      focusedDay: _focusedDay,
      locale: 'ko_KR',
      shouldFillViewport: fillViewport,
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
        decoration: BoxDecoration(color: _kPageBackground),
      ),
      daysOfWeekHeight: 27,
      rowHeight: 46,
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(
          color: Colors.grey.shade800,
          fontSize: 13,
          height: 1.25,
          fontWeight: FontWeight.bold,
        ),
      ),
      calendarBuilders: CalendarBuilders(
        dowBuilder: (context, day) {
          final text = DateFormat.E('ko_KR').format(day);
          return Center(
            child: Text(
              text,
              style: TextStyle(
                color: _dowColor(day),
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
        defaultBuilder: (context, day, focusedDay) {
          return Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: _dayNumberColor(day, outside: false),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
        outsideBuilder: (context, day, focusedDay) {
          return Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: _dayNumberColor(day, outside: true),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        },
      ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedDay ?? _focusedDay;
    final dayEvents = _eventsForDay(selected);
    final visibleList = _tab == CalendarTabType.day
        ? dayEvents
        : (_selectedDay != null
            ? _eventsForDay(_selectedDay!)
            : const <CalendarEventModel>[]);

    return Scaffold(
      backgroundColor: _kPageBackground,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 8),
        child: FloatingActionButton(
          onPressed: _onAddReservationPressed,
          backgroundColor: const Color(0xFF11B497),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          elevation: 4,
          child: const Icon(Icons.add, size: 32),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '회의실 예약',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Supabase.instance.client.auth.signOut();
                if (!context.mounted) return;
                context.go(AppRouter.login);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('로그아웃 실패: $e')),
                );
              }
            },
            child: const Text('로그아웃'),
          )
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RoomNameFilter(
                  onChanged: (id) {
                    setState(() => _filterRoomId = id);
                    _loadRangeForTab();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SegmentedButton<CalendarTabType>(
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        side: WidgetStatePropertyAll(
                          BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: CalendarTabType.month,
                          label: Text('월'),
                        ),
                        ButtonSegment(
                          value: CalendarTabType.week,
                          label: Text('주'),
                        ),
                        ButtonSegment(
                          value: CalendarTabType.day,
                          label: Text('일'),
                        ),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (v) async {
                        setState(() => _tab = v.first);
                        await _loadRangeForTab();
                      },
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: _loading ? null : () => _goToToday(),
                      icon: const Icon(Icons.today),
                      tooltip: '오늘',
                      style: IconButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.primary,
                        side: BorderSide(
                          color: scheme.primary.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_tab == CalendarTabType.day) ...[
            Container(
              width: double.infinity,
              color: _kPageBackground,
              child: _DayNavigatorBar(
                day: selected,
                onPrev: () => _shiftSelectedDay(-1),
                onNext: () => _shiftSelectedDay(1),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _DayScheduleTimeline(
                day: selected,
                events: dayEvents,
                onEventTap: _openEditor,
              ),
            ),
          ] else ...[
            if (_tab == CalendarTabType.month)
              Expanded(
                flex: 3,
                child: _buildTableCalendar(fillViewport: true),
              )
            else
              _buildTableCalendar(fillViewport: false),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(
              flex: _tab == CalendarTabType.month ? 2 : 1,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
                itemCount: visibleList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final e = visibleList[i];
                  return _EventListCard(
                    event: e,
                    onTap: () => _openEditor(e),
                  );
                },
              ),
            ),
          ],
        ],
            ),
          ),
          if (_loading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }
}

class _EventListCard extends StatelessWidget {
  const _EventListCard({
    required this.event,
    required this.onTap,
  });

  final CalendarEventModel event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final past = _isReservationPast(event);
    final titleColor =
        Theme.of(context).textTheme.titleMedium?.color ?? Colors.black87;
    final detailColor = Colors.blueGrey.shade700;
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        decoration:
                            past ? TextDecoration.lineThrough : TextDecoration.none,
                        decorationColor: past ? titleColor : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ReservationStatusChip(status: event.status),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.blueGrey.shade500),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('HH:mm').format(event.start.toLocal())} ~ '
                    '${DateFormat('HH:mm').format(event.end.toLocal())}',
                    style: TextStyle(
                      color: detailColor,
                      decoration:
                          past ? TextDecoration.lineThrough : TextDecoration.none,
                      decorationColor: past ? detailColor : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.meeting_room_outlined,
                      size: 16, color: Colors.blueGrey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      event.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: detailColor,
                        decoration:
                            past ? TextDecoration.lineThrough : TextDecoration.none,
                        decorationColor: past ? detailColor : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayNavigatorBar extends StatelessWidget {
  const _DayNavigatorBar({
    required this.day,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime day;
  final Future<void> Function() onPrev;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final title = DateFormat.yMMMMEEEEd('ko_KR').format(day);
    final defaultColor =
        Theme.of(context).textTheme.titleMedium?.color ?? Colors.black87;
    return Padding(
      // TableCalendar HeaderStyle.headerPadding(세로 8)에 맞춤
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onPrev(),
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 날',
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _weekendColor(day, weekdayColor: defaultColor),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          IconButton(
            onPressed: () => onNext(),
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 날',
          ),
        ],
      ),
    );
  }
}

class _DayScheduleTimeline extends StatefulWidget {
  static const double _hourHeight = 52;
  static const double _pxPerMinute = _hourHeight / 60.0;
  static const double _totalHeight = 24 * _hourHeight;

  const _DayScheduleTimeline({
    required this.day,
    required this.events,
    required this.onEventTap,
  });

  final DateTime day;
  final List<CalendarEventModel> events;
  final Future<void> Function(CalendarEventModel) onEventTap;

  @override
  State<_DayScheduleTimeline> createState() => _DayScheduleTimelineState();
}

class _DayScheduleTimelineState extends State<_DayScheduleTimeline> {
  static const double _nowLineHeight = 3;
  /// `ScrollController` 미부착 시 post-frame을 무한 반복하지 않도록 상한 (웹 엔진 단언 루프 방지).
  static const int _maxScrollToNowAttempts = 40;

  Timer? _clockTimer;
  final ScrollController _scroll = ScrollController();
  int _scrollToNowAttempts = 0;

  @override
  void initState() {
    super.initState();
    _scrollToNowAttempts = 0;
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNowIfNeeded());
  }

  @override
  void didUpdateWidget(covariant _DayScheduleTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameLocalCalendarDay(widget.day, oldWidget.day)) {
      _scrollToNowAttempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNowIfNeeded());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToNowIfNeeded() {
    if (!mounted || !_isSameLocalCalendarDay(widget.day, DateTime.now())) {
      _scrollToNowAttempts = 0;
      return;
    }
    if (!_scroll.hasClients) {
      if (_scrollToNowAttempts >= _maxScrollToNowAttempts) return;
      _scrollToNowAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNowIfNeeded());
      return;
    }
    _scrollToNowAttempts = 0;
    final dayStart = _localMidnight(widget.day);
    final mins = _minutesAfter(DateTime.now(), dayStart);
    if (mins < 0 || mins >= 24 * 60) return;
    final topPx =
        (mins * _DayScheduleTimeline._pxPerMinute).clamp(0.0, _DayScheduleTimeline._totalHeight);
    final vp = _scroll.position.viewportDimension;
    final maxExt = _scroll.position.maxScrollExtent;
    final target = (topPx - vp * 0.35).clamp(0.0, maxExt);
    _scroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor.withValues(alpha: 0.55);
    final dayStart = _localMidnight(widget.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final sortedEvents = List<CalendarEventModel>.from(widget.events)
      ..sort((a, b) => a.start.compareTo(b.start));
    final placed = _layoutTimelinePlacements(
      sortedEvents,
      dayStart,
      dayEnd,
      _DayScheduleTimeline._pxPerMinute,
    );

    double? nowLineTop;
    if (_isSameLocalCalendarDay(widget.day, DateTime.now())) {
      final mins = _minutesAfter(DateTime.now(), dayStart);
      if (mins >= 0 && mins < 24 * 60) {
        final y = mins * _DayScheduleTimeline._pxPerMinute;
        nowLineTop = (y - _nowLineHeight / 2)
            .clamp(0.0, _DayScheduleTimeline._totalHeight - _nowLineHeight);
      }
    }

    return SingleChildScrollView(
      controller: _scroll,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: SizedBox(
          height: _DayScheduleTimeline._totalHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: divider),
                      ),
                    ),
                    child: SizedBox(
                      width: 48,
                      child: Column(
                        children: List.generate(24, (h) {
                          return SizedBox(
                            height: _DayScheduleTimeline._hourHeight,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(
                                  '${h.toString().padLeft(2, '0')}:00',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).hintColor,
                                      ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final trackW = math.max(0.0, constraints.maxWidth - 12);
                        const laneGap = 2.0;

                        return Stack(
                          children: [
                            ...List.generate(24, (h) {
                              return Positioned(
                                top: h * _DayScheduleTimeline._hourHeight,
                                left: 0,
                                right: 0,
                                height: _DayScheduleTimeline._hourHeight,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: divider),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            if (placed.isEmpty)
                              Positioned.fill(
                                child: Center(
                                  child: Text(
                                    '이 날 예약이 없습니다',
                                    style:
                                        TextStyle(color: Theme.of(context).hintColor),
                                  ),
                                ),
                              )
                            else
                              ...placed.map((p) {
                                final n = math.max(1, p.laneCount);
                                final segW =
                                    (trackW - laneGap * (n - 1)).clamp(0, trackW) / n;
                                final left = 4 + p.lane * (segW + laneGap);

                                return Positioned(
                                  top: p.topPx,
                                  left: left,
                                  width: segW,
                                  height: p.heightPx,
                                  child: Material(
                                    color: scheme.primaryContainer,
                                    elevation: 0,
                                    borderRadius: BorderRadius.circular(8),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => widget.onEventTap(p.event),
                                      child: ClipRect(
                                        child: SizedBox(
                                          height: p.heightPx,
                                          width: segW,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: math
                                                  .min(8.0, segW * 0.12)
                                                  .clamp(4.0, 8.0)
                                                  .toDouble(),
                                              vertical:
                                                  p.heightPx >= 44 ? 5 : 3,
                                            ),
                                            child: _TimelineEventLabel(
                                              event: p.event,
                                              scheme: scheme,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (nowLineTop != null)
                Positioned(
                  left: 48,
                  right: 0,
                  top: nowLineTop,
                  height: _nowLineHeight,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 타임라인 블록 높이(1시간≈52px 등) 안에서 텍스트가 넘치지 않도록 줄 수·글자 크기를 맞춤.
class _TimelineEventLabel extends StatelessWidget {
  const _TimelineEventLabel({
    required this.event,
    required this.scheme,
  });

  final CalendarEventModel event;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth <= 0 || c.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final past = _isReservationPast(event);
        final fg = scheme.onPrimaryContainer;
        return Align(
          alignment: Alignment.topLeft,
          child: Text(
            '${event.title}\n${event.roomName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: fg,
              decoration:
                  past ? TextDecoration.lineThrough : TextDecoration.none,
              decorationColor: past ? fg : null,
            ),
          ),
        );
      },
    );
  }
}

class _PlacedTimelineEvent {
  _PlacedTimelineEvent({
    required this.event,
    required this.topPx,
    required this.heightPx,
    required this.startMin,
    required this.endMin,
    this.lane = 0,
    this.laneCount = 1,
  });

  final CalendarEventModel event;
  final double topPx;
  final double heightPx;
  final double startMin;
  final double endMin;
  int lane;
  int laneCount;
}

List<_PlacedTimelineEvent> _layoutTimelinePlacements(
  List<CalendarEventModel> sorted,
  DateTime dayStart,
  DateTime dayEnd,
  double pxPerMinute,
) {
  const eps = 1e-6;
  final raw = <_PlacedTimelineEvent>[];

  for (final e in sorted) {
    final start = e.start.toLocal();
    final end = e.end.toLocal();
    final clipStart = start.isBefore(dayStart) ? dayStart : start;
    final clipEnd = end.isAfter(dayEnd) ? dayEnd : end;
    if (!clipStart.isBefore(clipEnd)) {
      continue;
    }
    final startMin = _minutesAfter(clipStart, dayStart);
    final endMin = _minutesAfter(clipEnd, dayStart);
    final durMin = endMin - startMin;
    final heightPx = durMin * pxPerMinute;
    if (heightPx < 0.5) {
      continue;
    }
    final topPx = startMin * pxPerMinute;
    raw.add(
      _PlacedTimelineEvent(
        event: e,
        topPx: topPx,
        heightPx: heightPx,
        startMin: startMin,
        endMin: endMin,
        lane: 0,
        laneCount: 1,
      ),
    );
  }

  raw.sort((a, b) => a.startMin.compareTo(b.startMin));
  final laneEnds = <double>[];

  for (final p in raw) {
    var lane = -1;
    for (var i = 0; i < laneEnds.length; i++) {
      if (laneEnds[i] <= p.startMin + eps) {
        lane = i;
        laneEnds[i] = p.endMin;
        break;
      }
    }
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(p.endMin);
    }
    p.lane = lane;
  }

  final laneCount = laneEnds.isEmpty ? 1 : laneEnds.length;
  for (final p in raw) {
    p.laneCount = laneCount;
  }

  return raw;
}
