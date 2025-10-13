using Windows.Media.Control;
using Windows.Storage.Streams;

namespace OhmamiAgent.SystemControl
{
    public class MediaManager
    {
        private GlobalSystemMediaTransportControlsSessionManager? _sessionManager;
        private GlobalSystemMediaTransportControlsSession? CurrentSession =>
            _sessionManager?.GetCurrentSession();

        public event Func<object, Task>? StatusChanged;

        public async Task InitializeAsync()
        {
            _sessionManager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            
            void attach(GlobalSystemMediaTransportControlsSession? s)
            {
                if (s == null) return;
                s.MediaPropertiesChanged += async (_, __) => { System.Console.WriteLine("MediaPropertiesChanged"); await EmitStatusAsync(); };
                s.PlaybackInfoChanged += async (_, __) => { System.Console.WriteLine("PlaybackInfoChanged"); await EmitStatusAsync(); };
            }

            attach(CurrentSession);

            _sessionManager.CurrentSessionChanged += async (_, __) =>
            {
                System.Console.WriteLine("CurrentSessionChanged");
                attach(CurrentSession);
                await EmitStatusAsync();
            };

            await EmitStatusAsync();
        }

        public async Task<Object?> GetStatusAsync()
        {
            var session = CurrentSession;
            if (session == null) return null;

            var mediaProps = await session.TryGetMediaPropertiesAsync();
            var playbackInfo = session.GetPlaybackInfo();

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
                playbackStatus = playbackInfo.PlaybackStatus.ToString(),
                thumbnailBase64 = thumbnailBase64
            };
        }

        private async Task EmitStatusAsync()
        {
            var data = await GetStatusAsync();
            if (data != null && StatusChanged != null)
            {
                try { await StatusChanged.Invoke(data); } catch { }
            }
        }
        public async Task PlayAsync() =>
            await CurrentSession?.TryPlayAsync();

        public async Task PauseAsync() =>
            await CurrentSession?.TryPauseAsync();

        public async Task NextAsync() =>
            await CurrentSession?.TrySkipNextAsync();

        public async Task PreviousAsync() =>
            await CurrentSession?.TrySkipPreviousAsync();
    }
}
