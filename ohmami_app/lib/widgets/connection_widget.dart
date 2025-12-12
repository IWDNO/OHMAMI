import 'dart:async';
import 'package:flutter/material.dart';

import '../services/connection_service.dart'; 


class ConnectionWidget extends StatefulWidget {
  const ConnectionWidget({super.key});

  @override
  State<ConnectionWidget> createState() => _ConnectionWidgetState();
}

class _ConnectionWidgetState extends State<ConnectionWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _ipController = TextEditingController(text: "http://192.168.1.10:8000");
  final List<String> _log = [];
  
  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    // Автоматический поиск агентов при запуске приложения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchAgents();
    });

    _wsSubscription = _connectionService.wsMessages.stream.listen((message) {
      setState(() {
      });
    });
  }

  Future<void> _searchAgents() async {
    setState(() {
      _log.insert(0, "Searching for agents...");
    });

    try {
      final agents = await _connectionService.searchAgents();
      setState(() {
        if (agents.isEmpty) {
          _log.insert(0, "No agents found");
        } else {
          _ipController.text = agents.first;
          _log.insert(0, "Found ${agents.length} agent(s):");
          for (var agent in agents) {
            _log.insert(0, "  - $agent");
          }
          _log.insert(0, "Selected agent: ${agents.first}");
        }
      });
    } catch (e) {
      setState(() {
        _log.insert(0, "Error searching for agents: $e");
      });
    }
  }

  void _ping() async {    
    try {
      _connectionService.setApiUrl(_ipController.text.trim());
      final isConnected = await _connectionService.ping();
      setState(() {
        _log.insert(0, "PING: ${isConnected ? 'Connected' : 'Failed'}");
      });
    } catch (e) {
      setState(() {
        _log.insert(0, "PING ERROR: $e");
      });
    }
  }

  void _connectWs() {
    _connectionService.setApiUrl(_ipController.text.trim());
    _connectionService.connectWs();
    setState(() {
      _log.insert(0, 'ws is ${_connectionService.isWebSocketConnected}');
    });
  }

  @override
  void dispose() {
    super.dispose();
    _wsSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MaterialApp(
      title: 'Ohmami Minimal',
      home: Scaffold(
        appBar: AppBar(title: Text('Подключение')),
        body: Padding(
          padding: EdgeInsets.all(12),
          child: Column(children: [
            TextField(controller: _ipController, decoration: InputDecoration(labelText: "Agent base URL (http)")),
            SizedBox(height: 8),
            Row(children: [
              ElevatedButton(onPressed: _ping, child: Text("Ping!")),
              SizedBox(width: 8),
              ElevatedButton(onPressed: _connectWs, child: Text("Connect WS")),
            ]),
            Row(children: [
              ElevatedButton(
                onPressed: _connectionService.isSearching ? null : _searchAgents,
                child: _connectionService.isSearching 
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text("Searching..."),
                      ],
                    )
                  : Text("Refresh Agents")
              ),
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
