import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';


import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'agent_discovery.dart';

enum ConnectionMode {
  local,
  remote,
}

class ConnectionService extends ChangeNotifier {
  static const String defaultRelayUrl = 'http://38.99.23.186:8080';
  static const String _remoteDeviceIdKey = 'remote_device_id';
  static const String _remoteAccessTokenKey = 'remote_access_token';
  static const String _remoteRelayUrlKey = 'remote_relay_url';
  static const String _remoteSelectedAgentIdKey = 'remote_selected_agent_id';

  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  String? apiUrl;
  ConnectionMode connectionMode = ConnectionMode.local;
  String? remoteAgentId;
  String? _remoteDeviceId;
  String? _remoteAccessToken;
  bool isApiAvailable = false;
  bool isSearching = false;
  WebSocketChannel? webSocketChannel;
  StreamSubscription? webSocketSubscription;
  bool isWebSocketConnected = false;
  bool _shouldKeepConnected = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  final StreamController<String> wsMessages = StreamController<String>.broadcast();

  void setApiUrl(String url) {
    apiUrl = url;
    connectionMode = ConnectionMode.local;
    remoteAgentId = null;
    notifyListeners();
  }

  void setRemoteRelay({
    required String relayUrl,
    required String agentId,
  }) {
    apiUrl = relayUrl;
    remoteAgentId = agentId;
    connectionMode = ConnectionMode.remote;
    notifyListeners();
  }

  Future<void> saveRemoteSelection({
    required String relayUrl,
    required String agentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remoteRelayUrlKey, relayUrl);
    await prefs.setString(_remoteSelectedAgentIdKey, agentId);
  }

  Future<Map<String, String?>> loadRemoteSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'relayUrl': prefs.getString(_remoteRelayUrlKey),
      'agentId': prefs.getString(_remoteSelectedAgentIdKey),
    };
  }

  Future<List<String>> searchAgents() async {
    isSearching = true;
    notifyListeners();

    try {
      final agents = await AgentDiscovery.discoverAgents();
      if (agents.isNotEmpty) {
        setApiUrl(agents.first);
      }
      return agents;
    } finally {
      isSearching = false;
      notifyListeners();
    }
  }

  Future<bool> ping() async {
    if (apiUrl == null) return false;
    
    try {
      final response = connectionMode == ConnectionMode.remote
          ? remoteAgentId == null || remoteAgentId!.isEmpty
              ? await http.get(Uri.parse('$apiUrl/health')).timeout(const Duration(seconds: 5))
              : await request('GET', '/ping').timeout(const Duration(seconds: 5))
          : await http.get(
              Uri.parse('$apiUrl/ping'),
            ).timeout(const Duration(seconds: 3));
      
      isApiAvailable = response.statusCode == 200;
      notifyListeners();
      return isApiAvailable;
    } catch (e) {
      isApiAvailable = false;
      notifyListeners();
      return false;
    }
  }
  
  Future<http.Response> request(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (apiUrl == null) {
      throw Exception('Base URL not set');
    }

    if (connectionMode == ConnectionMode.remote) {
      final authHeaders = await _getRemoteAuthHeaders(apiUrl!);
      final agentId = remoteAgentId;
      if (agentId == null || agentId.isEmpty) {
        throw Exception('Remote agent ID not set');
      }

      final encodedAgentId = Uri.encodeComponent(agentId);
      final uri = Uri.parse('$apiUrl/agents/$encodedAgentId/proxy');
      final remoteBody = <String, Object?>{
        'method': method.toUpperCase(),
        'endpoint': endpoint,
        if (headers != null) 'headers': headers,
        if (body != null) 'body': _encodeRemoteBody(body),
      };

      return await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeaders,
        },
        body: json.encode(remoteBody),
      );
    }

    final uri = Uri.parse('$apiUrl$endpoint');
    
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

  Future<http.Response> uploadFile(
    String endpoint,
    File file, {
    Map<String, String>? fields,
  }) async {
    if (apiUrl == null) {
      throw Exception('Base URL not set');
    }

    if (connectionMode == ConnectionMode.remote) {
      throw Exception('Remote file upload is not implemented yet');
    }

    final uri = Uri.parse('$apiUrl$endpoint');
    
    final request = http.MultipartRequest('POST', uri);
    
    // Добавляем файл
    final fileStream = http.ByteStream(file.openRead());
    final fileLength = await file.length();
    final multipartFile = http.MultipartFile(
      'file',
      fileStream,
      fileLength,
      filename: file.path.split('/').last.split('\\').last,
    );
    request.files.add(multipartFile);
    
    // Добавляем дополнительные поля, если есть
    if (fields != null) {
      request.fields.addAll(fields);
    }
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    return response;
  }

  String? getWebSocketUrl() {
    if (apiUrl == null) return null;
    if (connectionMode == ConnectionMode.remote) {
      final agentId = remoteAgentId;
      if (agentId == null || agentId.isEmpty || _remoteDeviceId == null || _remoteAccessToken == null) return null;
      final encodedAgentId = Uri.encodeComponent(agentId);
      final encodedDeviceId = Uri.encodeComponent(_remoteDeviceId!);
      final encodedToken = Uri.encodeComponent(_remoteAccessToken!);
      return '${apiUrl!.replaceFirst('http', 'ws')}/clients/ws?agentId=$encodedAgentId&deviceId=$encodedDeviceId&token=$encodedToken';
    }
    return '${apiUrl!.replaceFirst('http', 'ws')}/ws';
  }

  Object? _encodeRemoteBody(Object body) {
    if (body is String) {
      try {
        return json.decode(body);
      } catch (_) {
        return body;
      }
    }
    return body;
  }
  
  Future<void> connectWs() async {        
    if (connectionMode == ConnectionMode.remote && apiUrl != null) {
      await _ensureRemoteIdentity(apiUrl!);
    }

    final wsUrl = getWebSocketUrl();
    if (wsUrl == null) return;

    try {
      webSocketChannel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 15),
      );
      isWebSocketConnected = true;
      _shouldKeepConnected = true;
      _clearReconnectTimer();
      _reconnectAttempts = 0;
      notifyListeners();

      webSocketSubscription = webSocketChannel!.stream.listen(
        (message) {
          try {
            try {
              final data = json.decode(message);
              print('WebSocket message received: $data');
              wsMessages.add(message.toString());
            } catch (_) {
              print('WebSocket raw message: $message');
              wsMessages.add(message.toString());
            }
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onDone: () {
          print('WebSocket disconnected');
          isWebSocketConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
        onError: (error) {
          print('WebSocket error: $error');
          isWebSocketConnected = false;
          notifyListeners();
          _scheduleReconnect();
        },
      );
      notifyListeners();
    } catch (error) {
      isWebSocketConnected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<List<Map<String, dynamic>>> fetchRemoteAgents(String relayUrl) async {
    final authHeaders = await _getRemoteAuthHeaders(relayUrl);
    final response = await http.get(
      Uri.parse('$relayUrl/mobile-devices/me/agents'),
      headers: authHeaders,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load agents: ${response.body}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = (decoded['data'] as List?) ?? const [];
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> pairRemoteAgent({
    required String relayUrl,
    required String code,
  }) async {
    final authHeaders = await _getRemoteAuthHeaders(relayUrl);
    final response = await http.post(
      Uri.parse('$relayUrl/mobile-devices/me/pair'),
      headers: {
        'Content-Type': 'application/json',
        ...authHeaders,
      },
      body: json.encode({'code': code}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to pair: ${response.body}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded['data'] as Map);
  }

  Future<Map<String, String>> _getRemoteAuthHeaders(String relayUrl) async {
    await _ensureRemoteIdentity(relayUrl);
    if (_remoteDeviceId == null || _remoteAccessToken == null) {
      throw Exception('Remote mobile identity is not initialized');
    }

    return {
      'X-Mobile-Device-Id': _remoteDeviceId!,
      'X-Mobile-Access-Token': _remoteAccessToken!,
    };
  }

  Future<void> _ensureRemoteIdentity(String relayUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final savedRelayUrl = prefs.getString(_remoteRelayUrlKey);
    _remoteDeviceId ??= prefs.getString(_remoteDeviceIdKey);
    _remoteAccessToken ??= prefs.getString(_remoteAccessTokenKey);

    if (_remoteDeviceId == null || _remoteDeviceId!.isEmpty) {
      _remoteDeviceId = _generateDeviceId();
      await prefs.setString(_remoteDeviceIdKey, _remoteDeviceId!);
    }

    if (_remoteAccessToken == null ||
        _remoteAccessToken!.isEmpty ||
        (savedRelayUrl != null && savedRelayUrl != relayUrl)) {
      await _registerRemoteDevice(relayUrl, prefs);
    }
  }

  Future<void> _registerRemoteDevice(String relayUrl, SharedPreferences prefs) async {
    final deviceId = _remoteDeviceId ?? _generateDeviceId();
    final response = await http.post(
      Uri.parse('$relayUrl/mobile-devices/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'deviceId': deviceId,
        'deviceName': _buildDeviceName(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to register mobile device: ${response.body}');
    }

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(decoded['data'] as Map);
    _remoteDeviceId = data['deviceId']?.toString() ?? deviceId;
    _remoteAccessToken = data['accessToken']?.toString();

    if (_remoteAccessToken == null || _remoteAccessToken!.isEmpty) {
      throw Exception('Relay did not return mobile access token');
    }

    await prefs.setString(_remoteDeviceIdKey, _remoteDeviceId!);
    await prefs.setString(_remoteAccessTokenKey, _remoteAccessToken!);
    await prefs.setString(_remoteRelayUrlKey, relayUrl);
  }

  String _generateDeviceId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _buildDeviceName() {
    if (kIsWeb) {
      return 'Web client';
    }

    if (Platform.isAndroid) {
      return 'Android phone';
    }
    if (Platform.isIOS) {
      return 'iPhone';
    }

    return 'Mobile device';
  }

    Future<void> disconnectWebSocket() async {
      _shouldKeepConnected = false;
      _clearReconnectTimer();
      webSocketSubscription?.cancel();
      webSocketSubscription = null;
      
      await webSocketChannel?.sink.close();
      webSocketChannel = null;
      isWebSocketConnected = false;
      notifyListeners();
    }

    void ensureConnected() {
      _shouldKeepConnected = true;
      if (!isWebSocketConnected) {
        connectWs();
      }
    }

    void _scheduleReconnect() {
      if (!_shouldKeepConnected) return;
      if (_reconnectTimer != null) return;

      // Exponential backoff with cap (1s, 2s, 5s, 10s, 20s, 30s)
      final delays = <int>[1, 2, 5, 10, 20, 30];
      final seconds = delays[(_reconnectAttempts).clamp(0, delays.length - 1)];
      _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 1000000);
      _reconnectTimer = Timer(Duration(seconds: seconds), () {
        _reconnectTimer = null;
        if (_shouldKeepConnected && !isWebSocketConnected) {
          connectWs();
        }
      });
    }

    void _clearReconnectTimer() {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
}
