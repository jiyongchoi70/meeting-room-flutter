import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/user_facing_error_message.dart';
import '../../../../data/datasources/room_remote_ds.dart';
import '../../../../data/datasources/reservation_remote_ds.dart';
import '../../../../data/models/meeting_room_model.dart';
import '../models/repeat_schedule_selection.dart';
import '../widgets/inline_datetime_wheel_picker.dart';
import '../widgets/meeting_room_card_styles.dart';
import 'repeat_settings_page.dart';

enum _ExpandedPicker { none, start, end }

/// 시간/하루종일·반복·취소/저장 등 폼 하단 액션과 동일한 터치 영역 높이.
const double _kFormBarButtonHeight = 48;

class ReservationCreatePage extends StatefulWidget {
  const ReservationCreatePage({
    super.key,
    required this.initialDay,
    this.initialRoomId,
  });

  final DateTime initialDay;
  final String? initialRoomId;

  @override
  State<ReservationCreatePage> createState() => _ReservationCreatePageState();
}

class _ReservationCreatePageState extends State<ReservationCreatePage> {
  final _ds = ReservationRemoteDs();
  final _roomDs = RoomRemoteDs();
  static final _displayFmtDate = DateFormat('M월 d일(E)', 'ko_KR');
  static final _displayFmtTime = DateFormat('a h:mm', 'ko_KR');

  late final TextEditingController _titleCtrl;
  late DateTime _start;
  late DateTime _end;

  bool _saving = false;
  bool _allDay = false;
  _ExpandedPicker _expanded = _ExpandedPicker.none;
  int _startPickerCounter = 0;
  int _endPickerCounter = 0;
  int _startDayPickerKey = 0;
  int _endDayPickerKey = 0;
  bool _loadingRooms = true;
  List<MeetingRoom> _rooms = const [];
  String? _selectedRoomId;

  late RepeatScheduleSelection _repeatSel;

  bool get _canEditDateTime => !_allDay;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 시작·종료가 서로 다른 날이면 반복 UI 비표시 (멀티데이 예약은 반복 불가)
  bool get _canConfigureRepeat =>
      _dateOnly(_start) == _dateOnly(_end);

  void _clearRepeatIfSpanningDays() {
    if (!_canConfigureRepeat) {
      _repeatSel = RepeatScheduleSelection.initial(
        reservationStart: _start,
        reservationEnd: _end,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    final day = widget.initialDay.toLocal();
    final roundedNow = _roundUpToNext30(DateTime.now().toLocal());
    _start = DateTime(
      day.year,
      day.month,
      day.day,
      roundedNow.hour,
      roundedNow.minute,
    );
    _end = _start.add(const Duration(hours: 1));
    _repeatSel = RepeatScheduleSelection.initial(
      reservationStart: _start,
      reservationEnd: _end,
    );
    _selectedRoomId = null; // 기본값: 선택
    _loadRooms();
  }

  void _clampRepeatUntilToEnd() {
    final endDay = _dateOnly(_end);
    if (_repeatSel.repeatUntil.isBefore(endDay)) {
      _repeatSel = _repeatSel.copyWith(repeatUntil: endDay);
    }
  }

  DateTime _roundUpToNext30(DateTime now) {
    final m = now.minute;
    final add = (30 - (m % 30)) % 30;
    final base = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final rounded = base.add(Duration(minutes: add));
    return DateTime(
      rounded.year,
      rounded.month,
      rounded.day,
      rounded.hour,
      rounded.minute,
    );
  }

  Future<void> _loadRooms() async {
    setState(() => _loadingRooms = true);
    try {
      final rooms = await _roomDs.fetchRoomsForReservation();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _rooms = const []);
    } finally {
      if (mounted) setState(() => _loadingRooms = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _scheduleDisplayText(DateTime dt) {
    if (_allDay) return _displayFmtDate.format(dt);
    return '${_displayFmtDate.format(dt)} ${_displayFmtTime.format(dt)}';
  }

  void _applyStart(DateTime v) {
    setState(() {
      _start = v;
      if (!_end.isAfter(_start)) _end = _start.add(const Duration(minutes: 30));
      _clampRepeatUntilToEnd();
      _clearRepeatIfSpanningDays();
    });
  }

  void _onEndWheelChanged(DateTime v) {
    setState(() {
      _end = v.isAfter(_start) ? v : _start.add(const Duration(minutes: 30));
      _clampRepeatUntilToEnd();
      _clearRepeatIfSpanningDays();
    });
  }

  Future<void> _openRepeatSettings() async {
    final result = await Navigator.push<RepeatScheduleSelection>(
      context,
      MaterialPageRoute(
        builder: (ctx) => RepeatSettingsPage(
          reservationStart: _start,
          reservationEnd: _end,
          initial: _repeatSel,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _repeatSel = result);
    }
  }

  void _toggleStartPicker() {
    if (_saving) return;
    if (_allDay) {
      setState(() {
        _expanded =
            _expanded == _ExpandedPicker.start ? _ExpandedPicker.none : _ExpandedPicker.start;
        _startDayPickerKey++;
      });
      return;
    }
    setState(() {
      if (_expanded == _ExpandedPicker.start) {
        _expanded = _ExpandedPicker.none;
      } else {
        _expanded = _ExpandedPicker.start;
        _startPickerCounter++;
      }
    });
  }

  void _toggleEndPicker() {
    if (_saving) return;
    if (_allDay) {
      setState(() {
        _expanded = _expanded == _ExpandedPicker.end ? _ExpandedPicker.none : _ExpandedPicker.end;
        _endDayPickerKey++;
      });
      return;
    }
    setState(() {
      if (_expanded == _ExpandedPicker.end) {
        _expanded = _ExpandedPicker.none;
      } else {
        _expanded = _ExpandedPicker.end;
        _endPickerCounter++;
      }
    });
  }

  void _setAllDay(bool allDay) {
    setState(() {
      _allDay = allDay;
      _expanded = _ExpandedPicker.none;
    });
  }

  void _applyAllDayStartCalendar(DateTime picked) {
    setState(() {
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
      final dStart = DateTime(_start.year, _start.month, _start.day);
      final dEnd = DateTime(_end.year, _end.month, _end.day);
      if (dEnd.isBefore(dStart)) {
        _end = DateTime(_start.year, _start.month, _start.day, _end.hour, _end.minute);
      }
      _clampRepeatUntilToEnd();
      _clearRepeatIfSpanningDays();
    });
  }

  Future<void> _unfocusKeyboardBeforePop() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future<void>.delayed(const Duration(milliseconds: 64));
  }

  void _applyAllDayEndCalendar(DateTime picked) {
    setState(() {
      _end = DateTime(picked.year, picked.month, picked.day, _end.hour, _end.minute);
      final dStart = DateTime(_start.year, _start.month, _start.day);
      final dEnd = DateTime(_end.year, _end.month, _end.day);
      if (dEnd.isBefore(dStart)) {
        _start = DateTime(_end.year, _end.month, _end.day, _start.hour, _start.minute);
      }
      _clampRepeatUntilToEnd();
      _clearRepeatIfSpanningDays();
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목은 필수 입력입니다.')),
      );
      return;
    }
    final selectedRoomId = _selectedRoomId;
    if (selectedRoomId == null || selectedRoomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회의실을 선택해주세요.')),
      );
      return;
    }

    if (_canConfigureRepeat && _repeatSel.isRepeating) {
      final endDay = _dateOnly(_end);
      if (_repeatSel.repeatUntil.isBefore(endDay)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반복 종료일은 종료 일시 이후 날짜여야 합니다.')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'title': title,
        'allday_yn': _allDay ? 'Y' : 'N',
        'start_ymd': _start.toUtc().toIso8601String(),
        'end_ymd': _end.toUtc().toIso8601String(),
      };
      if (_canConfigureRepeat) {
        payload.addAll(_repeatSel.repeatFieldsForPayload());
      }

      await _ds.createReservation(
        roomId: selectedRoomId,
        payload: payload,
      );
      if (!mounted) return;
      await _unfocusKeyboardBeforePop();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: ${userFacingErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _scheduleRow({
    required BuildContext context,
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(_scheduleDisplayText(value), style: style),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // 웹 등에서 기본 BackButton 옆에 "뒤로" 텍스트가 따로 붙는 것을 막고 아이콘만 표시
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.maybePop(context),
        ),
        automaticallyImplyLeading: false,
        title: const Text(
          '회의실 예약',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              _scheduleRow(
                context: context,
                label: '시작',
                value: _start,
                onTap: _toggleStartPicker,
              ),
              if (_canEditDateTime && _expanded == _ExpandedPicker.start)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InlineDateTimeWheelPicker(
                    key: ValueKey<int>(_startPickerCounter),
                    initial: _start,
                    onChanged: _applyStart,
                  ),
                ),
              if (_allDay && _expanded == _ExpandedPicker.start)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AllDayCalendarPicker(
                    key: ValueKey<int>(_startDayPickerKey),
                    selectedDate: DateTime(_start.year, _start.month, _start.day),
                    onDateChanged: _applyAllDayStartCalendar,
                  ),
                ),
              _scheduleRow(
                context: context,
                label: '종료',
                value: _end,
                onTap: _toggleEndPicker,
              ),
              if (_canEditDateTime && _expanded == _ExpandedPicker.end)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InlineDateTimeWheelPicker(
                    key: ValueKey<int>(_endPickerCounter),
                    initial: _end,
                    onChanged: _onEndWheelChanged,
                  ),
                ),
              if (_allDay && _expanded == _ExpandedPicker.end)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AllDayCalendarPicker(
                    key: ValueKey<int>(_endDayPickerKey),
                    selectedDate: DateTime(_end.year, _end.month, _end.day),
                    onDateChanged: _applyAllDayEndCalendar,
                  ),
                ),
              const SizedBox(height: 6),
              Center(
                child: SegmentedButton<bool>(
                  style: ButtonStyle(
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.padded,
                    minimumSize: WidgetStateProperty.all(
                      const Size(0, _kFormBarButtonHeight),
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('시간')),
                    ButtonSegment<bool>(value: true, label: Text('하루 종일')),
                  ],
                  selected: {_allDay},
                  onSelectionChanged: (v) => _setAllDay(v.first),
                ),
              ),
              if (_canConfigureRepeat) ...[
                const SizedBox(height: 12),
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _saving ? null : _openRepeatSettings,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _repeatSel.summaryLine(reservationStart: _start),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '회의실',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_loadingRooms)
                      const LinearProgressIndicator(minHeight: 2)
                    else
                      DropdownButtonFormField<String?>(
                        isDense: true,
                        initialValue: (_selectedRoomId != null &&
                                _rooms.any((r) => r.id == _selectedRoomId))
                            ? _selectedRoomId
                            : null,
                        style: MeetingRoomCardStyles.fieldStyle(
                          Theme.of(context).textTheme,
                        ),
                        items: _rooms
                            .map<DropdownMenuItem<String?>>(
                              (r) => DropdownMenuItem<String>(
                                value: r.id,
                                child: Text(
                                  r.capacity != null
                                      ? '${r.name} (${r.capacity})'
                                      : r.name,
                                  style: MeetingRoomCardStyles.fieldStyle(
                                    Theme.of(context).textTheme,
                                  ),
                                ),
                              ),
                            )
                            .toList()
                          ..insert(
                            0,
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                '선택',
                                style: MeetingRoomCardStyles.fieldStyle(
                                  Theme.of(context).textTheme,
                                ),
                              ),
                            ),
                          ),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _selectedRoomId = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          hintText: '회의실을 선택하세요',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, _kFormBarButtonHeight),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, _kFormBarButtonHeight),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('저장'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_saving)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _AllDayCalendarPicker extends StatelessWidget {
  const _AllDayCalendarPicker({
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
