import 'package:http/http.dart' as http;

class DocsService {
  // Используем GitHub Pages для загрузки через raw.githubusercontent.com
  static const String _githubRawBaseUrl = 'https://raw.githubusercontent.com/iwdno/OHMAMI/dev/docs';

  /// Загружает markdown файл с хостинга
  /// [path] - путь к файлу относительно папки docs (например: 'getting-started/overview.md' или 'getting-started/overview')
  static Future<String> loadMarkdown(String path) async {
    try {
      // Убираем начальный слеш, если есть
      String cleanPath = path.startsWith('/') ? path.substring(1) : path;
      
      // Если путь не заканчивается на .md, добавляем его
      if (!cleanPath.endsWith('.md') && !cleanPath.contains('.')) {
        cleanPath = '$cleanPath.md';
      }
      
      // Формируем URL для загрузки из GitHub raw
      final url = '$_githubRawBaseUrl/$cleanPath';
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to load markdown: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading markdown: $e');
    }
  }

  /// Преобразует относительные ссылки в markdown в пути для загрузки
  /// Обрабатывает ссылки формата docsify: /getting-started/installation
  /// Например: '../user-guide/navigation.md' -> 'user-guide/navigation.md'
  /// Например: '/getting-started/installation' -> 'getting-started/installation.md'
  static String normalizePath(String currentPath, String linkPath) {
    // Если ссылка уже полная или внешняя, возвращаем как есть
    if (linkPath.startsWith('http://') || linkPath.startsWith('https://')) {
      return linkPath;
    }

    // Убираем якорь из ссылки (например, /reference/api/http#управление-безопасностью)
    String linkWithoutAnchor = linkPath;
    if (linkPath.contains('#')) {
      linkWithoutAnchor = linkPath.substring(0, linkPath.indexOf('#'));
    }

    // Убираем начальный слеш
    String cleanLink = linkWithoutAnchor.startsWith('/') ? linkWithoutAnchor.substring(1) : linkWithoutAnchor;
    
    // Если ссылка начинается с #/, это docsify путь - преобразуем в markdown путь
    if (cleanLink.startsWith('#/')) {
      cleanLink = cleanLink.substring(2);
    }

    // Если ссылка абсолютная (начинается с /) - это docsify формат
    if (linkWithoutAnchor.startsWith('/')) {
      // Добавляем .md если его нет и это не изображение/другой файл
      if (!cleanLink.contains('.') && !cleanLink.endsWith('/')) {
        cleanLink = '$cleanLink.md';
      }
      return cleanLink;
    }

    // Если ссылка относительная (начинается с ../)
    if (cleanLink.startsWith('../')) {
      // Убираем .md из currentPath для вычисления директории
      String currentDirPath = currentPath;
      if (currentDirPath.endsWith('.md')) {
        currentDirPath = currentDirPath.substring(0, currentDirPath.lastIndexOf('/'));
      } else {
        currentDirPath = currentDirPath.substring(0, currentDirPath.lastIndexOf('/'));
      }
      
      cleanLink = cleanLink.replaceFirst('../', '');
      
      // Поднимаемся на уровень выше для каждого ../
      int levelsUp = 0;
      while (cleanLink.startsWith('../')) {
        levelsUp++;
        cleanLink = cleanLink.replaceFirst('../', '');
      }
      
      var pathParts = currentDirPath.split('/').where((p) => p.isNotEmpty).toList();
      for (int i = 0; i < levelsUp && pathParts.isNotEmpty; i++) {
        pathParts.removeLast();
      }
      
      // Добавляем .md если его нет и это не изображение/другой файл
      if (!cleanLink.contains('.') && !cleanLink.endsWith('/')) {
        cleanLink = '$cleanLink.md';
      }
      
      if (pathParts.isNotEmpty) {
        return '${pathParts.join('/')}/$cleanLink';
      } else {
        return cleanLink;
      }
    }

    // Если ссылка относительная в той же папке
    String currentDir = '';
    if (currentPath.contains('/')) {
      currentDir = currentPath.substring(0, currentPath.lastIndexOf('/'));
    }
    
    // Добавляем .md если его нет и это не изображение/другой файл
    if (!cleanLink.contains('.') && !cleanLink.endsWith('/')) {
      cleanLink = '$cleanLink.md';
    }
    
    if (currentDir.isNotEmpty) {
      return '$currentDir/$cleanLink';
    }
    
    return cleanLink;
  }

  /// Преобразует ссылки в markdown для работы с внутренней навигацией
  /// Заменяет относительные пути на специальные ссылки, которые будут обработаны в приложении
  static String processMarkdownLinks(String markdown, String currentPath) {
    // Регулярное выражение для поиска markdown ссылок [текст](путь)
    final linkPattern = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    
    // Регулярное выражение для поиска изображений ![alt](путь)
    final imagePattern = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');
    
    // Обрабатываем изображения - преобразуем относительные пути в абсолютные URL
    markdown = markdown.replaceAllMapped(imagePattern, (match) {
      final altText = match.group(1) ?? '';
      var imagePath = match.group(2)!;
      
      // Если это уже абсолютный URL, оставляем как есть
      if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
        return match.group(0)!;
      }
      
      // Преобразуем относительный путь в абсолютный URL для GitHub raw
      final normalizedPath = normalizePath(currentPath, imagePath);
      final imageUrl = '$_githubRawBaseUrl/$normalizedPath';
      
      return '![$altText]($imageUrl)';
    });
    
    // Обрабатываем ссылки
    return markdown.replaceAllMapped(linkPattern, (match) {
      final linkText = match.group(1)!;
      var linkPath = match.group(2)!;
      
      // Если это внешняя ссылка или mailto, оставляем как есть
      if (linkPath.startsWith('http://') || 
          linkPath.startsWith('https://') || 
          linkPath.startsWith('mailto:')) {
        return match.group(0)!;
      }
      
      // Если это якорь на текущей странице (#section), оставляем как есть
      if (linkPath.startsWith('#') && !linkPath.startsWith('#/')) {
        return match.group(0)!;
      }
      
      // Преобразуем путь (включая якорные ссылки вида /path#anchor)
      final normalizedPath = normalizePath(currentPath, linkPath);
      
      // Сохраняем якорь, если он был
      String finalPath = normalizedPath;
      if (linkPath.contains('#') && !linkPath.startsWith('#')) {
        final anchor = linkPath.substring(linkPath.indexOf('#'));
        finalPath = '$normalizedPath$anchor';
      }
      
      // Создаём специальную ссылку для внутренней навигации
      // Используем специальный протокол для обработки в приложении
      return '[$linkText](docs://$finalPath)';
    });
  }

  /// Извлекает путь из специальной ссылки docs://
  /// Возвращает путь без якоря для загрузки файла
  static String? extractDocsPath(String url) {
    if (url.startsWith('docs://')) {
      String path = url.substring(7);
      // Убираем якорь, если есть
      if (path.contains('#')) {
        path = path.substring(0, path.indexOf('#'));
      }
      return path;
    }
    return null;
  }
}

