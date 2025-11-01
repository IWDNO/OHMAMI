import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';



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

  String? get currentPath => pathStack.isEmpty ? null : pathStack.last;

  @override
  void initState() {
    super.initState();
    _loadListing(null);
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

    final shareParams = ShareParams(
      text: 'Вот файл: $filename',
      files: [XFile(savePath, name: filename)],
    );

    await SharePlus.instance.share(shareParams);

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

  // Вверх на уровень (или к корню)
  Future<void> _goUp() async {
    if (pathStack.isEmpty) return; // уже в корне
    pathStack.removeLast();
    await _loadListing(currentPath);
  }

  // Переход по крошке (на произвольный уровень)
  Future<void> _jumpToIndex(int indexInclusive) async {
    // indexInclusive: индекс в визуальном списке крошек
    // 0 => "Этот компьютер" (null), 1 => 'C:\\', ...
    final target = _crumbs()[indexInclusive].path;
    pathStack
      ..clear()
      ..addAll(_crumbs()
          .where((c) => c.path != null)
          .map((c) => c.path))
      ..retainWhere((p) {
        // оставить до требуемого
        if (target == null) return false;
        return true;
      });

    // Правильнее — просто пересобрать стек по target:
    pathStack
      .clear();
    if (target != null) {
      pathStack.add(target);
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

    IconData icon;
    if (isDrive) {
      icon = Icons.sd_storage;
    } else if (isDir) {
      icon = Icons.folder;
    } else {
      icon = Icons.insert_drive_file;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(name),
      subtitle: Row(
        children: [
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
      trailing: isDir || isDrive ? const Icon(Icons.chevron_right) : null,
      onTap: () => _enter(item),
      onLongPress: () => _deleteItem(item),
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