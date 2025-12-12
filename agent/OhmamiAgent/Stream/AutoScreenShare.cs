using Agora.Rtc;

namespace OhmamiAgent.Stream
{
    public class AutoScreenShare : IEngine
    {
        private readonly string log_file_path = ".\\logs\\agora.log";
        private string app_id_;
        private string channel_id_;
        private bool joined_ = false;
        private bool inited_ = false;
        private RtcConnection screenshare_connection_ = new RtcConnection();

        public AutoScreenShare(string appId, string channelId)
        {
            app_id_ = appId;
            channel_id_ = channelId;
        }

        internal override int Init(string appId)
        {
            int ret = -1;

            if (null == rtc_engine_)
            {
                rtc_engine_ = RtcEngine.CreateAgoraRtcEngine();
            }

            // Prepare engine context
            RtcEngineContext rtc_engine_ctx = new RtcEngineContext();
            rtc_engine_ctx.appId = appId;
            rtc_engine_ctx.logConfig.filePath = log_file_path;

            // Initialize engine
            ret = rtc_engine_.Initialize(rtc_engine_ctx);
            Console.WriteLine("Initialize: {0}", ret);

            if (ret != 0) return ret;

            // Register event handler
            ret = rtc_engine_.InitEventHandler(this);
            Console.WriteLine("InitEventHandler: {0}", ret);

            inited_ = (ret == 0);
            return ret;
        }

        internal override int UnInit()
        {
            if (null != rtc_engine_)
            {
                rtc_engine_.Dispose();
                rtc_engine_ = null;
                inited_ = false;
            }
            return 0;
        }

        internal override int JoinChannel(string channelId)
        {
            int ret = -1;
            if (null != rtc_engine_ && !joined_)
            {
                // Enable video
                ret = rtc_engine_.EnableVideo();
                Console.WriteLine("EnableVideo: {0}", ret);

                // Join channel for primary connection
                ChannelMediaOptions options = new ChannelMediaOptions();
                options.channelProfile.SetValue(CHANNEL_PROFILE_TYPE.CHANNEL_PROFILE_LIVE_BROADCASTING);
                options.clientRoleType.SetValue(CLIENT_ROLE_TYPE.CLIENT_ROLE_BROADCASTER);

                ret = rtc_engine_.JoinChannel("", channel_id_, 0, options);
                Console.WriteLine("JoinChannel: {0}", ret);

                if (ret == 0)
                {
                    joined_ = true;
                    // После успешного подключения запускаем трансляцию экрана
                    StartScreenSharing();
                }
            }
            return ret;
        }

        internal override int LeaveChannel()
        {
            int ret = -1;
            if (null != rtc_engine_ && joined_)
            {
                // Stop screen sharing
                StopScreenSharing();

                ret = rtc_engine_.LeaveChannel();
                Console.WriteLine("LeaveChannel: {0}", ret);

                ret = rtc_engine_.DisableVideo();
                Console.WriteLine("DisableVideo: {0}", ret);

                joined_ = false;
            }
            return ret;
        }

        private void StartScreenSharing()
        {
            if (!inited_) return;

            // Get available screens
            var screens = rtc_engine_.GetScreenCaptureSources(new SIZE(300, 300), new SIZE(30, 30), true);

            if (screens == null || screens.Length == 0)
            {
                Console.WriteLine("No screens found!");
                return;
            }

            // Find first screen (not window)
            ScreenCaptureSourceInfo screenSource = null;
            foreach (var source in screens)
            {
                if (source.type == ScreenCaptureSourceType.ScreenCaptureSourceType_Screen)
                {
                    screenSource = source;
                    break;
                }
            }

            if (screenSource == null)
            {
                Console.WriteLine("No screen source found!");
                return;
            }

            Console.WriteLine("Found screen: {0} (ID: {1})", screenSource.sourceTitle, screenSource.sourceId);

            IRtcEngineEx engine_ex = (IRtcEngineEx)rtc_engine_;

            // Start screen capture
            ScreenCaptureParameters parameters = new ScreenCaptureParameters
            {
                bitrate = 0,  // 0 = default
                frameRate = 60,
                enableHighLight = true,
                windowFocus = true,
                dimensions = new VideoDimensions(1920, 1080)
            };

            int ret = engine_ex.StartScreenCaptureByDisplayId((uint)screenSource.sourceId,
                new Agora.Rtc.Rectangle(), parameters);
            Console.WriteLine("StartScreenCaptureByDisplayId: {0}", ret);

            if (ret != 0) return;

            // Setup screenshare connection
            screenshare_connection_.channelId = channel_id_;
            screenshare_connection_.localUid = (uint)new Random().Next(0, 50000);

            // Mute remote streams for screenshare connection (we don't need to receive)
            engine_ex.MuteRemoteVideoStream(screenshare_connection_.localUid, true);
            engine_ex.MuteRemoteAudioStream(screenshare_connection_.localUid, true);

            // Join channel with screenshare connection
            ChannelMediaOptions screenOptions = new ChannelMediaOptions();
            screenOptions.channelProfile.SetValue(CHANNEL_PROFILE_TYPE.CHANNEL_PROFILE_LIVE_BROADCASTING);
            screenOptions.clientRoleType.SetValue(CLIENT_ROLE_TYPE.CLIENT_ROLE_BROADCASTER);
            screenOptions.publishCameraTrack.SetValue(false);
            screenOptions.publishMicrophoneTrack.SetValue(false);
            screenOptions.autoSubscribeAudio.SetValue(false);
            screenOptions.autoSubscribeVideo.SetValue(false);
            screenOptions.publishScreenTrack.SetValue(true);  // Важно: публикуем экран

            ret = engine_ex.JoinChannelEx("", screenshare_connection_, screenOptions);
            engine_ex.EnableLoopbackRecordingEx(screenshare_connection_, true, "");
            Console.WriteLine("JoinChannelEx (screenshare): {0}", ret);
        }

        private void StopScreenSharing()
        {
            if (!inited_) return;

            IRtcEngineEx engine_ex = (IRtcEngineEx)rtc_engine_;

            // Stop screen capture
            engine_ex.StopScreenCapture();

            // Leave screenshare channel
            engine_ex.LeaveChannelEx(screenshare_connection_);
        }

        public override void OnJoinChannelSuccess(RtcConnection connection, int elapsed)
        {
            if (screenshare_connection_.localUid == connection.localUid)
            {
                Console.WriteLine("Screen sharing started successfully! UID: {0}", connection.localUid);
            }
            else
            {
                Console.WriteLine("Primary channel joined. UID: {0}", connection.localUid);
            }
        }

        public override void OnLeaveChannel(RtcConnection connection, RtcStats stats)
        {
            if (screenshare_connection_.localUid == connection.localUid)
            {
                Console.WriteLine("Screen sharing stopped. UID: {0}", connection.localUid);
            }
        }

        // Запуск приложения
        public void Run()
        {
            Console.WriteLine("Initializing Agora SDK...");
            int ret = Init(app_id_);
            if (ret != 0)
            {
                Console.WriteLine("Failed to initialize: {0}", ret);
                return;
            }

            Console.WriteLine("Joining channel: {0}", channel_id_);
            ret = JoinChannel(channel_id_);
            if (ret != 0)
            {
                Console.WriteLine("Failed to join channel: {0}", ret);
                UnInit();
                return;
            }

            Console.WriteLine("Screen sharing is running. Press any key to stop...");
        }

        public void Stop()
        {
            Console.WriteLine("Stopping...");
            LeaveChannel();
            UnInit();
        }
    }
}
