using System.Collections.Concurrent;

namespace OhmamiAgent.Stream
{
    public class ScreenShareService
    {
        private readonly string _appId;
        private AutoScreenShare? _activeStream;
        private int _streamsCount;
        private string _channelId;
        private readonly object _lock = new object();

        public ScreenShareService()
        {
            _appId = "5104f95fdd824c20a2610f909c1a0c6b";
            _streamsCount = 0;
            _channelId = "";
        }

        public string Start()
        {
            lock (_lock)
            {
                if (_streamsCount > 0)
                {
                    _streamsCount++;
                    return _channelId;
                }

                _streamsCount++;
                _channelId = Guid.NewGuid().ToString("N");

                _activeStream = new AutoScreenShare(_appId, _channelId);
                _activeStream.Run();

                return _channelId;
            }
        }

        public void Stop(string channelId)
        {
            lock (_lock)
            {
                // Проверяем, что channelId совпадает с текущим
                if (!string.IsNullOrEmpty(_channelId) && _channelId != channelId)
                {
                    return; // Игнорируем запрос на остановку другого канала
                }

                if (_streamsCount > 1)
                {
                    _streamsCount--;
                    return;
                }

                // Последний стоп - останавливаем stream
                if (_streamsCount == 1 && _activeStream != null)
                {
                    _streamsCount = 0;
                    try
                    {
                        _activeStream.Stop();
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Error stopping stream: {ex.Message}");
                    }
                    finally
                    {
                        _activeStream = null;
                        _channelId = "";
                    }
                }
                else if (_streamsCount == 0)
                {
                    // Уже остановлено, ничего не делаем
                    return;
                }
            }
        }
    }
}
