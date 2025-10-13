import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/connection_service.dart';

class VolumeWidget extends StatefulWidget {
  const VolumeWidget({super.key});

  @override
  State<VolumeWidget> createState() => _VolumeWidgetState();
}

class _VolumeWidgetState extends State<VolumeWidget> {
  final ConnectionService _connectionService = ConnectionService();

  Map<String, dynamic>? _volumeInfo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVolumeInfo();
  }

  Future<void> _loadVolumeInfo() async {
    if (_connectionService.apiUrl == null) {
      setState(() {
        _error = 'No agent connected';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      final response = await _connectionService.request('GET', '/volume');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _volumeInfo = data['data'];
        });
      } else {
        setState(() {
          _error = 'Failed to load volume info: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _setVolume(int level) async {
    if (_connectionService.apiUrl == null) {
      setState(() {
        _error = 'No agent connected';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      final response = await _connectionService.request(
        'POST',
        '/volume/set?level=$level',
      );

      if (response.statusCode == 200) {
        await _loadVolumeInfo(); // refresh
      } else {
        setState(() {
          _error = 'Failed to set volume: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    }
  }

  Future<void> _toggleMute() async {
    if (_connectionService.apiUrl == null) {
      setState(() {
        _error = 'No agent connected';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      final endpoint = _volumeInfo?['muted'] == true ? '/volume/unmute' : '/volume/mute';
      final response = await _connectionService.request('POST', endpoint);

      if (response.statusCode == 200) {
        await _loadVolumeInfo(); // refresh
      } else {
        setState(() {
          _error = 'Failed to toggle mute: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    }
  }

  int get _currentLevel {
    final lvl = _volumeInfo?['level'];
    if (lvl is int) return lvl;
    if (lvl is double) return lvl.toInt();
    if (lvl is String) return int.tryParse(lvl) ?? 0;
    return 0;
  }

  bool get _isMuted => _volumeInfo?['muted'] == true;

@override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок с кнопкой обновления
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Громкость',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Обновить',
                  onPressed: _loadVolumeInfo,
                ),
              ],
            ),
            
            const SizedBox(height: 6),
            Text(
              _isMuted ? 'Выключено' : 'Уровень: $_currentLevel%',
              style: TextStyle(color: Colors.grey[700]),
            ),

            // Slider + quick controls
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Column(
                children: [
                  Slider(
                    min: 0,
                    max: 100,
                    divisions: 100,
                    value: _currentLevel.clamp(0, 100).toDouble(),
                    onChanged: (value) {
                      // Local update for smooth UI
                      setState(() {
                        _volumeInfo ??= {};
                        _volumeInfo!['level'] = value.toInt();
                      });
                    },
                    onChangeEnd: (value) async {
                      await _setVolume(value.toInt());
                    },
                  ),
                ],
              ),
            ),

            // Error / status / actions
            Row(
              children: [
                if (_error != null)
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),

                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    // Example: decrease quickly by 10
                    final newLevel = (_currentLevel - 10).clamp(0, 100);
                    await _setVolume(newLevel);
                  },
                  icon: const Icon(Icons.remove),
                  label: const Text('-10'),
                ),

                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: () async {
                    final newLevel = (_currentLevel + 10).clamp(0, 100);
                    await _setVolume(newLevel);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('+10'),
                ),

                const SizedBox(width: 8),

                OutlinedButton.icon(
                  onPressed: _toggleMute,
                  icon: Icon(_isMuted ? Icons.volume_up : Icons.volume_off),
                  label: Text(_isMuted ? 'Unmute' : 'Mute'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}