import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/reservation_rpc_error_mapper.dart';
import '../../../../core/user_facing_error_message.dart';
import '../../../../data/datasources/reservation_remote_ds.dart';
import '../../../../data/datasources/room_remote_ds.dart';
import '../../../../data/models/calendar_event_model.dart';
import '../../../../data/models/meeting_room_model.dart';
import '../../../../data/models/reservation_booker_info.dart';
import '../../../calendar/presentation/widgets/reservation_status_chip.dart';
import '../widgets/inline_datetime_wheel_picker.dart';
import '../widgets/meeting_room_card_styles.dart';

class ReservationEditorPage extends StatefulWidget {
  const ReservationEditorPage({super.key, required this.event});
  final CalendarEventModel event;

  @override
  State<ReservationEditorPage> createState() => _ReservationEditorPageState();
}

enum _ExpandedPicker { none, start, end }
enum _SaveScope { single, thisOnly, all }
enum _DeleteScope { single, thisAndFollowing, all }

class _ReservationEditorPageState extends State<ReservationEditorPage> {
  final _ds = ReservationRemoteDs();
  final _roomDs = RoomRemoteDs();
  static final _displayFmtDate = DateFormat('M월 d일(E)', 'ko_KR');
  static final _displayFmtTime = DateFormat('a h:mm', 'ko_KR');

  late TextEditingController _titleCtrl;
  late DateTime _start;
  late DateTime _end;
  bool _saving = false;
  bool _deleting = false;
  bool _statusChanging = false;
  bool? _canApprove;
  _ExpandedPicker _expanded = _ExpandedPicker.none;
  int _startPickerCounter = 0;
  int _endPickerCounter = 0;

  ReservationBookerInfo? _bookerInfo;
  bool _bookerLoading = true;

  late String _selectedRoomId;
  List<MeetingRoom> _rooms = const [];
  bool _loadingRooms = false;

  /// 신청·완료일 때 일정 값(날짜·시간) 강조 스타일.
  bool get _scheduleValueEmphasized {
    final s = widget.event.status;
    return s == kReservationStatusApplied || s == kReservationStatusCompleted;
  }

  /// 신청·완료일 때 휠 피커로 시각 수정 가능.
  bool get _canEditDateTime =>
      _scheduleValueEmphasized && _canEditReservationFields;

  /// 시작/종료 값 탭 허용 여부.
  bool get _canTapScheduleValue =>
      _scheduleValueEmphasized && _canEditReservationFields;

  /// 기획: 저장(본인·110 또는 140)이 가능할 때만 제목·일정 편집.
  bool get _canEditReservationFields => _showSaveButton;

  bool get _isSelf {
    final uid = _ds.actorUid;
    final cu = widget.event.createUser;
    if (uid == null || cu == null || cu.isEmpty) return false;
    return cu == uid;
  }

  /// 담당자/회의실 승인자: 신청(110)일 때 하단에 승인·반려(저장 자리 대체).
  bool get _showApproveRejectRow =>
      widget.event.status == kReservationStatusApplied && _canApprove == true;

  /// 본인만, 110(비승인자) 또는 140. 승인자에게는 저장 대신 승인·반려 행이 옴.
  bool get _showSaveButton {
    if (!_isSelf) return false;
    final s = widget.event.status;
    if (s == kReservationStatusCompleted) return true;
    if (s == kReservationStatusApplied) {
      if (_canApprove == null) return false;
      return _canApprove == false;
    }
    return false;
  }

  /// 본인만 모든 상태에서 삭제 가능.
  bool get _showDeleteButton => _isSelf;

  bool get _anyBusy => _saving || _deleting || _statusChanging;

  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.event.roomId;
    _titleCtrl = TextEditingController(text: widget.event.title);
    _start = widget.event.start.toLocal();
    _end = widget.event.end.toLocal();
    _bootstrapInitialData();
  }

  /// 승인 가능 여부·회의실 목록·예약자 정보를 **병렬** 조회 후 한 번에 반영 (순차 로딩 완화).
  Future<void> _bootstrapInitialData() async {
    final needRooms = _isSelf &&
        (widget.event.status == kReservationStatusApplied ||
            widget.event.status == kReservationStatusCompleted);
    final uid = widget.event.createUser;
    final needBooker = uid != null && uid.isNotEmpty;

    if (mounted) {
      setState(() {
        if (needRooms) _loadingRooms = true;
        if (needBooker) _bookerLoading = true;
      });
    }

    final approverFuture = _ds
        .canActorApproveForRoom(_selectedRoomId)
        .catchError((_) => false);
    final roomsFuture = needRooms
        ? _roomDs.fetchRoomsForReservation().catchError(
            (_) => <MeetingRoom>[],
          )
        : Future<List<MeetingRoom>>.value(const []);
    final bookerUid = uid;
    final bookerFuture = (bookerUid != null && bookerUid.isNotEmpty)
        ? _ds.fetchBookerInfo(userUid: bookerUid).catchError((_) => null)
        : Future<ReservationBookerInfo?>.value(null);

    try {
      final out = await Future.wait<Object?>([
        approverFuture,
        roomsFuture,
        bookerFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _canApprove = out[0] as bool;
        if (needRooms) {
          _rooms = out[1] as List<MeetingRoom>;
        }
        _bookerInfo = out[2] as ReservationBookerInfo?;
        _loadingRooms = false;
        _bookerLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canApprove = false;
        if (needRooms) {
          _rooms = const [];
        }
        _loadingRooms = false;
        _bookerLoading = false;
      });
    }
  }

  /// 회의실 드롭다운 변경 시 승인 권한만 다시 조회.
  Future<void> _loadApproverCapability() async {
    try {
      final v = await _ds.canActorApproveForRoom(_selectedRoomId);
      if (mounted) setState(() => _canApprove = v);
    } catch (_) {
      if (mounted) setState(() => _canApprove = false);
    }
  }

  List<DropdownMenuItem<String>> _buildRoomMenuItems() {
    final fieldStyle = MeetingRoomCardStyles.fieldStyle(Theme.of(context).textTheme);
    final out = <DropdownMenuItem<String>>[];
    final seen = <String>{};
    for (final r in _rooms) {
      if (seen.contains(r.id)) continue;
      seen.add(r.id);
      final label = r.capacity != null ? '${r.name} (${r.capacity})' : r.name;
      out.add(
        DropdownMenuItem<String>(
          value: r.id,
          child: Text(
            label,
            style: fieldStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      );
    }
    if (!seen.contains(_selectedRoomId) && _selectedRoomId.isNotEmpty) {
      final nm = widget.event.roomName.isEmpty ? _selectedRoomId : widget.event.roomName;
      out.insert(
        0,
        DropdownMenuItem<String>(
          value: _selectedRoomId,
          child: Text(
            nm,
            style: fieldStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      );
    }
    return out;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  /// 키보드가 열린 채 pop하면 복귀 화면에서 viewInsets 애니메이션과 겹쳐 순간 overflow(빨간 띠)가 날 수 있음.
  Future<void> _unfocusKeyboardBeforePop() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future<void>.delayed(const Duration(milliseconds: 64));
  }

  Future<void> _saveThis() async {
    if (_anyBusy) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제목은 필수 입력입니다.')));
      return;
    }

    final payload = {
      'title': title,
      'room_id': _selectedRoomId,
      'allday_yn': 'N',
      'start_ymd': _start.toUtc().toIso8601String(),
      'end_ymd': _end.toUtc().toIso8601String(),
      // 필요 시 repeat 필드 포함
    };
    final isRepeating =
        (widget.event.repeatGroupId != null &&
        widget.event.repeatGroupId!.isNotEmpty);

    _SaveScope scope = _SaveScope.single;
    if (isRepeating) {
      final selected = await _askSaveScope();
      if (selected == null) return;
      scope = selected;
    }

    setState(() => _saving = true);
    try {
      switch (scope) {
        case _SaveScope.single:
          await _ds.saveSingle(reservationId: widget.event.id, payload: payload);
          break;
        case _SaveScope.thisOnly:
          await _ds.saveThisOccurrence(
            reservationId: widget.event.id,
            payload: payload,
          );
          break;
        case _SaveScope.all:
          await _ds.saveAllInSeries(
            repeatGroupId: widget.event.repeatGroupId!,
            payload: payload,
            oldStartUtc: widget.event.start.toUtc(),
            oldEndUtc: widget.event.end.toUtc(),
            newStartUtc: _start.toUtc(),
            newEndUtc: _end.toUtc(),
          );
          break;
      }
      if (!mounted) return;
      await _unfocusKeyboardBeforePop();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: ${userFacingErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askStatusChangeScope() {
    final gid = widget.event.repeatGroupId;
    if (gid == null || gid.trim().isEmpty) {
      return Future.value('this');
    }
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('반복 일정'),
        content: const Text('어느 범위로 처리할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'this'),
            child: const Text('이 일정'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'all'),
            child: const Text('모든 일정'),
          ),
        ],
      ),
    );
  }

  /// 반려 사유 입력 모달. 확인 시 입력 문자열(빈 문자열 가능), 취소·× 시 `null`.
  Future<String?> _showRejectReasonModal() {
    return showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _RejectReasonDialog(),
    );
   }

  Future<void> _runStatusChange(int nextStatus) async {
    if (_anyBusy) return;

    String? returnComment;
    if (nextStatus == kReservationStatusRejected) {
      final c = await _showRejectReasonModal();
      if (!mounted || c == null) return;
      returnComment = c.isEmpty ? null : c;
    }

    final scope = await _askStatusChangeScope();
    if (!mounted || scope == null) return;

    setState(() => _statusChanging = true);
    try {
      final r = await _ds.changeReservationStatus(
        targetReservationId: widget.event.id,
        nextStatus: nextStatus,
        scope: scope,
        returnComment: returnComment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('처리되었습니다 (${r.affectedCount}건)')),
      );
      await _unfocusKeyboardBeforePop();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mapReservationStatusRpcUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _statusChanging = false);
    }
  }

  Future<_SaveScope?> _askSaveScope() {
    return showDialog<_SaveScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('반복 일정 저장'),
        content: const Text('어떻게 저장할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _SaveScope.thisOnly),
            child: const Text('이 일정'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _SaveScope.all),
            child: const Text('모든 일정'),
          ),
        ],
      ),
    );
  }

  Future<_DeleteScope?> _askDeleteScope() async {
    final gid = widget.event.repeatGroupId;
    if (gid == null || gid.trim().isEmpty) {
      return _DeleteScope.single;
    }
    return showDialog<_DeleteScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('반복 일정 삭제'),
        content: const Text('어떤 범위를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteScope.single),
            child: const Text('이 일정'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _DeleteScope.thisAndFollowing),
            child: const Text('이 일정 및 이후'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _DeleteScope.all),
            child: const Text('모든 일정'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    if (_anyBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('예약 삭제'),
        content: const Text('이 예약을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final scope = await _askDeleteScope();
    if (!mounted || scope == null) return;

    setState(() => _deleting = true);
    try {
      switch (scope) {
        case _DeleteScope.single:
          await _ds.deleteReservation(reservationId: widget.event.id);
          break;
        case _DeleteScope.thisAndFollowing:
          await _ds.deleteReservationThisAndFollowing(
            reservationId: widget.event.id,
          );
          break;
        case _DeleteScope.all:
          final g = widget.event.repeatGroupId;
          if (g == null || g.isEmpty) {
            throw Exception('반복 그룹 정보가 없습니다.');
          }
          await _ds.deleteReservationAllInGroup(repeatGroupId: g);
          break;
      }
      if (!mounted) return;
      await _unfocusKeyboardBeforePop();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: ${userFacingErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _applyStart(DateTime v) {
    setState(() {
      _start = v;
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(minutes: 30));
      }
    });
  }

  void _toggleStartPicker() {
    if (!_canTapScheduleValue || _anyBusy) return;
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
    if (!_canTapScheduleValue || _anyBusy) return;
    setState(() {
      if (_expanded == _ExpandedPicker.end) {
        _expanded = _ExpandedPicker.none;
      } else {
        _expanded = _ExpandedPicker.end;
        _endPickerCounter++;
      }
    });
  }

  String _scheduleDisplayText(DateTime dt) {
    return '${_displayFmtDate.format(dt)} ${_displayFmtTime.format(dt)}';
  }

  void _onEndWheelChanged(DateTime v) {
    setState(() {
      _end = v.isAfter(_start) ? v : _start.add(const Duration(minutes: 30));
    });
  }

  Widget _scheduleRow(
    BuildContext context, {
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyLarge;
    final valueStyle = _scheduleValueEmphasized
        ? textStyle?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          )
        : textStyle;
    final valueWidget = _canTapScheduleValue
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                _scheduleDisplayText(value),
                style: valueStyle,
                textAlign: TextAlign.end,
              ),
            ),
          )
        : Text(
            _scheduleDisplayText(value),
            style: valueStyle,
            textAlign: TextAlign.end,
          );
    final normalizedValueWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: valueWidget,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: textStyle),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: normalizedValueWidget,
            ),
          ),
        ],
      ),
    );
  }

  /// 반려 사유 — 회의실 카드와 동일한 박스 스타일.
  Widget _rejectCommentCard(BuildContext context) {
    final theme = Theme.of(context);
    final note = widget.event.returnComment!.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.error),
        ),
        child: Text(
          note,
          style: MeetingRoomCardStyles.fieldStyle(theme.textTheme),
        ),
      ),
    );
  }

  /// 회의실 — 좌우 패딩은 `시작`/`종료`와 동일. 라벨 아래에 드롭다운·값을 둠.
  Widget _roomRow(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyLarge;
    final fieldStyle = MeetingRoomCardStyles.fieldStyle(theme.textTheme);
    final text = widget.event.roomName.isEmpty ? '—' : widget.event.roomName;

    Widget roomColumn(List<Widget> belowLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('회의실', style: labelStyle),
            const SizedBox(height: 8),
            ...belowLabel,
          ],
        ),
      );
    }

    if (!_canEditReservationFields) {
      return roomColumn([
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            text,
            style: fieldStyle,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);
    }

    if (_loadingRooms) {
      return roomColumn([
        const LinearProgressIndicator(minHeight: 2),
      ]);
    }

    final items = _buildRoomMenuItems();
    if (items.isEmpty) {
      return roomColumn([
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(text, style: fieldStyle),
        ),
      ]);
    }

    final validValue = items.any((e) => e.value == _selectedRoomId)
        ? _selectedRoomId
        : items.first.value!;

    // `DropdownButtonFormField` + `initialValue`는 웹에서 items 재생성 시 FormField 단언/빌드 루프가 날 수 있어
    // `DropdownButton`(상태 `value`) + `InputDecorator`로 고정한다.
    return roomColumn([
      InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: validValue,
            isDense: true,
            isExpanded: true,
            style: fieldStyle,
            items: items,
            onChanged: _anyBusy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _selectedRoomId = v);
                    _loadApproverCapability();
                  },
          ),
        ),
      ),
    ]);
  }

  /// 회의실 아래 — 예약자 본문 글씨는 회의실 선택값과 동일(`MeetingRoomCardStyles.fieldStyle`).
  Widget _bookerRow(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyLarge;
    final detailStyle = MeetingRoomCardStyles.fieldStyle(theme.textTheme);

    if (_bookerLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final detail = _bookerInfo?.detailAfterColon ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('예약자', style: labelStyle),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  detail,
                  style: detailStyle,
                  textAlign: TextAlign.end,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rejectStyle = OutlinedButton.styleFrom(
      foregroundColor: scheme.error,
      side: BorderSide(color: scheme.error),
    );
    final deleteStyle = OutlinedButton.styleFrom(
      foregroundColor: scheme.error,
      side: BorderSide(color: scheme.error),
    );
    final showAr = _showApproveRejectRow;
    final showSave = _showSaveButton;
    final showDel = _showDeleteButton;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _anyBusy ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ),
        if (showAr) ...[
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _anyBusy
                  ? null
                  : () => _runStatusChange(kReservationStatusApproved),
              child: const Text('승인'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: rejectStyle,
              onPressed: _anyBusy
                  ? null
                  : () => _runStatusChange(kReservationStatusRejected),
              child: const Text('반려'),
            ),
          ),
        ] else if (showSave) ...[
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _anyBusy ? null : _saveThis,
              child: const Text('저장'),
            ),
          ),
        ],
        if (showDel) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: deleteStyle,
              onPressed: _anyBusy ? null : _confirmAndDelete,
              child: const Text('삭제'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: ReservationStatusChip(status: widget.event.status),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _titleCtrl,
                readOnly: !_canEditReservationFields,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              if (widget.event.status == kReservationStatusRejected &&
                  (widget.event.returnComment?.trim().isNotEmpty ?? false))
                _rejectCommentCard(context),
              if (_canApprove == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              _scheduleRow(
                context,
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
              _scheduleRow(
                context,
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
              _roomRow(context),
              _bookerRow(context),
              const SizedBox(height: 24),
              _buildBottomActions(context),
            ],
          ),
          if (_anyBusy)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// 반려 사유 모달. 컨트롤러는 라우트 수명에 맞춰 dispose, pop은 unfocus 후 다음 프레임.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _popping = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String? result) {
    if (_popping) return;
    _popping = true;
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '반려 사유',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => _finish(null),
                    tooltip: '닫기',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: '반려 사유를 입력하세요.',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _finish(null),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                    onPressed: () => _finish(_controller.text.trim()),
                    child: const Text('반려'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
