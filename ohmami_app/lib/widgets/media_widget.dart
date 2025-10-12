import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/connection_service.dart';

class MediaWidget extends StatefulWidget {
  const MediaWidget({super.key});

  @override
  State<MediaWidget> createState() => _MediaWidgetState();
}

class _MediaWidgetState extends State<MediaWidget> {
  final ConnectionService _connectionService = ConnectionService();

  Map<String, dynamic>? _mediaInfo;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMediaInfo();
  }

  Future<void> _loadMediaInfo() async {
    if (_connectionService.baseUrl == null) {
      setState(() {
        _error = 'No agent connected';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _connectionService.request('GET', '/media/info');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _mediaInfo = data['data'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load media info: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _play() async {
    await _sendMediaCommand('/media/play', 'Playback started');
  }

  Future<void> _pause() async {
    await _sendMediaCommand('/media/pause', 'Playback paused');
  }

  Future<void> _next() async {
    await _sendMediaCommand('/media/next', 'Skipped to next track');
  }

  Future<void> _previous() async {
    await _sendMediaCommand('/media/previous', 'Skipped to previous track');
  }

  Future<void> _sendMediaCommand(String endpoint, String successMessage) async {
    if (_connectionService.baseUrl == null) {
      setState(() {
        _error = 'No agent connected';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _connectionService.request('POST', endpoint);

      if (response.statusCode == 200) {
        await _loadMediaInfo(); // refresh
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      } else {
        setState(() {
          _error = 'Failed to execute command: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  String get _title {
    return _mediaInfo?['title'] ?? 'Unknown Title';
  }

  String get _artist {
    return _mediaInfo?['artist'] ?? 'Unknown Artist';
  }

  String get _album {
    return _mediaInfo?['album'] ?? 'Unknown Album';
  }

  String get _status {
    return _mediaInfo?['status'] ?? 'Unknown';
  }

  bool get _isPlaying {
    return _mediaInfo?['status'] == 'playing';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _isLoading ? null : _loadMediaInfo,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Media Info Card
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          color: _isPlaying ? Colors.green : Colors.grey,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _artist,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _album,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isPlaying ? Colors.green : Colors.grey,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Control Buttons
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'Media Controls',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Main control buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Previous button
                        FloatingActionButton(
                          heroTag: 'previous',
                          onPressed: _isLoading ? null : _previous,
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.skip_previous, color: Colors.white),
                        ),
                        
                        // Play/Pause button
                        FloatingActionButton.large(
                          heroTag: 'play_pause',
                          onPressed: _isLoading ? null : (_isPlaying ? _pause : _play),
                          backgroundColor: _isPlaying ? Colors.orange : Colors.green,
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        
                        // Next button
                        FloatingActionButton(
                          heroTag: 'next',
                          onPressed: _isLoading ? null : _next,
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.skip_next, color: Colors.white),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Error display
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Quick actions
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _play,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
