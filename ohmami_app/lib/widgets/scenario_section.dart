import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/connection_service.dart';

class Scenario {
  final String name;
  final List<String> launchAppPaths;
  final List<String> blockPaths;

  Scenario({
    required this.name,
    required this.launchAppPaths,
    required this.blockPaths,
  });

  bool get hasActions =>
      launchAppPaths.isNotEmpty || blockPaths.isNotEmpty;
}

class ScenarioSection extends StatefulWidget {
  const ScenarioSection({super.key});

  @override
  State<ScenarioSection> createState() => _ScenarioSectionState();
}

class _ScenarioSectionState extends State<ScenarioSection> {
  final ConnectionService _conn = ConnectionService();
  final List<Scenario> _scenarios = [];

  Future<void> _runScenario(Scenario scenario) async {
    if (!scenario.hasActions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сценарий не содержит действий'),
        ),
      );
      return;
    }

    String? error;

    // Запуск приложений
    for (final path in scenario.launchAppPaths) {
      try {
        final endpoint =
            '/apps/launch?path=${Uri.encodeQueryComponent(path)}';
        final resp = await _conn.request('POST', endpoint);

        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['status'] != 'ok') {
          throw Exception(body['message'] ?? 'Ошибка запуска');
        }
      } catch (e) {
        error = (error ?? '') + '\nОшибка запуска: $path — $e';
      }
    }

    // Блокировка путей/приложений
    for (final path in scenario.blockPaths) {
      try {
        final endpoint =
            '/security/block/app?path=${Uri.encodeQueryComponent(path)}';
        final resp = await _conn.request('POST', endpoint);

        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['status'] != 'ok') {
          throw Exception(body['message'] ?? 'Ошибка блокировки');
        }
      } catch (e) {
        error = (error ?? '') + '\nОшибка блокировки: $path — $e';
      }
    }

    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сценарий "${scenario.name}" выполнен'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Сценарий "${scenario.name}" выполнен с ошибками:$error',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _openAddScenarioDialog() async {
    final scenario = await showDialog<Scenario>(
      context: context,
      builder: (context) => const _ScenarioEditorDialog(),
    );

    if (scenario == null) return;

    setState(() {
      _scenarios.add(scenario);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Всегда показываем блок, чтобы была кнопка добавления
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Сценарии',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final scenario in _scenarios)
                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: SizedBox(
                    width: 150,
                    height: 120,
                    child: _GlassButton(
                      icon: Icons.playlist_play,
                      label: scenario.name,
                      onTap: () => _runScenario(scenario),
                    ),
                  ),
                ),
              SizedBox(
                width: 150,
                height: 120,
                child: _GlassButton(
                  icon: Icons.add,
                  label: 'Добавить сценарий',
                  onTap: _openAddScenarioDialog,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenarioEditorDialog extends StatefulWidget {
  const _ScenarioEditorDialog({super.key});

  @override
  State<_ScenarioEditorDialog> createState() =>
      _ScenarioEditorDialogState();
}

class _ScenarioEditorDialogState extends State<_ScenarioEditorDialog> {
  final ConnectionService _conn = ConnectionService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _apps = [];
  List<Map<String, dynamic>> _filteredApps = [];
  final Set<String> _selectedLaunchApps = {};
  final Set<String> _selectedBlockApps = {};

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchController.addListener(_applySearch);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
      _error = null;
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
      final apps = data
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _apps = apps;
        _filteredApps = apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredApps = _apps;
      });
      return;
    }

    setState(() {
      _filteredApps = _apps.where((app) {
        final name = (app['name'] as String? ?? '').toLowerCase();
        final path = (app['path'] as String? ?? '').toLowerCase();
        return name.contains(query) || path.contains(query);
      }).toList();
    });
  }

  void _toggleLaunch(String path) {
    setState(() {
      if (_selectedLaunchApps.contains(path)) {
        _selectedLaunchApps.remove(path);
      } else {
        _selectedLaunchApps.add(path);
      }
    });
  }

  void _toggleBlock(String path) {
    setState(() {
      if (_selectedBlockApps.contains(path)) {
        _selectedBlockApps.remove(path);
      } else {
        _selectedBlockApps.add(path);
      }
    });
  }

  bool get _canSave {
    return _nameController.text.trim().isNotEmpty &&
        (_selectedLaunchApps.isNotEmpty || _selectedBlockApps.isNotEmpty);
  }

  void _onSave() {
    if (!_canSave) return;

    final scenario = Scenario(
      name: _nameController.text.trim(),
      launchAppPaths: _selectedLaunchApps.toList(),
      blockPaths: _selectedBlockApps.toList(),
    );

    Navigator.of(context).pop(scenario);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый сценарий'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название сценария',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Поиск приложений',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Ошибка: $_error',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _loadApps,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Повторить'),
                              ),
                            ],
                          ),
                        )
                      : _filteredApps.isEmpty
                          ? const Center(
                              child: Text('Приложения не найдены'),
                            )
                          : ListView.builder(
                              itemCount: _filteredApps.length,
                              itemBuilder: (context, index) {
                                final app = _filteredApps[index];
                                final name =
                                    (app['name'] as String?) ?? 'Приложение';
                                final path =
                                    (app['path'] as String?) ?? '';
                                final isLaunchSelected =
                                    _selectedLaunchApps.contains(path);
                                final isBlockSelected =
                                    _selectedBlockApps.contains(path);

                                return ListTile(
                                  title: Text(name),
                                  subtitle: Text(
                                    path,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Запуск',
                                            style: TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                          Checkbox(
                                            value: isLaunchSelected,
                                            onChanged: (_) =>
                                                _toggleLaunch(path),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Блок',
                                            style: TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                          Checkbox(
                                            value: isBlockSelected,
                                            onChanged: (_) =>
                                                _toggleBlock(path),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _canSave ? _onSave : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

