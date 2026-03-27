import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../data/datasources/reservation_remote_ds.dart';
import '../../../../data/models/calendar_event_model.dart';

class ReservationEditorPage extends StatefulWidget {
  const ReservationEditorPage({super.key, required this.event});
  final CalendarEventModel event;

  @override
  State<ReservationEditorPage> createState() => _ReservationEditorPageState();
}

class _ReservationEditorPageState extends State<ReservationEditorPage> {
  final _ds = ReservationRemoteDs();
  late TextEditingController _titleCtrl;
  late DateTime _start;
  late DateTime _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.event.title);
    _start = widget.event.start.toLocal();
    _end = widget.event.end.toLocal();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveThis() async {
    setState(() => _saving = true);
    try {
      await _ds.saveThisOccurrence(
        reservationId: widget.event.id,
        payload: {
          'title': _titleCtrl.text.trim(),
          'room_id': widget.event.roomId,
          'allday_yn': 'N',
          'start_ymd': _start.toUtc().toIso8601String(),
          'end_ymd': _end.toUtc().toIso8601String(),
          // 필요 시 repeat 필드 포함
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _moveThis() async {
    setState(() => _saving = true);
    try {
      await _ds.moveThisOccurrence(
        reservationId: widget.event.id,
        startUtcIso: _start.toUtc().toIso8601String(),
        endUtcIso: _end.toUtc().toIso8601String(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이동 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('회의실 예약 수정')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('시작'),
                subtitle: Text(f.format(_start)),
              ),
              ListTile(
                title: const Text('종료'),
                subtitle: Text(f.format(_end)),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _saveThis,
                      child: const Text('이 일정 저장'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _moveThis,
                      child: const Text('이 일정 이동'),
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
