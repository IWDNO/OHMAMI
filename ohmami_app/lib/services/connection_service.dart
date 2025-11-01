import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'agent_discovery.dart';

class ConnectionService extends ChangeNotifier {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();

  String? apiUrl;
  bool isApiAvailable = false;
  bool isSearching = false;
  WebSocketChannel? webSocketChannel;
  StreamSubscription? webSocketSubscription;
  bool isWebSocketConnected = false;

  final StreamController<String> wsMessages = StreamController<String>.broadcast();

  void setApiUrl(String url) {
    apiUrl = url;
    notifyListeners();
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
      final response = await http.get(
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
    return '${apiUrl!.replaceFirst('http', 'ws')}/ws';
  }
  
  Future<void> connectWs() async {        
    final wsUrl = getWebSocketUrl();
    if (wsUrl == null) return;

    try {
      webSocketChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      isWebSocketConnected = true;
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
          //TODO: add reconnect logic
        },
        onError: (error) {
          print('WebSocket error: $error');
          isWebSocketConnected = false;
          notifyListeners();
          //TODO: add reconnect logic
        },
      );
      notifyListeners();
    } catch (error) {
      isWebSocketConnected = false;
      notifyListeners();
    }
  }

    Future<void> disconnectWebSocket() async {
      webSocketSubscription?.cancel();
      webSocketSubscription = null;
      
      await webSocketChannel?.sink.close();
      webSocketChannel = null;
      isWebSocketConnected = false;
      notifyListeners();
    }
}
