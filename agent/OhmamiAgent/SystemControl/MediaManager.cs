using Windows.Media.Control;
using Windows.Storage.Streams;

namespace OhmamiAgent.SystemControl
{
    public class MediaManager
    {
        private GlobalSystemMediaTransportControlsSessionManager? _sessionManager;

        public async Task InitializeAsync()
        {
            _sessionManager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }

        private GlobalSystemMediaTransportControlsSession? CurrentSession =>
            _sessionManager?.GetCurrentSession();

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
                Title = mediaProps.Title,
                Artist = mediaProps.Artist,
                Album = mediaProps.AlbumTitle,
                PlaybackStatus = playbackInfo.PlaybackStatus.ToString(),
                ThumbnailBase64 = thumbnailBase64
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

        //public class MediaStatus
        //{
        //    public string? Title { get; set; }
        //    public string? Subtitle { get; set; }

        //    public string? Artist { get; set; }
        //    public string? Album { get; set; }
        //    public string? PlaybackStatus { get; set; }
        //    public string? ThumbnailBase64 { get; set; }
        //}
    }
}
