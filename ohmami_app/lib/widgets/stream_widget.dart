import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';

const appId = "5104f95fdd824c20a2610f909c1a0c6b";
const token = "";

class StreamWidget extends StatefulWidget {
  const StreamWidget({super.key});

  @override
  State<StreamWidget> createState() => _StreamWidgetState();
}

class _StreamWidgetState extends State<StreamWidget> {
  int? _remoteUid;
  RtcEngine? _engine;
  String? _channelId;
  bool _isStreamActive = false;
  bool _isLoading = false;
  final ConnectionService _connectionService = ConnectionService();

  @override
  void initState() {
    super.initState();
    _initAgora();
  }

  // Метод для изменения ориентации экрана
  void _setOrientation(bool isVideoPlaying) {
    if (isVideoPlaying) {
      // Горизонтальная ориентация при наличии видео
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      // Вертикальная ориентация когда видео нет
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _initAgora() async {
    if (_engine != null) return;

    //create the engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("local user ${connection.localUid} joined");
          setState(() {});
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          setState(() {
            _remoteUid = remoteUid;
            _setOrientation(true); // Поворачиваем экран при получении видео
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left channel");
          setState(() {
            _remoteUid = null;
            _setOrientation(false); // Возвращаем вертикальную ориентацию
          });
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          debugPrint(
              '[onTokenPrivilegeWillExpire] connection: ${connection.toJson()}, token: $token');
        },
      ),
    );

    // Роль на audience (только получение данных)
    await _engine!.setClientRole(role: ClientRoleType.clientRoleAudience);
    await _engine!.enableVideo();
  }

  Future<void> _startStream() async {
    if (_isLoading || _isStreamActive) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Отправляем запрос на начало стрима
      final response = await _connectionService.request(
        'POST',
        '/stream/start',
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'ok' && responseData['data'] != null) {
          final channelId = responseData['data']['channelId'] as String;
          
          setState(() {
            _channelId = channelId;
            _isStreamActive = true;
            _isLoading = false;
          });

          // Подключаемся к каналу Agora
          if (_engine != null) {
            await _engine!.joinChannel(
              token: token,
              channelId: channelId,
              uid: 0,
              options: const ChannelMediaOptions(),
            );
          }
        } else {
          throw Exception(responseData['message'] ?? 'Failed to start stream');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to start stream');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting stream: $e')),
        );
      }
    }
  }

  Future<void> _stopStream() async {
    if (_isLoading || !_isStreamActive || _channelId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Отправляем запрос на остановку стрима
      final response = await _connectionService.request(
        'POST',
        '/stream/stop?channelId=$_channelId',
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        // Отключаемся от канала Agora
        if (_engine != null) {
          await _engine!.leaveChannel();
        }

        setState(() {
          _isStreamActive = false;
          _channelId = null;
          _remoteUid = null;
          _isLoading = false;
        });
        
        _setOrientation(false);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to stop stream');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping stream: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
    // Восстанавливаем все ориентации при закрытии приложения
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _dispose();
  }

  Future<void> _dispose() async {
    if (_engine != null) {
      await _engine!.leaveChannel();
      await _engine!.release();
      _engine = null;
    }
  }

  // Create UI with local view and remote view
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: !_isStreamActive
          ? AppBar(
              title: const Text('Screen Stream'),
            )
          : null,
      body: _isStreamActive
          ? Stack(
              children: [
                // Видео на весь экран
                _remoteVideo(),
                // Кнопка остановки стрима в верхнем левом углу
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FloatingActionButton(
                        onPressed: _isLoading ? null : _stopStream,
                        backgroundColor: Colors.red.withOpacity(0.7),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.stop, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.play_circle_outline,
                          size: 80,
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Ready to start streaming',
                          style: TextStyle(fontSize: 18),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _startStream,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start Stream'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  // Display remote user's video
  Widget _remoteVideo() {
    if (_remoteUid != null && _channelId != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine!,
                  canvas: VideoCanvas(uid: _remoteUid),
                  connection: RtcConnection(channelId: _channelId),
                ),
              ),
            ),
          );
        },
      );
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Waiting for stream...',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }
}