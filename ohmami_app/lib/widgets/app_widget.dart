import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class AppLauncherWidget extends StatefulWidget {
  const AppLauncherWidget({super.key});

  @override
  State<AppLauncherWidget> createState() => _AppLauncherWidgetState();
}

class _AppLauncherWidgetState extends State<AppLauncherWidget> {
  final ConnectionService _conn = ConnectionService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _apps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  String? _error;
  bool _isLoading = false;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  Future<void> _loadApps() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final resp = await _conn.request('GET', '/apps');
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Status: ${body['status']}');
      }

      final List data = (body['data'] as List? ?? <dynamic>[]);
      setState(() {
        _apps = data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        _filteredApps = _apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    
    if (query.isEmpty) {
      setState(() {
        _filteredApps = _apps;
      });
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final endpoint = '/apps/search?q=${Uri.encodeQueryComponent(query)}';
      final resp = await _conn.request('GET', endpoint);
      
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Status: ${body['status']}');
      }

      final List data = (body['data'] as List? ?? <dynamic>[]);
      setState(() {
        _filteredApps = data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        // При ошибке поиска показываем все приложения
        _filteredApps = _apps;
      });
    }
  }

  Future<void> _launchApp(Map<String, dynamic> app) async {
    final path = app['path'] as String?;
    if (path == null || path.isEmpty) {
      _showErrorMessage('Путь к приложению не указан');
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      final endpoint = '/apps/launch?path=${Uri.encodeQueryComponent(path)}';
      final resp = await _conn.request('POST', endpoint);

      if (resp.statusCode == 403) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Доступ запрещен');
      }

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception(body['message'] ?? 'Ошибка запуска');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Приложение запущено: ${app['name'] ?? path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при запуске: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildAppTile(Map<String, dynamic> app) {
    final name = (app['name'] as String?) ?? 'Неизвестное приложение';
    final path = (app['path'] as String?) ?? '';
    final description = (app['description'] as String?) ?? '';

    // Формируем текст для subtitle
    String subtitleText = '';
    if (description.isNotEmpty) {
      subtitleText = description;
    }
    if (path.isNotEmpty) {
      if (subtitleText.isNotEmpty) {
        subtitleText += '\n';
      }
      subtitleText += path;
    }

    return ListTile(
      leading: Icon(
        Icons.apps,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(name),
      subtitle: subtitleText.isNotEmpty
          ? Text(
              subtitleText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontFamily: path.isNotEmpty ? 'monospace' : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.play_arrow),
        color: Theme.of(context).colorScheme.primary,
        onPressed: () => _launchApp(app),
        tooltip: 'Запустить',
      ),
      onTap: () => _launchApp(app),
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
                  Icons.apps,
                  color: Colors.blue[700],
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Запуск приложений',
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
                  onPressed: _isLoading ? null : _loadApps,
                  tooltip: 'Обновить список',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Search field
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Поиск приложений...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filteredApps = _apps;
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Apps list - используем ConstrainedBox вместо Expanded
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5, // 50% высоты экрана
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
                              onPressed: _loadApps,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _filteredApps.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.apps_outlined,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchController.text.isNotEmpty
                                      ? 'Приложения не найдены'
                                      : 'Нет приложений',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, index) => _buildAppTile(_filteredApps[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}