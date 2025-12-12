import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';



class FileBrowserWidget extends StatefulWidget {
  const FileBrowserWidget({super.key});

  @override
  State<FileBrowserWidget> createState() => _FileBrowserWidgetState();
}

class _FileBrowserWidgetState extends State<FileBrowserWidget> {
  final ConnectionService _conn = ConnectionService();

  final List<String?> pathStack = <String?>[];

  String? error;
  List<Map<String, dynamic>> entries = <Map<String, dynamic>>[];
  Map<String, String> specialFolders = {};
  Set<String> blockedPaths = <String>{};

  String? get currentPath => pathStack.isEmpty ? null : pathStack.last;

  @override
  void initState() {
    super.initState();
    _loadListing(null);
    _loadSpecialFolders();
    _loadBlockedPaths();
  }

  Future<void> _loadSpecialFolders() async {
    try {
      final resp = await _conn.request('GET', '/fs/special-folders');
      if (resp.statusCode != 200) {
        return;
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] == 'ok' && body['data'] != null) {
        setState(() {
          specialFolders = Map<String, String>.from(body['data'] as Map);
        });
      }
    } catch (e) {
      // Игнорируем ошибки загрузки специальных папок
      print('Error loading special folders: $e');
    }
  }

  Future<void> _loadBlockedPaths() async {
    try {
      final resp = await _conn.request('GET', '/security/blocked');
      if (resp.statusCode != 200) {
        return;
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] == 'ok' && body['data'] != null) {
        final List data = (body['data'] as List? ?? <dynamic>[]);
        setState(() {
          blockedPaths = data.map<String>((e) => e.toString()).toSet();
        });
      }
    } catch (e) {
      // Игнорируем ошибки загрузки заблокированных путей
      print('Error loading blocked paths: $e');
    }
  }

  Future<void> _navigateToSpecialFolder(String folderPath) async {
    if (folderPath.isEmpty) return;

    // Очищаем стек и переходим к папке
    pathStack.clear();
    pathStack.add(folderPath);
    await _loadListing(folderPath);
  }

  Future<void> _loadListing(String? path) async {
    setState(() {
      error = null;
    });

    try {
      final endpoint = path == null || path.isEmpty
          ? '/fs/ls'
          : '/fs/ls?path=${Uri.encodeQueryComponent(path)}';

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
        entries = data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
      // Обновляем список заблокированных путей для актуального состояния
      _loadBlockedPaths();
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    }
  }

  // Переход вниз: в диск/директорию — или скачивание файла
  Future<void> _enter(Map<String, dynamic> item) async {
    final bool isDir = item['isDirectory'] == true;
    final bool isDrive = item['isDrive'] == true;
    final String name = (item['name'] as String?) ?? 'file';
    final String filePath = (item['path'] as String?) ?? '';

    if (isDir || isDrive) {
      // пушим и грузим директорию
      pathStack.add(filePath);
      await _loadListing(filePath);
      return;
    }

    // Если это файл — скачать его
    await _downloadFile(filePath, name);
  }

  // Скачать файл по /fs/download?path=...
  Future<void> _downloadFile(String remotePath, String filename) async {
  setState(() {
    error = null;
  });

  try {
    if (remotePath.isEmpty) throw Exception('Путь файла пустой');

    final endpoint = '/fs/download?path=${Uri.encodeQueryComponent(remotePath)}';
    final resp = await _conn.request('GET', endpoint);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }

    final bytes = resp.bodyBytes;

    final savePath = '${'/storage/emulated/0/Download'}/$filename'; //FIXME: gotta use path_provider idk how

    final file = File(savePath);
    await file.writeAsBytes(bytes);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранено: $savePath')),
    );

    // Open the file directly instead of showing share dialog
    await OpenFile.open(savePath);

  } catch (e) {
    setState(() {
      error = e.toString();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка при скачивании/шаре: $e')),
    );
  }
}

  Future<void> _uploadFile() async {
    try {
      // Выбор файла
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        return; // Пользователь отменил выбор
      }

      final platformFile = result.files.first;
      if (platformFile.path == null) {
        throw Exception('Не удалось получить путь к файлу');
      }

      final file = File(platformFile.path!);
      final fileName = platformFile.name;

      // Определяем путь назначения (текущая директория или корень)
      final dest = currentPath ?? '';

      // Показываем индикатор загрузки
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загрузка файла...')),
      );

      // Загружаем файл
      final endpoint = '/fs/upload?dest=${Uri.encodeQueryComponent(dest)}';
      final resp = await _conn.uploadFile(endpoint, file);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список файлов
      await _loadListing(currentPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Файл загружен: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при загрузке: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  Future<void> _createDirectory() async {
    // Проверяем, что мы не на этапе выбора тома
    if (currentPath == null) return;

    // Показываем диалог для ввода имени директории
    final TextEditingController nameController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Создать папку'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Введите имя папки',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );

    if (result != true || nameController.text.trim().isEmpty) {
      return; // Пользователь отменил или не ввел имя
    }

    final dirName = nameController.text.trim();

    setState(() {
      error = null;
    });

    try {
      // Формируем путь новой директории
      String newDirPath;
      if (currentPath!.isEmpty) {
        newDirPath = dirName;
      } else {
        // Для Windows используем обратный слеш
        final separator = currentPath!.contains('\\') ? '\\' : '/';
        newDirPath = '$currentPath$separator$dirName';
      }

      // Отправляем запрос на создание директории
      final endpoint = '/fs/mkdir?path=${Uri.encodeQueryComponent(newDirPath)}';
      final resp = await _conn.request('POST', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список файлов
      await _loadListing(currentPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Папка создана: $dirName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при создании папки: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _blockPath(Map<String, dynamic> item) async {
    final String itemPath = (item['path'] as String?) ?? '';
    final String name = (item['name'] as String?) ?? 'file';

    if (itemPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: путь к файлу пустой'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Проверяем, не заблокирован ли уже файл
    if (blockedPaths.contains(itemPath)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Файл уже заблокирован'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      error = null;
    });

    try {
      final endpoint = '/security/block/path?path=${Uri.encodeQueryComponent(itemPath)}';
      final resp = await _conn.request('POST', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список заблокированных путей
      await _loadBlockedPaths();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заблокировано: $name'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при блокировке: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _unblockPath(Map<String, dynamic> item) async {
    final String itemPath = (item['path'] as String?) ?? '';
    final String name = (item['name'] as String?) ?? 'file';

    if (itemPath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: путь к файлу пустой'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Проверяем, заблокирован ли файл
    if (!blockedPaths.contains(itemPath)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Файл не заблокирован'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      error = null;
    });

    try {
      final endpoint = '/security/unblock?path=${Uri.encodeQueryComponent(itemPath)}';
      final resp = await _conn.request('DELETE', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список заблокированных путей
      await _loadBlockedPaths();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Разблокировано: $name'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при разблокировке: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final bool isDir = item['isDirectory'] == true;
    final bool isDrive = item['isDrive'] == true;
    final String name = (item['name'] as String?) ?? 'file';
    final String itemPath = (item['path'] as String?) ?? '';

    // Нельзя удалять диски
    if (isDrive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить диск'),
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
          title: Text(isDir ? 'Удалить папку?' : 'Удалить файл?'),
          content: Text('Вы уверены, что хотите удалить "${name}"?${isDir ? '\n\nВнимание: это действие нельзя отменить.' : ''}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return; // Пользователь отменил
    }

    setState(() {
      error = null;
    });

    try {
      String endpoint;
      if (isDir) {
        // Удаление папки с рекурсивным удалением
        endpoint = '/fs/rmdir?path=${Uri.encodeQueryComponent(itemPath)}&recursive=true';
      } else {
        // Удаление файла
        endpoint = '/fs/rm?path=${Uri.encodeQueryComponent(itemPath)}';
      }

      final resp = await _conn.request('DELETE', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список файлов
      await _loadListing(currentPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isDir ? 'Папка' : 'Файл'} удален: $name'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при удалении: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showBlockedFilesDialog() async {
    // Загружаем актуальный список заблокированных файлов
    await _loadBlockedPaths();
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return _BlockedFilesDialog(
          connectionService: _conn,
          initialBlockedPaths: blockedPaths.toList(),
          onUpdate: () async {
            await _loadBlockedPaths();
            if (mounted) {
              setState(() {});
            }
          },
        );
      },
    );
    
    // Обновляем список после закрытия диалога
    await _loadBlockedPaths();
    if (mounted) {
      setState(() {});
    }
  }

  // Вверх на уровень (или к корню)
  Future<void> _goUp() async {
    if (pathStack.isEmpty) return; // уже в корне
    pathStack.removeLast();
    await _loadListing(currentPath);
  }

  Future<void> _jumpToIndex(int indexInclusive) async {
    // indexInclusive: индекс в визуальном списке крошек
    // 0 => "Этот компьютер" (null), 1 => 'C:\\', ...
    final crumbs = _crumbs();
    
    if (indexInclusive < 0 || indexInclusive >= crumbs.length) {
      return;
    }

    final target = crumbs[indexInclusive].path;

    // Очищаем стек
    pathStack.clear();

    // Если кликнули на корень (index 0), оставляем стек пустым
    if (target == null) {
      await _loadListing(null);
      return;
    }

    // Восстанавливаем путь: берём все крошки до индекса включительно (но пропускаем корень)
    // и добавляем их пути в стек
    for (int i = 1; i <= indexInclusive; i++) {
      final crumbPath = crumbs[i].path;
      if (crumbPath != null) {
        pathStack.add(crumbPath);
      }
    }

    await _loadListing(target);
  }

  // Структура крошки
  ({String label, String? path}) _crumbFor(String? path) {
    if (path == null || path.isEmpty) {
      return (label: 'Этот компьютер', path: null);
    }
    // Диск 'C:\\' -> 'C:'
    if (path.endsWith('\\') && !path.contains('\\', 3)) {
      // шаблон "X:\\"
      return (label: path.substring(0, 2), path: path);
    }
    // Иначе последнее имя
    final normalized = path.replaceAll('/', '\\');
    final parts = normalized.split('\\').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) {
      return (label: path, path: path);
    }
    return (label: parts.last, path: path);
  }

  // Построить список крошек из текущего стека
  List<({String label, String? path})> _crumbs() {
    final List<({String label, String? path})> result = <({String label, String? path})>[];
    // Корень всегда первый
    result.add(_crumbFor(null));
    for (final p in pathStack) {
      result.add(_crumbFor(p));
    }
    // Удалить дубликаты меток подряд (редко, но на всякий случай)
    return result;
  }

  Widget _buildBreadcrumbs() {
    final crumbs = _crumbs();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < crumbs.length; i++) ...[
            InkWell(
              onTap: () => _jumpToIndex(i),
              child: Row(
                children: [
                  if (i == 0)
                    const Icon(Icons.computer, size: 18)
                  else
                    const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    crumbs[i].label,
                    style: TextStyle(
                      color: i == crumbs.length - 1 ? Colors.grey : Theme.of(context).colorScheme.primary,
                      fontWeight: i == crumbs.length - 1 ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (i < crumbs.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.chevron_right, size: 18),
              ),
          ],
        ],
      ),
    );
    }

  Widget _buildEntryTile(Map<String, dynamic> item) {
    final isDir = item['isDirectory'] == true;
    final isDrive = item['isDrive'] == true;
    final name = (item['name'] as String?) ?? '';
    final modified = (item['modifiedUtc'] as String?) ?? '';
    final size = item['size'];
    final String itemPath = (item['path'] as String?) ?? '';
    final bool isBlocked = blockedPaths.contains(itemPath);

    IconData icon;
    if (isDrive) {
      icon = Icons.sd_storage;
    } else if (isDir) {
      icon = Icons.folder;
    } else {
      icon = Icons.insert_drive_file;
    }

    return ListTile(
      leading: Icon(
        icon,
        color: isBlocked ? Colors.red : null,
      ),
      title: Text(name),
      subtitle: Row(
        children: [
          if (isBlocked) ...[
            Icon(Icons.block, size: 14, color: Colors.red),
            const SizedBox(width: 4),
            const Text('Заблокировано', style: TextStyle(color: Colors.red)),
            const SizedBox(width: 8),
          ],
          if (isDir || isDrive)
            const Text('Папка')
          else
            Text(size == null ? 'Файл' : 'Файл • ${size.toString()} B'),
          if (modified.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(modified, style: const TextStyle(fontFeatures: [])),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 18,
            onSelected: (value) {
              if (value == 'block') {
                _blockPath(item);
              } else if (value == 'unblock') {
                _unblockPath(item);
              }
            },
            itemBuilder: (BuildContext context) => [
              if (!isBlocked)
                const PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Заблокировать'),
                    ],
                  ),
                ),
              if (isBlocked)
                const PopupMenuItem<String>(
                  value: 'unblock',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Разблокировать'),
                    ],
                  ),
                ),
            ],
            icon: const Icon(Icons.more_vert, size: 18),
          ),
          if (isDir || isDrive) 
            const Padding(
              padding: EdgeInsets.only(left: 2.0),
              child: Icon(Icons.chevron_right, size: 18),
            ),
        ],
      ),
      onTap: () => _enter(item),
      onLongPress: () => _deleteItem(item),
    );
  }

  Widget _buildSpecialFolders() {
    _loadSpecialFolders();
    if (specialFolders.isEmpty) {
      return const SizedBox.shrink();
    }

    // Маппинг названий папок на русские и иконки
    final folderConfig = {
      'desktop': (icon: Icons.desktop_windows, label: 'Рабочий стол'),
      'documents': (icon: Icons.description, label: 'Документы'),
      'pictures': (icon: Icons.image, label: 'Изображения'),
      'downloads': (icon: Icons.download, label: 'Загрузки'),
      'music': (icon: Icons.music_note, label: 'Музыка'),
      'videos': (icon: Icons.video_library, label: 'Видео'),
      'home': (icon: Icons.home, label: 'Домашняя папка'),
      'recent': (icon: Icons.access_time, label: 'Недавние'),
    };

    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: specialFolders.entries.map((entry) {
          final config = folderConfig[entry.key];
          if (config == null) return const SizedBox.shrink();

          final isActive = currentPath == entry.value;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => _navigateToSpecialFolder(entry.value),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 80,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      config.icon,
                      size: 24,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config.label,
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildBreadcrumbs()),
        ],),
        Divider(),
        _buildSpecialFolders(),
        Row(
          children: [
            IconButton(
              tooltip: 'Вверх',
              onPressed: pathStack.isEmpty ? null : _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(child: SizedBox()),
            IconButton(
              tooltip: 'Загрузить файл',
              onPressed: currentPath == null ? null : _uploadFile,
              icon: const Icon(Icons.upload_file),
            ),
            IconButton(
              tooltip: 'Создать папку',
              onPressed: currentPath == null ? null : _createDirectory,
              icon: const Icon(Icons.create_new_folder),
            ),
            IconButton(
              tooltip: 'Обновить',
              onPressed: () => _loadListing(currentPath),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Заблокированные файлы',
              onPressed: _showBlockedFilesDialog,
              icon: Icon(
                Icons.block,
                color: blockedPaths.isEmpty ? null : Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: error != null
              ? Center(child: Text('Ошибка: $error'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _buildEntryTile(entries[index]),
                ),
        ),
      ],
    );
  }
}

class _BlockedFilesDialog extends StatefulWidget {
  final ConnectionService connectionService;
  final List<String> initialBlockedPaths;
  final VoidCallback onUpdate;

  const _BlockedFilesDialog({
    required this.connectionService,
    required this.initialBlockedPaths,
    required this.onUpdate,
  });

  @override
  State<_BlockedFilesDialog> createState() => _BlockedFilesDialogState();
}

class _BlockedFilesDialogState extends State<_BlockedFilesDialog> {
  late List<String> blockedPaths;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    blockedPaths = List<String>.from(widget.initialBlockedPaths);
  }

  Future<void> _loadBlockedPaths() async {
    setState(() {
      isLoading = true;
    });

    try {
      final resp = await widget.connectionService.request('GET', '/security/blocked');
      if (resp.statusCode != 200) {
        return;
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] == 'ok' && body['data'] != null) {
        final List data = (body['data'] as List? ?? <dynamic>[]);
        setState(() {
          blockedPaths = data.map<String>((e) => e.toString()).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _unblockPath(String path) async {
    try {
      final endpoint = '/security/unblock?path=${Uri.encodeQueryComponent(path)}';
      final resp = await widget.connectionService.request('DELETE', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Ошибка: ${body['message'] ?? 'Unknown error'}');
      }

      // Обновляем список
      await _loadBlockedPaths();
      widget.onUpdate();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Разблокировано: ${path.split(RegExp(r'[/\\]')).last}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при разблокировке: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.block, color: Colors.red[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Заблокированные файлы',
              maxLines: 2,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            )
          ),


          if (isLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: blockedPaths.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.green[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет заблокированных файлов',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: blockedPaths.length,
                itemBuilder: (context, index) {
                  final path = blockedPaths[index];
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
                      icon: const Icon(Icons.lock_open, color: Colors.green),
                      onPressed: () => _unblockPath(path),
                      tooltip: 'Разблокировать',
                    ),
                    onTap: () => _unblockPath(path),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: isLoading ? null : _loadBlockedPaths,
          icon: const Icon(Icons.refresh),
          label: const Text('Обновить'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}