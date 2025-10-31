import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/connection_service.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';


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

  // Переход вниз: в диск/директорию
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

    final dir = await getApplicationDocumentsDirectory();
    final savePath = '${dir.path}/$filename';

    final file = File(savePath);
    await file.writeAsBytes(bytes);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранено: $savePath')),
    );

    // --- Новый рекомендуемый способ шаринга через SharePlus.instance.share ---
    // Опционально можно задать позицию происхождения (для планшетов/поповеров)
    final shareParams = ShareParams(
      text: 'Вот файл: $filename',
      files: [XFile(savePath, name: filename)],
      // sharePositionOrigin: box != null ? (box.localToGlobal(Offset.zero) & box.size) : null,
    );

    final ShareResult result = await SharePlus.instance.share(shareParams);

    // Можно показать результат (необязательно)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share result: ${result.status}')),
    );
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Панель управления
        Row(
          children: [
            IconButton(
              tooltip: 'Вверх',
              onPressed: pathStack.isEmpty ? null : _goUp,
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(child: _buildBreadcrumbs()),
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