import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart' as md;
import '../services/docs_service.dart';

class DocsScreen extends StatefulWidget {
  final String? initialPath;

  const DocsScreen({super.key, this.initialPath});

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  String _currentPath = 'README.md';
  String _markdownContent = '';
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _currentPath = widget.initialPath!;
    }
    _loadMarkdown(_currentPath);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMarkdown(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Извлекаем якорь из пути, если есть
      String filePath = path;
      String? anchor;
      if (path.contains('#')) {
        final parts = path.split('#');
        filePath = parts[0];
        anchor = parts[1];
      }

      String content = await DocsService.loadMarkdown(filePath);
      
      // Обрабатываем ссылки для внутренней навигации
      content = DocsService.processMarkdownLinks(content, filePath);
      
      setState(() {
        _markdownContent = content;
        _currentPath = filePath;
        _isLoading = false;
      });

      // Прокручиваем к якорю после загрузки, если он указан
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAnchor(anchor!);
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _scrollToAnchor(String anchor) {
    // Простая реализация прокрутки к якорю
    // В реальном приложении можно использовать более сложную логику
    // для поиска заголовков с соответствующим id
    Future.delayed(const Duration(milliseconds: 300), () {
      // Прокручиваем немного вниз (можно улучшить, найдя точную позицию)
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          200, // Примерное значение, можно улучшить
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _handleLinkTap(String? url, String? title, String? href) {
    if (href == null) return;

    // Проверяем, является ли это внутренней ссылкой документации
    if (href.startsWith('docs://')) {
      // Извлекаем полный путь с якорем
      String fullPath = href.substring(7);
      
      // Навигация к другой странице документации
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DocsScreen(initialPath: fullPath),
        ),
      );
      return;
    }

    // Если это внешняя ссылка, открываем в браузере
    if (href.startsWith('http://') || href.startsWith('https://')) {
      // Можно использовать url_launcher для открытия в браузере
      // Пока просто показываем сообщение
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Внешняя ссылка: $href'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Заголовок с кнопкой назад
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: const Text(
                              'Документация',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Контент
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Ошибка загрузки документации',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () => _loadMarkdown(_currentPath),
                                  child: const Text('Повторить'),
                                ),
                              ],
                            ),
                          )
                        : Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  child: md.MarkdownBody(
                                    data: _markdownContent,
                                    selectable: true,
                                    styleSheet: md.MarkdownStyleSheet(
                                  h1: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  h2: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  h3: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  h4: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  p: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.5,
                                  ),
                                  a: const TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                  code: TextStyle(
                                    color: Colors.green.shade300,
                                    backgroundColor: Colors.black.withOpacity(0.3),
                                    fontFamily: 'monospace',
                                  ),
                                  codeblockDecoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  blockquote: TextStyle(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  blockquoteDecoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    border: Border(
                                      left: BorderSide(
                                        color: Colors.blue,
                                        width: 4,
                                      ),
                                    ),
                                  ),
                                  tableHead: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  tableBody: const TextStyle(
                                    color: Colors.white,
                                  ),
                                  tableBorder: TableBorder.all(
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  listBullet: const TextStyle(
                                    color: Colors.white,
                                  ),
                                  strong: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  em: const TextStyle(
                                    color: Colors.white,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  ),
                                    onTapLink: (text, href, title) {
                                      _handleLinkTap(text, title, href);
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
