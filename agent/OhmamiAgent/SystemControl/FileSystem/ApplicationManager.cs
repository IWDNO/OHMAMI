using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace OhmamiAgent.SystemControl.FileSystem
{
    public class ApplicationManager
    {
        private readonly string[] _roots;

        public ApplicationManager()
        {
            var commonStart = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu);
            var userStart = Environment.GetFolderPath(Environment.SpecialFolder.StartMenu);
            // Приводим к папке Programs
            _roots = new[]
            {
                Path.Combine(commonStart, "Programs"),
                Path.Combine(userStart, "Programs")
            }.Where(Directory.Exists).ToArray();
        }

        public IEnumerable<AppInfo> ListApps()
        {
            var items = new List<AppInfo>();
            foreach (var root in _roots)
            {
                try
                {
                    var links = Directory.EnumerateFiles(root, "*.lnk", SearchOption.AllDirectories);
                    foreach (var lnk in links)
                    {
                        var name = Path.GetFileNameWithoutExtension(lnk);
                        items.Add(new AppInfo { Name = name, Path = lnk });
                    }
                }
                catch { /* ignore */ }
            }
            // Убираем дубликаты по пути
            return items
                .GroupBy(x => x.Path, StringComparer.OrdinalIgnoreCase)
                .Select(g => g.First())
                .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        public IEnumerable<AppInfo> Search(string query)
        {
            if (string.IsNullOrWhiteSpace(query))
                return ListApps();

            query = query.Trim();
            return ListApps()
                .Where(a => a.Name.Contains(query, StringComparison.OrdinalIgnoreCase));
        }

        public void Launch(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Path is required.", nameof(path));

            if (!File.Exists(path))
                throw new FileNotFoundException("Application shortcut not found.", path);

            if (!IsUnderAllowedRoots(path))
                throw new UnauthorizedAccessException("Launching this path is not allowed.");

            var psi = new ProcessStartInfo
            {
                FileName = path,
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(path) ?? Environment.CurrentDirectory
            };
            Process.Start(psi);
        }

        private bool IsUnderAllowedRoots(string path)
        {
            var full = Path.GetFullPath(path);
            foreach (var root in _roots)
            {
                var r = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (full.StartsWith(r, StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            return false;
        }
    }

    public class AppInfo
    {
        public string Name { get; set; } = "";
        public string Path { get; set; } = "";
    }
}