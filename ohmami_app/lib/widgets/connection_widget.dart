import 'dart:async';
import 'dart:ui';

import 'package:home_widget/home_widget.dart';
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../services/connection_service.dart';

class ConnectionWidget extends StatefulWidget {
  const ConnectionWidget({super.key});

  @override
  State<ConnectionWidget> createState() => _ConnectionWidgetState();
}

class _ConnectionWidgetState extends State<ConnectionWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _ipController =
      TextEditingController(text: 'http://192.168.1.10:8000');
  final TextEditingController _pairCodeController = TextEditingController();
  final List<String> _log = [];
  final List<Map<String, dynamic>> _remoteAgents = [];

  final ConnectionService _connectionService = ConnectionService();
  StreamSubscription? _wsSubscription;
  bool _useRemoteRelay = false;
  bool _isLoadingRemoteAgents = false;
  String? _selectedRemoteAgentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchAgents();
      _restoreRemoteSelection();
    });
  }

  String get _relayUrl => ConnectionService.defaultRelayUrl;

  Future<void> _restoreRemoteSelection() async {
    final selection = await _connectionService.loadRemoteSelection();
    if (!mounted) return;

    setState(() {
      final agentId = selection['agentId'];
      if (agentId != null && agentId.isNotEmpty) {
        _selectedRemoteAgentId = agentId;
      }
    });
  }

  Future<void> _searchAgents() async {
    setState(() {
      _log.insert(0, 'Searching local agents...');
    });

    try {
      final agents = await _connectionService.searchAgents();
      setState(() {
        if (agents.isEmpty) {
          _log.insert(0, 'No local agents found');
        } else {
          _ipController.text = agents.first;
          _log.insert(0, 'Found ${agents.length} local agent(s)');
          _log.insert(0, 'Selected local agent: ${agents.first}');
        }
      });
    } catch (e) {
      setState(() {
        _log.insert(0, 'Local search error: $e');
      });
    }
  }

  void _ping() async {
    try {
      _configureConnection();
      if (!_useRemoteRelay) {
        await HomeWidget.saveWidgetData<String>('base_url', _ipController.text.trim());
      }

      final isConnected = await _connectionService.ping();
      setState(() {
        _log.insert(0, 'PING: ${isConnected ? 'Connected' : 'Failed'}');
      });
    } catch (e) {
      setState(() {
        _log.insert(0, 'PING ERROR: $e');
      });
    }
  }

  void _connectWs() async {
    _configureConnection();
    await _connectionService.connectWs();
    setState(() {
      _log.insert(0, 'WS connected: ${_connectionService.isWebSocketConnected}');
    });

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

  void _configureConnection() {
    if (_useRemoteRelay) {
      final agentId = _selectedRemoteAgentId?.trim() ?? '';
      if (agentId.isEmpty) {
        throw Exception('Select a PC first');
      }
      _connectionService.setRemoteRelay(
        relayUrl: _relayUrl,
        agentId: agentId,
      );
    } else {
      _connectionService.setApiUrl(_ipController.text.trim());
    }
  }

  Future<void> _connectToRemoteAgent(Map<String, dynamic> agent) async {
    final agentId = agent['agentId']?.toString() ?? '';
    final online = agent['isOnline'] == true;
    if (agentId.trim().isEmpty) return;
    if (!online) {
      setState(() {
        _log.insert(0, 'PC is offline: $agentId');
      });
      return;
    }

    setState(() {
      _selectedRemoteAgentId = agentId;
      _log.insert(0, 'Connecting to ${agent['name'] ?? agentId} ($agentId)...');
    });

    await _connectionService.saveRemoteSelection(
      relayUrl: _relayUrl,
      agentId: agentId,
    );

    _connectionService.setRemoteRelay(relayUrl: _relayUrl, agentId: agentId);
    await _connectionService.connectWs();

    setState(() {
      _log.insert(0, 'WS connected: ${_connectionService.isWebSocketConnected}');
    });

    if (_connectionService.isWebSocketConnected && mounted) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  Future<void> _pairRemoteAgent() async {
    try {
      final code = _pairCodeController.text.trim();
      final agent = await _connectionService.pairRemoteAgent(
        relayUrl: _relayUrl,
        code: code,
      );

      setState(() {
        _selectedRemoteAgentId = agent['agentId']?.toString();
        _log.insert(0, 'Paired with ${agent['name']} (${agent['agentId']})');
      });

      await _connectionService.saveRemoteSelection(
        relayUrl: _relayUrl,
        agentId: _selectedRemoteAgentId?.trim() ?? '',
      );

      await _loadRemoteAgents();
    } catch (e) {
      setState(() {
        _log.insert(0, 'PAIR ERROR: $e');
      });
    }
  }

  Future<void> _loadRemoteAgents() async {
    if (_isLoadingRemoteAgents) return;
    setState(() {
      _isLoadingRemoteAgents = true;
      _log.insert(0, 'Loading my PCs...');
    });
    try {
      final agents = await _connectionService.fetchRemoteAgents(_relayUrl);
      setState(() {
        _remoteAgents
          ..clear()
          ..addAll(agents);
        _log.insert(0, 'Loaded ${agents.length} paired PC(s)');
        if ((_selectedRemoteAgentId == null || _selectedRemoteAgentId!.trim().isEmpty) &&
            agents.isNotEmpty) {
          _selectedRemoteAgentId = agents.first['agentId']?.toString();
        }
      });
    } catch (e) {
      setState(() {
        _log.insert(0, 'LOAD PCS ERROR: $e');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRemoteAgents = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _ipController.dispose();
    _pairCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: Colors.black),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                children: [
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
                          'Connection',
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
                SwitchListTile(
                  value: _useRemoteRelay,
                  onChanged: (value) async {
                    setState(() {
                      _useRemoteRelay = value;
                      if (!value) {
                        _remoteAgents.clear();
                        _selectedRemoteAgentId = null;
                      }
                    });
                    if (value) {
                      await _loadRemoteAgents();
                    }
                  },
                  title: const Text(
                    'Remote relay',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _useRemoteRelay ? 'HTTP/WS through VPS' : 'Local mDNS/direct LAN',
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                  activeColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_useRemoteRelay) ...[
                  const SizedBox(height: 12),
                  _buildInput(
                    controller: _pairCodeController,
                    label: 'Pairing code',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _GlassButton(
                      label: 'Pair with code',
                      onPressed: _pairRemoteAgent,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_useRemoteRelay) ...[
                  _buildInput(
                    controller: _ipController,
                    label: 'Agent base URL (http)',
                  ),
                ],
                const SizedBox(height: 16),
                if (_useRemoteRelay) ...[
                  SizedBox(
                    width: double.infinity,
                    child: _GlassButton(
                      label: _isLoadingRemoteAgents ? 'Loading...' : 'Refresh my PCs',
                      onPressed: _isLoadingRemoteAgents ? null : _loadRemoteAgents,
                      isLoading: _isLoadingRemoteAgents,
                    ),
                  ),
                  if (_remoteAgents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: ListView.builder(
                              itemCount: _remoteAgents.length,
                              itemBuilder: (context, idx) {
                                final agent = _remoteAgents[idx];
                                final agentId = agent['agentId']?.toString() ?? '';
                                final selected = (_selectedRemoteAgentId?.trim() ?? '') == agentId;
                                final online = agent['isOnline'] == true;

                                return ListTile(
                                  dense: true,
                                  selected: selected,
                                  selectedTileColor: Colors.white.withOpacity(0.12),
                                  onTap: () => _connectToRemoteAgent(agent),
                                  title: Text(
                                    agent['name']?.toString() ?? agentId,
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    online ? 'online' : 'offline',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: online ? Colors.greenAccent : Colors.white38,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'No paired PCs yet. Pair using a code above.',
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    ),
                  ],
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _GlassButton(
                          label: 'Ping',
                          onPressed: _ping,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GlassButton(
                          label: 'Connect WS',
                          onPressed: _connectWs,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _GlassButton(
                      label: _connectionService.isSearching
                          ? 'Searching...'
                          : 'Refresh local agents',
                      onPressed: _connectionService.isSearching ? null : _searchAgents,
                      isLoading: _connectionService.isSearching,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
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
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
  }) {
    return ClipRRect(
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
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.8)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
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
