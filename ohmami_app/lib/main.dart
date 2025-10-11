import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:multicast_dns/multicast_dns.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _ipController = TextEditingController(text: "http://192.168.1.10:8000");
  WebSocketChannel? _channel;
  final List<String> _log = [];
  final TextEditingController _cmdController = TextEditingController();
  bool _isSearching = false;

  Future<List<String>> discoverAgents() async {
    final MDnsClient client = MDnsClient();
    final List<String> discovered = [];

    try {
      await client.start();
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_ohmami._tcp.local'))) {
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))) {
            discovered.add('http://${ip.address.address}:${srv.port}');
          }
        }
      }
    } catch (e) {
      print("mDNS discovery error: $e");
    } finally {
      client.stop();
    }

    return discovered;
  }

  Future<void> _searchAgents() async {
    setState(() {
      _isSearching = true;
      _log.insert(0, "Searching for agents...");
    });

    try {
      final agents = await discoverAgents();
      setState(() {
        if (agents.isEmpty) {
          _log.insert(0, "No agents found");
        } else {
          // Записываем первого найденного агента в _ipController
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
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }


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
    final wsUrl = "${_ipController.text.trim().replaceFirst("http", "ws")}/ws";
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
  void initState() {
    super.initState();
    // Автоматический поиск агентов при запуске приложения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchAgents();
    });
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
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearching ? null : _searchAgents,
                child: _isSearching 
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
