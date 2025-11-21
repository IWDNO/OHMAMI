using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace OhmamiAgent.SystemControl.Security
{
    public class BlocklistStore
    {
        private readonly string _filePath;
        private readonly object _lock = new();
        private HashSet<string> _blocked = new(StringComparer.OrdinalIgnoreCase);

        public BlocklistStore()
        {
            var baseDir = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            var dir = Path.Combine(baseDir, "OhmamiAgent");
            Directory.CreateDirectory(dir);
            _filePath = Path.Combine(dir, "blocklist.json");
            Load();
        }

        public IReadOnlyCollection<string> List()
        {
            lock (_lock)
            {
                return _blocked.ToArray();
            }
        }

        public bool Add(string normalizedPath)
        {
            lock (_lock)
            {
                var added = _blocked.Add(normalizedPath);
                if (added) Save();
                return added;
            }
        }

        public bool Remove(string normalizedPath)
        {
            lock (_lock)
            {
                var removed = _blocked.Remove(normalizedPath);
                if (removed) Save();
                return removed;
            }
        }

        private void Load()
        {
            try
            {
                if (!File.Exists(_filePath))
                {
                    _blocked = new(StringComparer.OrdinalIgnoreCase);
                    return;
                }
                var json = File.ReadAllText(_filePath);
                var parsed = JsonSerializer.Deserialize<HashSet<string>>(json);
                _blocked = parsed != null
                    ? new HashSet<string>(parsed, StringComparer.OrdinalIgnoreCase)
                    : new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            }
            catch
            {
                _blocked = new(StringComparer.OrdinalIgnoreCase);
            }
        }

        private void Save()
        {
            var json = JsonSerializer.Serialize(_blocked, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_filePath, json);
        }
    }
}


