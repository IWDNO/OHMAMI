using System;
using System.IO;

namespace OhmamiAgent.Remote
{
    public sealed class RemoteAgentIdStore
    {
        private readonly object _lock = new();
        private readonly string _filePath;

        public RemoteAgentIdStore()
        {
            var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var dir = Path.Combine(baseDir, "OhmamiAgent");
            Directory.CreateDirectory(dir);
            _filePath = Path.Combine(dir, "agent-id.txt");
        }

        public string GetOrCreate()
        {
            lock (_lock)
            {
                var existing = TryRead();
                if (!string.IsNullOrWhiteSpace(existing))
                {
                    return existing;
                }

                var created = Guid.NewGuid().ToString("N");
                File.WriteAllText(_filePath, created);
                return created;
            }
        }

        private string? TryRead()
        {
            try
            {
                if (!File.Exists(_filePath))
                {
                    return null;
                }

                var value = File.ReadAllText(_filePath).Trim();
                return string.IsNullOrWhiteSpace(value) ? null : value;
            }
            catch
            {
                return null;
            }
        }
    }
}
