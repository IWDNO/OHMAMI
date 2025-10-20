import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class PowerWidget extends StatefulWidget {
  const PowerWidget({super.key});

  @override
  State<PowerWidget> createState() => _PowerWidgetState();
}

class _PowerWidgetState extends State<PowerWidget> {
  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription? _wsSubscription;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _wsSubscription = _connectionService.wsMessages.stream.listen((message) {
      if (mounted) {
        try {
          final decoded = json.decode(message);
          if (decoded is Map && decoded['type'] == 'power_update') {
            setState(() {
              // Handle power state updates if needed
            });
          }
        } catch (e) {
          print('Error parsing WebSocket message: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _request(String endpoint) async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _connectionService.request('GET', endpoint);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'ok') {
          _showSuccessMessage(data['message'] ?? 'Operation completed');
        } else {
          _showErrorMessage(data['message'] ?? 'Operation failed');
        }
      } else {
        _showErrorMessage('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorMessage('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showConfirmationDialog(String title, String message, String endpoint) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _request(endpoint);
              },
              child: const Text('Подтвердить'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shutdown() async {
    _showConfirmationDialog(
      'Выключение системы',
      'Вы уверены, что хотите выключить компьютер?',
      '/shutdown',
    );
  }

  Future<void> _restart() async {
    _showConfirmationDialog(
      'Перезагрузка системы',
      'Вы уверены, что хотите перезагрузить компьютер?',
      '/restart',
    );
  }

  Future<void> _sleep() async {
    _showConfirmationDialog(
      'Режим сна',
      'Перевести компьютер в режим сна?',
      '/sleep',
    );
  }

  Future<void> _hibernate() async {
    _showConfirmationDialog(
      'Гибернация',
      'Перевести компьютер в режим гибернации?',
      '/hibernate',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.power_settings_new,
                  color: Colors.blue[700],
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Управление питанием',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Power control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Sleep button
                _buildPowerButton(
                  icon: Icons.bedtime,
                  label: 'Сон',
                  color: Colors.blue,
                  onPressed: _sleep,
                ),
                
                // Hibernate button
                _buildPowerButton(
                  icon: Icons.nightlight_round,
                  label: 'Гибернация',
                  color: Colors.purple,
                  onPressed: _hibernate,
                ),
              ],
            ),

            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Restart button
                _buildPowerButton(
                  icon: Icons.restart_alt,
                  label: 'Перезагрузка',
                  color: Colors.orange,
                  onPressed: _restart,
                ),
                
                // Shutdown button
                _buildPowerButton(
                  icon: Icons.power_off,
                  label: 'Выключение',
                  color: Colors.red,
                  onPressed: _shutdown,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(icon),
          iconSize: 32,
          style: IconButton.styleFrom(
            backgroundColor: color.withOpacity(0.1),
            foregroundColor: color,
            disabledBackgroundColor: Colors.grey.withOpacity(0.1),
            disabledForegroundColor: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: _isLoading ? Colors.grey : color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}