using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Options;

namespace OhmamiAgent.SystemControl
{
    public class FileSystemManager
    {
        private readonly string[] _blacklist;
        private readonly bool _blacklistForRead;

        public FileSystemManager(IOptions<OhmamiAgent.AppConfig> cfg)
        {
            _blacklist = (cfg.Value.BlacklistPaths ?? Array.Empty<string>())
                .Select(NormalizePathSafe)
                .Where(p => !string.IsNullOrEmpty(p))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            _blacklistForRead = cfg.Value.BlacklistAppliesToRead;
        }

        public IEnumerable<DriveInfoEntry> ListDrives()
        {
            foreach (var d in DriveInfo.GetDrives())
            {
                yield return new DriveInfoEntry
                {
                    Name = d.Name,                    // "C:\\"
                    DriveType = d.DriveType.ToString(),
                    Ready = SafeReady(d),
                    TotalSize = SafeReady(d) ? d.TotalSize : (long?)null,
                    AvailableFreeSpace = SafeReady(d) ? d.AvailableFreeSpace : (long?)null
                };
            }
        }

        public IEnumerable<Entry> List(string? path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                // корень — отдать тома
                return ListDrives()
                    .Select(d => new Entry
                    {
                        Name = d.Name.TrimEnd('\\'),
                        Path = d.Name,
                        IsDirectory = true,
                        IsDrive = true,
                        Size = null,
                        ModifiedUtc = DateTime.MinValue.ToString()
                    })
                    .ToArray();
            }

            var full = NormalizePathRequired(path);

            if (_blacklistForRead && IsBlacklisted(full))
                throw new UnauthorizedAccessException("Reading from this path is not allowed.");

            if (File.Exists(full))
            {
                var fi = new FileInfo(full);
                return new[] {
                    new Entry {
                        Name = fi.Name,
                        Path = fi.FullName,
                        IsDirectory = false,
                        Size = fi.Length,
                        ModifiedUtc = fi.LastWriteTimeUtc.ToString("dd.MM.yyyy HH:mm"),
                    }
                };
            }

            if (!Directory.Exists(full))
                throw new DirectoryNotFoundException();

            var dirs = Directory.EnumerateDirectories(full)
                .Select(d => new Entry
                {
                    Name = Path.GetFileName(d),
                    Path = d,
                    IsDirectory = true,
                    Size = null,
                    ModifiedUtc = Directory.GetLastWriteTimeUtc(d).ToString("dd.MM.yyyy HH:mm")
                });
            var files = Directory.EnumerateFiles(full)
                .Select(f => new Entry
                {
                    Name = Path.GetFileName(f),
                    Path = f,
                    IsDirectory = false,
                    Size = new FileInfo(f).Length,
                    ModifiedUtc = File.GetLastWriteTimeUtc(f).ToString("dd.MM.yyyy HH:mm")
                });
            return dirs.Concat(files)
                .OrderBy(e => e.IsDirectory ? 0 : 1)
                .ThenBy(e => e.Name, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        public void CreateDirectory(string path)
        {
            var full = NormalizePathRequired(path);
            DenyIfBlacklisted(full);
            Directory.CreateDirectory(full);
        }

        public void DeleteFile(string path)
        {
            var full = NormalizePathRequired(path);
            DenyIfBlacklisted(full);
            if (!File.Exists(full)) throw new FileNotFoundException();
            File.Delete(full);
        }

        public void DeleteDirectory(string path, bool recursive)
        {
            var full = NormalizePathRequired(path);
            DenyIfBlacklisted(full);
            if (!Directory.Exists(full)) throw new DirectoryNotFoundException();
            Directory.Delete(full, recursive);
        }

        public string NormalizeForRead(string path)
        {
	        if (string.IsNullOrWhiteSpace(path))
		        throw new ArgumentException("Path is required.", nameof(path));

	        var full = Path.IsPathFullyQualified(path) ? path : Path.GetFullPath(path);
	        full = Path.GetFullPath(full);
	        if (full.Length > 3 && full.EndsWith(Path.DirectorySeparatorChar.ToString()))
		        full = full.TrimEnd(Path.DirectorySeparatorChar);

	        if (_blacklistForRead && IsBlacklisted(full))
		        throw new UnauthorizedAccessException("Reading from this path is not allowed.");

	        return full;
        }

        public string PrepareUploadPath(string dest, string? fileNameIfDir)
        {
            var destFull = NormalizePathRequired(dest);
            string finalPath;
            if (Directory.Exists(destFull) || EndsWithDirectorySeparator(dest))
            {
                if (string.IsNullOrEmpty(fileNameIfDir))
                    throw new ArgumentException("Destination is a directory; file name is required.");
                finalPath = Path.Combine(destFull, fileNameIfDir);
            }
            else
            {
                finalPath = destFull; // указан полный путь к файлу
                var dir = Path.GetDirectoryName(finalPath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    Directory.CreateDirectory(dir);
            }
            DenyIfBlacklisted(finalPath);
            // финальная проверка, что путь корректен
            return NormalizePathRequired(finalPath);
        }

        private void DenyIfBlacklisted(string fullPath)
        {
            if (IsBlacklisted(fullPath))
                throw new UnauthorizedAccessException("This path is blacklisted for modifications.");
        }

        private bool IsBlacklisted(string fullPath)
        {
            var norm = NormalizePathSafe(fullPath);
            return _blacklist.Any(b => IsSameOrUnder(norm, b));
        }

        private static string NormalizePathRequired(string p)
        {
            if (string.IsNullOrWhiteSpace(p))
                throw new ArgumentException("Path is required.", nameof(p));
            // Относительные пути разрешаем от текущего процесса (можно изменить на текущий диск)
            return NormalizePathSafe(Path.IsPathFullyQualified(p) ? p : Path.GetFullPath(p));
        }

        private static string NormalizePathSafe(string p)
        {
            var full = Path.GetFullPath(p);
            // Приведем к стандартной форме без завершающих слешей (кроме корня диска)
            if (full.Length > 3 && full.EndsWith(Path.DirectorySeparatorChar.ToString()))
                full = full.TrimEnd(Path.DirectorySeparatorChar);
            return full;
        }

        private static bool IsSameOrUnder(string candidate, string prefix)
        {
            // Сравнение префикса по границам каталогов
            if (candidate.Equals(prefix, StringComparison.OrdinalIgnoreCase))
                return true;

            var withSep = prefix.EndsWith(Path.DirectorySeparatorChar.ToString())
                ? prefix
                : prefix + Path.DirectorySeparatorChar;

            return candidate.StartsWith(withSep, StringComparison.OrdinalIgnoreCase);
        }

        private static bool EndsWithDirectorySeparator(string p)
        {
            return p.EndsWith(Path.DirectorySeparatorChar) || p.EndsWith(Path.AltDirectorySeparatorChar);
        }

        private static bool SafeReady(DriveInfo d)
        {
            try { return d.IsReady; } catch { return false; }
        }

        public class Entry
        {
            public string Name { get; set; } = "";
            public string Path { get; set; } = "";
            public bool IsDirectory { get; set; }
            public bool IsDrive { get; set; }
            public long? Size { get; set; }
            public string? ModifiedUtc { get; set; }
        }

        public class DriveInfoEntry
        {
            public string Name { get; set; } = "";
            public string DriveType { get; set; } = "";
            public bool Ready { get; set; }
            public long? TotalSize { get; set; }
            public long? AvailableFreeSpace { get; set; }
        }
    }
}