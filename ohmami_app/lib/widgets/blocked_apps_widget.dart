import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class BlockedAppsWidget extends StatefulWidget {
  const BlockedAppsWidget({super.key});

  @override
  State<BlockedAppsWidget> createState() => _BlockedAppsWidgetState();
}

class _BlockedAppsWidgetState extends State<BlockedAppsWidget> {
  final ConnectionService _conn = ConnectionService();

  List<String> _blockedPaths = [];
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
  }

  Future<void> _loadBlockedApps() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final resp = await _conn.request('GET', '/security/blocked');
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Status: ${body['status']}');
      }

      final List data = (body['data'] as List? ?? <dynamic>[]);
      setState(() {
        _blockedPaths = data.map<String>((e) => e.toString()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockApp(String path) async {
    // Проверяем, что путь не пустой
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: путь к приложению пустой'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Показываем диалог подтверждения
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Разблокировать?'),
          content: Text('Вы уверены, что хотите разблокировать:\n$trimmedPath'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.green,
              ),
              child: const Text('Разблокировать'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      // Используем Uri.parse для правильного формирования URL с параметрами
      final uri = Uri.parse('${_conn.apiUrl}/security/unblock').replace(
        queryParameters: {'path': trimmedPath},
      );
      
      final endpoint = uri.toString().replaceFirst(_conn.apiUrl ?? '', '');
      final resp = await _conn.request('DELETE', endpoint);

      // Парсим ответ независимо от статус кода
      Map<String, dynamic>? body;
      try {
        body = json.decode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        // Если не удалось распарсить JSON, продолжаем с проверкой статус кода
      }

      // Проверяем статус ответа
      if (resp.statusCode != 200) {
        String errorMessage = 'HTTP ${resp.statusCode}';
        if (body != null && body['message'] != null) {
          errorMessage = body['message'] as String;
        } else if (resp.body.isNotEmpty) {
          errorMessage = resp.body;
        }
        
        // Специальная обработка для ошибок прав доступа
        if (errorMessage.toLowerCase().contains('unauthorized') || 
            errorMessage.toLowerCase().contains('unauthorized operation') ||
            errorMessage.toLowerCase().contains('доступ запрещен') ||
            resp.statusCode == 403) {
          errorMessage = 'Недостаточно прав для выполнения операции. Требуются права администратора.';
        }
        
        throw Exception(errorMessage);
      }

      // Проверяем статус в теле ответа
      if (body != null && body['status'] != 'ok') {
        String errorMessage = body['message'] ?? 'Ошибка разблокировки';
        
        // Специальная обработка для ошибок прав доступа в теле ответа
        if (errorMessage.toLowerCase().contains('unauthorized') || 
            errorMessage.toLowerCase().contains('unauthorized operation') ||
            errorMessage.toLowerCase().contains('доступ запрещен')) {
          errorMessage = 'Недостаточно прав для выполнения операции. Требуются права администратора.';
        }
        
        throw Exception(errorMessage);
      }

      // Обновляем список
      await _loadBlockedApps();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Разблокировано: $trimmedPath'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      String errorMessage = e.toString();
      // Убираем префикс "Exception: " если есть
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Widget _buildBlockedItem(String path) {
    // Извлекаем имя файла из пути
    final fileName = path.split(RegExp(r'[/\\]')).last;

    return ListTile(
      leading: Icon(
        Icons.block,
        color: Colors.red[700],
      ),
      title: Text(fileName),
      subtitle: Text(
        path,
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[600],
          fontFamily: 'monospace',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.lock_open),
        color: Colors.green,
        onPressed: () => _unblockApp(path),
        tooltip: 'Разблокировать',
      ),
      onTap: () => _unblockApp(path),
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
                  Icons.block,
                  color: Colors.red[700],
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Заблокированные приложения',
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
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _loadBlockedApps,
                  tooltip: 'Обновить список',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Blocked apps list
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Ошибка: $_error',
                              style: TextStyle(color: Colors.red[700]),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadBlockedApps,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _blockedPaths.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: Colors.green[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Нет заблокированных приложений',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _blockedPaths.length,
                          itemBuilder: (context, index) => _buildBlockedItem(_blockedPaths[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
