import 'package:flutter/material.dart';

import '../../../../data/datasources/room_remote_ds.dart';
import '../../../../data/models/meeting_room_model.dart';

class RoomNameFilter extends StatefulWidget {
  const RoomNameFilter({
    super.key,
    required this.onChanged,
  });

  /// null이면 전체
  final ValueChanged<String?> onChanged;

  @override
  State<RoomNameFilter> createState() => _RoomNameFilterState();
}

class _RoomNameFilterState extends State<RoomNameFilter> {
  final _ds = RoomRemoteDs();
  List<MeetingRoom> _rooms = [];
  String? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _ds.fetchRoomsForReservation();
      if (!mounted) return;
      setState(() => _rooms = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '회의실명',
          style: TextStyle(fontSize: 14, color: Color(0xFF5F6368)),
        ),
        const SizedBox(height: 6),
        if (_loading)
          const LinearProgressIndicator()
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))
        else
          DropdownButtonFormField<String?>(
            value: _selectedId,
            isExpanded: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            hint: const Text('전체'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('전체'),
              ),
              ..._rooms.map(
                (r) => DropdownMenuItem<String?>(
                  value: r.id,
                  child: Text(r.name),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _selectedId = v);
              widget.onChanged(v);
            },
          ),
      ],
    );
  }
}
