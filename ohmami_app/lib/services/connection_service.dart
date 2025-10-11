import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'agent_discovery.dart';

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  String? _baseUrl;
  bool _isConnected = false;
  bool _isSearching = false;

  String? get baseUrl => _baseUrl;
  bool get isConnected => _isConnected;
  bool get isSearching => _isSearching;

  /// Установить базовый URL агента
  void setBaseUrl(String url) {
    _baseUrl = url;
    notifyListeners();
  }

  /// Поиск агентов через mDNS
  Future<List<String>> searchAgents() async {
    _isSearching = true;
    notifyListeners();

    try {
      final agents = await AgentDiscovery.discoverAgents();
      if (agents.isNotEmpty) {
        _baseUrl = agents.first;
      }
      return agents;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Проверить подключение к агенту
  Future<bool> ping() async {
    if (_baseUrl == null) return false;
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ping'),
      ).timeout(const Duration(seconds: 3));
      
      _isConnected = response.statusCode == 200;
      notifyListeners();
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  /// Выполнить HTTP запрос к агенту
  Future<http.Response> request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (_baseUrl == null) {
      throw Exception('Base URL not set');
    }

    final uri = Uri.parse('$_baseUrl$endpoint');
    
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(uri, headers: headers, body: body);
      case 'PUT':
        return await http.put(uri, headers: headers, body: body);
      case 'DELETE':
        return await http.delete(uri, headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }

  /// Получить WebSocket URL
  String? getWebSocketUrl() {
    if (_baseUrl == null) return null;
    return '${_baseUrl!.replaceFirst('http', 'ws')}/ws';
  }
}
