import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class BlockedSitesWidget extends StatefulWidget {
  const BlockedSitesWidget({super.key});

  @override
  State<BlockedSitesWidget> createState() => _BlockedSitesWidgetState();
}

class _BlockedSitesWidgetState extends State<BlockedSitesWidget> {
  final ConnectionService _conn = ConnectionService();
  final TextEditingController _domainController = TextEditingController();

  List<String> _blockedSites = [];
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBlockedSites();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _loadBlockedSites() async {
    setState(() {
      _error = null;
      _isLoading = true;
    });

    try {
      final resp = await _conn.request('GET', '/security/blocked-sites');
      if (resp.statusCode != 200) {
        if (resp.statusCode == 404) {
          throw Exception('Endpoint не найден. Убедитесь, что сервер перезапущен и HostsController зарегистрирован.');
        }
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception('Status: ${body['status']}');
      }

      final List data = (body['data'] as List? ?? <dynamic>[]);
      setState(() {
        _blockedSites = data.map<String>((e) => e.toString()).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _blockSite() async {
    final domain = _domainController.text.trim();
    if (domain.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите домен для блокировки'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Проверяем, не заблокирован ли уже сайт
    if (_blockedSites.contains(domain.toLowerCase())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сайт уже заблокирован'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _error = null;
    });

    try {
      final endpoint = '/security/block-site?domain=${Uri.encodeQueryComponent(domain)}';
      final resp = await _conn.request('POST', endpoint);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      if (body['status'] != 'ok') {
        throw Exception(body['message'] ?? 'Ошибка блокировки');
      }

      _domainController.clear();
      await _loadBlockedSites();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Заблокирован: $domain'),
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
          content: Text('Ошибка при блокировке: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _unblockSite(String domain) async {
    final trimmedDomain = domain.trim();
    if (trimmedDomain.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: домен пустой'),
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
          content: Text('Вы уверены, что хотите разблокировать:\n$trimmedDomain'),
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
      final endpoint = '/security/unblock-site?domain=${Uri.encodeQueryComponent(trimmedDomain)}';
      final resp = await _conn.request('DELETE', endpoint);

      Map<String, dynamic>? body;
      try {
        body = json.decode(resp.body) as Map<String, dynamic>;
      } catch (_) {}

      if (resp.statusCode != 200) {
        String errorMessage = 'HTTP ${resp.statusCode}';
        if (body != null && body['message'] != null) {
          errorMessage = body['message'] as String;
        } else if (resp.body.isNotEmpty) {
          errorMessage = resp.body;
        }

        if (errorMessage.toLowerCase().contains('unauthorized') ||
            errorMessage.toLowerCase().contains('unauthorized operation') ||
            errorMessage.toLowerCase().contains('доступ запрещен') ||
            resp.statusCode == 403) {
          errorMessage = 'Недостаточно прав для выполнения операции. Требуются права администратора.';
        }

        throw Exception(errorMessage);
      }

      if (body != null && body['status'] != 'ok') {
        String errorMessage = body['message'] ?? 'Ошибка разблокировки';

        if (errorMessage.toLowerCase().contains('unauthorized') ||
            errorMessage.toLowerCase().contains('unauthorized operation') ||
            errorMessage.toLowerCase().contains('доступ запрещен')) {
          errorMessage = 'Недостаточно прав для выполнения операции. Требуются права администратора.';
        }

        throw Exception(errorMessage);
      }

      await _loadBlockedSites();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Разблокирован: $trimmedDomain'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String errorMessage = e.toString();
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

  Widget _buildBlockedSiteItem(String domain) {
    return ListTile(
      leading: Icon(
        Icons.block,
        color: Colors.red[700],
      ),
      title: Text(domain),
      trailing: IconButton(
        icon: const Icon(Icons.lock_open),
        color: Colors.green,
        onPressed: () => _unblockSite(domain),
        tooltip: 'Разблокировать',
      ),
      onTap: () => _unblockSite(domain),
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
                const Expanded(
                  child: Text(
                    'Заблокированные сайты',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _loadBlockedSites,
                  tooltip: 'Обновить список',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Add domain field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _domainController,
                    decoration: InputDecoration(
                      hintText: 'Введите домен (например: example.com)',
                      prefixIcon: const Icon(Icons.language),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSubmitted: (_) => _blockSite(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _blockSite,
                  icon: const Icon(Icons.block),
                  label: const Text('Заблокировать'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Blocked sites list
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
                              onPressed: _loadBlockedSites,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Повторить'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _blockedSites.isEmpty
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
                                  'Нет заблокированных сайтов',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _blockedSites.length,
                          itemBuilder: (context, index) => _buildBlockedSiteItem(_blockedSites[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

