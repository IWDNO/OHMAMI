// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _ipController = TextEditingController(text: "http://192.168.1.10:8000");
  WebSocketChannel? _channel;
  List<String> _log = [];
  final TextEditingController _cmdController = TextEditingController();

  void _ping() async {
    final url = "${_ipController.text.trim()}/ping";
    try {
      final r = await http.get(Uri.parse(url)).timeout(Duration(seconds: 3));
      setState(() {
        _log.insert(0, "PING: ${r.statusCode} ${r.body}");
      });
    } catch (e) {
      setState(() {
        _log.insert(0, "PING ERROR: $e");
      });
    }
  }

  void _connectWs() {
    final wsUrl = _ipController.text.trim().replaceFirst("http", "ws") + "/ws";
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen((message) {
        setState(() {
          _log.insert(0, "WS <- $message");
        });
      }, onDone: () {
        setState(() {
          _log.insert(0, "WS closed");
          _channel = null;
        });
      }, onError: (e) {
        setState(() {
          _log.insert(0, "WS ERROR: $e");
        });
      });
      setState(() {
        _log.insert(0, "WS connected to $wsUrl");
      });
    } catch (e) {
      setState(() {
        _log.insert(0, "WS connect error: $e");
      });
    }
  }

  void _sendCmd() {
    final text = _cmdController.text.trim();
    if (_channel != null && text.isNotEmpty) {
      _channel!.sink.add(text);
      setState(() {
        _log.insert(0, "WS -> $text");
      });
      _cmdController.clear();
    } else {
      setState(() {
        _log.insert(0, "WS not connected or empty command");
      });
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ohmami Minimal',
      home: Scaffold(
        appBar: AppBar(title: Text('Ohmami — minimal')),
        body: Padding(
          padding: EdgeInsets.all(12),
          child: Column(children: [
            TextField(controller: _ipController, decoration: InputDecoration(labelText: "Agent base URL (http)")),
            SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: _ping, child: Text("Ping")),
              SizedBox(width: 8),
              ElevatedButton(onPressed: _connectWs, child: Text("Connect WS")),
            ]),
            SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _cmdController, decoration: InputDecoration(labelText: "Command to send via WS"))),
              SizedBox(width: 8),
              ElevatedButton(onPressed: _sendCmd, child: Text("Send")),
            ]),
            SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _log.length,
                itemBuilder: (context, idx) => ListTile(title: Text(_log[idx])),
              ),
            )
          ]),
        ),
      ),
    );
  }
}
