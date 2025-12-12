import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../services/connection_service.dart';
import '../screens/home_screen.dart';


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
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    // Автоматический поиск агентов при запуске приложения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchAgents();
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
      HomeWidget.saveWidgetData<String>('base_url', _ipController.text.trim());
      final isConnected = await _connectionService.ping();
      setState(() {
        _isConnected = isConnected;
        _log.insert(0, "PING: ${isConnected ? 'Connected' : 'Failed'}");
      });
      
    } catch (e) {
      setState(() {
        _isConnected = false;
        _log.insert(0, "PING ERROR: $e");
      });
    }
  }

  void _connectWs() {
    _connectionService.setApiUrl(_ipController.text.trim());
    _connectionService.connectWs();
    setState(() {
      _isConnected = _connectionService.isWebSocketConnected;
      _log.insert(0, 'ws is ${_connectionService.isWebSocketConnected}');
    });
    
    // Переход на главный экран после успешного подключения WebSocket
    if (_connectionService.isWebSocketConnected && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
    _wsSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Заголовок с glassmorphism
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: const Text(
                          'Подключение',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Поле ввода с glassmorphism
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: TextField(
                        controller: _ipController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Agent base URL (http)",
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Кнопки с glassmorphism
                Row(
                  children: [
                    Expanded(
                      child: _GlassButton(
                        label: "Ping!",
                        onPressed: _ping,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GlassButton(
                        label: "Подключить WS",
                        onPressed: _connectWs,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _GlassButton(
                    label: _connectionService.isSearching ? "Поиск..." : "Перезапустить Агента",
                    onPressed: _connectionService.isSearching ? null : _searchAgents,
                    isLoading: _connectionService.isSearching,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Лог с glassmorphism
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                        ),
                        child: ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: _log.length,
                          itemBuilder: (context, idx) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: Text(
                              _log[idx],
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
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
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GlassButton({
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                        color: Colors.white.withOpacity(onPressed == null ? 0.05 : 0.15),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: onPressed == null
                            ? Colors.white.withOpacity(0.5)
                            : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

