import 'dart:async';
import 'dart:typed_data';

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
  StreamSubscription? _wsSubscription;

  Map<String, dynamic>? _mediaInfo;

  @override
  void initState() {
    super.initState();
    _loadMediaInfo();

    _wsSubscription = _connectionService.wsMessages.stream.listen((message) {
      if (mounted) {
        try {
          final decoded = json.decode(message);
          if (decoded is Map && decoded['type'] == 'media_update') {
            setState(() {
              _mediaInfo = decoded['payload'];
            });
          }
        } catch (e) {
          print('Error parsing WebSocket message: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMediaInfo() async {
    if (_connectionService.apiUrl == null) {
      return;
    }

    try {
      final response = await _connectionService.request('GET', '/media/info');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _mediaInfo = data['data'];
          });
        }
      } 
    } catch (e) {
      print('Error loading media info: $e');
    }
  }

  Future<void> _play() async {
    await _request('/media/play');
  }

  Future<void> _pause() async {
    await _request('/media/pause');
  }

  Future<void> _next() async {
    await _request('/media/next');
  }

  Future<void> _previous() async {
    await _request('/media/previous');
  }

  Future<void> _request(String endpoint) async {
    final response = await _connectionService.request('POST', endpoint);
    if (response.statusCode == 200) {
      await Future.delayed(const Duration(milliseconds: 100)); //FIXME иначе не успевает обновиться
      await _loadMediaInfo();
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
    return _mediaInfo?['playbackStatus'] ?? _mediaInfo?['status'] ?? 'Unknown';
  }

  bool get _isPlaying {
    final status = _status.toLowerCase();
    return status.contains('playing');
  }

  String? get _thumbnailBase64 {
    return _mediaInfo?['thumbnailBase64'];
  }

  Widget _buildThumbnail() {
    final thumbnail = _thumbnailBase64;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      try {
        final bytes = base64.decode(thumbnail);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultIcon();
            },
          ),
        );
      } catch (e) {
        return _buildDefaultIcon();
      }
    }
    return _buildDefaultIcon();
  }

  Widget _buildDefaultIcon() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.music_note,
        color: _isPlaying ? Colors.green : Colors.grey,
        size: 32,
      ),
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
            // Media Info with thumbnail
            Row(
              children: [
                // Thumbnail
                _buildThumbnail(),
                const SizedBox(width: 16),
                
                // Media info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 16,
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
                
                // Refresh button
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadMediaInfo,
                  tooltip: 'Обновить',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Previous button
                IconButton(
                  onPressed: _previous,
                  icon: const Icon(Icons.skip_previous),
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[700],
                  ),
                ),
                
                // Play/Pause button
                IconButton(
                  onPressed: (_isPlaying ? _pause : _play),
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  iconSize: 40,
                  style: IconButton.styleFrom(
                    backgroundColor: _isPlaying ? Colors.orange[100] : Colors.green[100],
                    foregroundColor: _isPlaying ? Colors.orange[700] : Colors.green[700],
                  ),
                ),
                
                // Next button
                IconButton(
                  onPressed: _next,
                  icon: const Icon(Icons.skip_next),
                  iconSize: 32,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
