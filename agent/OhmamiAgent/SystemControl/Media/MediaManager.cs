using Windows.Media.Control;
using Windows.Storage.Streams;

namespace OhmamiAgent.SystemControl.Media
{
    public class MediaManager: IDisposable
    {
        private GlobalSystemMediaTransportControlsSessionManager? _sessionManager;
        private GlobalSystemMediaTransportControlsSession? _attachedSession;

        public event Func<object, Task>? StatusChanged;

        private GlobalSystemMediaTransportControlsSession? CurrentSession =>
            _sessionManager?.GetCurrentSession();

        public async Task InitializeAsync()
        {
            _sessionManager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();

            _sessionManager.CurrentSessionChanged += async (_, __) =>
            {
                AttachTo(CurrentSession);
                await EmitStatusAsync();
            };

            AttachTo(CurrentSession);
            await EmitStatusAsync();
        }

        private void AttachTo(GlobalSystemMediaTransportControlsSession? session)
        {
            if (_attachedSession != null)
            {
                _attachedSession.MediaPropertiesChanged -= OnMediaPropsChangedAsync;
                _attachedSession.PlaybackInfoChanged -= OnPlaybackInfoChangedAsync;
                _attachedSession = null;
            }

            if (session != null)
            {
                _attachedSession = session;
                _attachedSession.MediaPropertiesChanged += OnMediaPropsChangedAsync;
                _attachedSession.PlaybackInfoChanged += OnPlaybackInfoChangedAsync;
            }
        }

        private async void OnMediaPropsChangedAsync(GlobalSystemMediaTransportControlsSession s, object e)
        {
            try { await EmitStatusAsync(); } catch(Exception ex) { Console.WriteLine(ex); }
        }

        private async void OnPlaybackInfoChangedAsync(GlobalSystemMediaTransportControlsSession s, object e)
        {
            try { await EmitStatusAsync(); } catch (Exception ex) { Console.WriteLine(ex); }
        }

        private async Task EmitStatusAsync()
        {
            var data = await GetStatusAsync();
            if (data != null && StatusChanged != null)
            {
                try { await StatusChanged.Invoke(data); } catch { }
            }
        }

        public async Task<object?> GetStatusAsync()
        {
            var session = CurrentSession;
            if (session == null) return null;

            GlobalSystemMediaTransportControlsSessionMediaProperties? mediaProps = null;
            try
            {
                mediaProps = await session.TryGetMediaPropertiesAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"GetStatusAsync: TryGetMediaPropertiesAsync failed: {ex.Message}");
            }
            if (mediaProps == null) return null;

            var playbackInfo = session.GetPlaybackInfo();
            var playbackStatus = playbackInfo?.PlaybackStatus.ToString() ?? "Unknown";

            string? thumbnailBase64 = null;
            try
            {
                if (mediaProps.Thumbnail != null)
                {
                    var streamRef = mediaProps.Thumbnail;
                    var randomAccessStream = await streamRef.OpenReadAsync();
                    using var memoryStream = new MemoryStream();
                    await randomAccessStream.AsStreamForRead().CopyToAsync(memoryStream);
                    thumbnailBase64 = Convert.ToBase64String(memoryStream.ToArray());
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Failed to read thumbnail: {ex.Message}");
            }

            return new
            {
                timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                title = mediaProps.Title,
                artist = mediaProps.Artist,
                album = mediaProps.AlbumTitle,
                playbackStatus,
                thumbnailBase64
            };
        }

        public async Task PlayAsync() =>
            await CurrentSession?.TryPlayAsync();

        public async Task PauseAsync() =>
            await CurrentSession?.TryPauseAsync();

        public async Task NextAsync() =>
            await CurrentSession?.TrySkipNextAsync();

        public async Task PreviousAsync() =>
            await CurrentSession?.TrySkipPreviousAsync();

        public void Dispose()
        {
            if (_attachedSession != null)
            {
                _attachedSession.MediaPropertiesChanged -= OnMediaPropsChangedAsync;
                _attachedSession.PlaybackInfoChanged -= OnPlaybackInfoChangedAsync;
            }
            _sessionManager = null;
            _attachedSession = null;
        }
    }
}
