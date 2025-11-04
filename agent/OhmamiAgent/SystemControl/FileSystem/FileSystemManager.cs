using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.Options;

namespace OhmamiAgent.SystemControl.FileSystem
{
    public class FileSystemManager
    {
        private readonly string[] _blacklist;
        private readonly bool _blacklistForRead;

        public FileSystemManager(IOptions<AppConfig> cfg)
        {
            _blacklist = (cfg.Value.BlacklistPaths ?? Array.Empty<string>())
                .Select(PathHelper.NormalizeSafe)
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
                    Ready = PathHelper.IsDriveReady(d),
                    TotalSize = PathHelper.IsDriveReady(d) ? d.TotalSize : null,
                    AvailableFreeSpace = PathHelper.IsDriveReady(d) ? d.AvailableFreeSpace : null
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

            var full = PathHelper.NormalizeRequired(path);

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
            var full = PathHelper.NormalizeRequired(path);
            DenyIfBlacklisted(full);
            Directory.CreateDirectory(full);
        }

        public void DeleteFile(string path)
        {
            var full = PathHelper.NormalizeRequired(path);
            DenyIfBlacklisted(full);
            if (!File.Exists(full)) throw new FileNotFoundException();
            File.Delete(full);
        }

        public void DeleteDirectory(string path, bool recursive)
        {
            var full = PathHelper.NormalizeRequired(path);
            DenyIfBlacklisted(full);
            if (!Directory.Exists(full)) throw new DirectoryNotFoundException();
            Directory.Delete(full, recursive);
        }

        public string NormalizeForRead(string path)
        {
            var full = PathHelper.NormalizeRequired(path);

            if (_blacklistForRead && IsBlacklisted(full))
                throw new UnauthorizedAccessException("Reading from this path is not allowed.");

            return full;
        }

        public string PrepareUploadPath(string dest, string? fileNameIfDir)
        {
            var destFull = PathHelper.NormalizeRequired(dest);
            string finalPath;
            if (Directory.Exists(destFull) || PathHelper.EndsWithDirectorySeparator(dest))
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
            return PathHelper.NormalizeRequired(finalPath);
        }

        public Dictionary<string, string> GetSpecialFolders()
        {
            var folders = new Dictionary<string, string>();
            
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            if (!string.IsNullOrEmpty(desktop))
                folders["desktop"] = desktop;

            var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            if (!string.IsNullOrEmpty(documents))
                folders["documents"] = documents;

            var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
            if (!string.IsNullOrEmpty(pictures))
                folders["pictures"] = pictures;

            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!string.IsNullOrEmpty(userProfile))
            {
                var downloads = Path.Combine(userProfile, "Downloads");
                if (Directory.Exists(downloads))
                    folders["downloads"] = downloads;
            }

            var music = Environment.GetFolderPath(Environment.SpecialFolder.MyMusic);
            if (!string.IsNullOrEmpty(music) && Directory.Exists(music))
                folders["music"] = music;

            var videos = Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);
            if (!string.IsNullOrEmpty(videos) && Directory.Exists(videos))
                folders["videos"] = videos;

            var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            if (!string.IsNullOrEmpty(home))
                folders["home"] = home;

            var recent = Environment.GetFolderPath(Environment.SpecialFolder.Recent);
            if (!string.IsNullOrEmpty(recent) && Directory.Exists(recent))
                folders["recent"] = recent;

            return folders;
        }

        private void DenyIfBlacklisted(string fullPath)
        {
            if (IsBlacklisted(fullPath))
                throw new UnauthorizedAccessException("This path is blacklisted for modifications.");
        }

        private bool IsBlacklisted(string fullPath)
        {
            var norm = PathHelper.NormalizeSafe(fullPath);
            return _blacklist.Any(b => PathHelper.IsSameOrUnder(norm, b));
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