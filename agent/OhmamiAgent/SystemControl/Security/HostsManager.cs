using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace OhmamiAgent.SystemControl.Security
{
    public class HostsManager
    {
        private const string HostsFilePath = @"C:\Windows\System32\drivers\etc\hosts";
        private const string BlockStartMarker = "# BEGIN OHMAMI BLOCKED SITES";
        private const string BlockEndMarker = "# END OHMAMI BLOCKED SITES";
        private const string BlockIp = "127.0.0.1";
        
        private readonly object _lock = new();
        private readonly HashSet<string> _blockedSites = new(StringComparer.OrdinalIgnoreCase);

        public HostsManager()
        {
            LoadBlockedSites();
        }

        /// <summary>
        /// Получить список всех заблокированных сайтов
        /// </summary>
        public IReadOnlyCollection<string> GetBlockedSites()
        {
            lock (_lock)
            {
                LoadBlockedSites();
                return _blockedSites.ToArray();
            }
        }

        /// <summary>
        /// Заблокировать сайт
        /// </summary>
        public bool BlockSite(string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return false;

            var normalized = NormalizeDomain(domain);
            if (string.IsNullOrEmpty(normalized))
                return false;

            lock (_lock)
            {
                if (_blockedSites.Contains(normalized))
                    return false;

                _blockedSites.Add(normalized);
                return SaveHostsFile();
            }
        }

        /// <summary>
        /// Разблокировать сайт
        /// </summary>
        public bool UnblockSite(string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return false;

            var normalized = NormalizeDomain(domain);
            if (string.IsNullOrEmpty(normalized))
                return false;

            lock (_lock)
            {
                if (!_blockedSites.Remove(normalized))
                    return false;

                return SaveHostsFile();
            }
        }

        /// <summary>
        /// Проверить, заблокирован ли сайт
        /// </summary>
        public bool IsBlocked(string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return false;

            var normalized = NormalizeDomain(domain);
            lock (_lock)
            {
                LoadBlockedSites();
                return _blockedSites.Contains(normalized);
            }
        }

        private string NormalizeDomain(string domain)
        {
            if (string.IsNullOrWhiteSpace(domain))
                return string.Empty;

            // Удаляем протоколы (http://, https://)
            domain = Regex.Replace(domain, @"^https?://", "", RegexOptions.IgnoreCase);
            
            // Удаляем www. префикс для нормализации
            domain = domain.Trim().ToLowerInvariant();
            if (domain.StartsWith("www."))
                domain = domain.Substring(4);

            // Удаляем путь и параметры
            var uriIndex = domain.IndexOfAny(new[] { '/', '?', '#' });
            if (uriIndex >= 0)
                domain = domain.Substring(0, uriIndex);

            domain = domain.Trim();
            
            // Проверка на валидность домена
            if (string.IsNullOrEmpty(domain) || domain.Contains(" "))
                return string.Empty;

            return domain;
        }

        private void LoadBlockedSites()
        {
            _blockedSites.Clear();

            try
            {
                if (!File.Exists(HostsFilePath))
                    return;

                var lines = File.ReadAllLines(HostsFilePath);
                bool inBlockSection = false;

                foreach (var line in lines)
                {
                    var trimmed = line.Trim();
                    
                    if (trimmed == BlockStartMarker)
                    {
                        inBlockSection = true;
                        continue;
                    }

                    if (trimmed == BlockEndMarker)
                    {
                        inBlockSection = false;
                        continue;
                    }

                    if (inBlockSection && !string.IsNullOrWhiteSpace(trimmed) && !trimmed.StartsWith("#"))
                    {
                        // Парсим строку вида "127.0.0.1 domain.com"
                        var parts = trimmed.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                        if (parts.Length >= 2 && parts[0] == BlockIp)
                        {
                            var domain = NormalizeDomain(parts[1]);
                            if (!string.IsNullOrEmpty(domain))
                            {
                                _blockedSites.Add(domain);
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error loading blocked sites from hosts file: {ex.Message}");
            }
        }

        private bool SaveHostsFile()
        {
            try
            {
                if (!File.Exists(HostsFilePath))
                {
                    // Создаем файл, если его нет (маловероятно, но на всякий случай)
                    Directory.CreateDirectory(Path.GetDirectoryName(HostsFilePath)!);
                    File.Create(HostsFilePath).Close();
                }

                var allLines = File.ReadAllLines(HostsFilePath).ToList();
                
                // Находим индексы начала и конца нашей секции
                int startIndex = -1;
                int endIndex = -1;

                for (int i = 0; i < allLines.Count; i++)
                {
                    var trimmed = allLines[i].Trim();
                    if (trimmed == BlockStartMarker)
                        startIndex = i;
                    if (trimmed == BlockEndMarker)
                        endIndex = i;
                }

                // Удаляем старую секцию, если она существует
                if (startIndex >= 0 && endIndex >= 0 && endIndex >= startIndex)
                {
                    allLines.RemoveRange(startIndex, endIndex - startIndex + 1);
                }
                else if (startIndex >= 0)
                {
                    // Если есть начало, но нет конца, удаляем все до конца файла
                    allLines.RemoveRange(startIndex, allLines.Count - startIndex);
                }

                // Добавляем новую секцию, если есть заблокированные сайты
                if (_blockedSites.Count > 0)
                {
                    // Убеждаемся, что файл заканчивается пустой строкой перед нашей секцией
                    if (allLines.Count > 0 && !string.IsNullOrWhiteSpace(allLines[^1]))
                    {
                        allLines.Add("");
                    }

                    allLines.Add(BlockStartMarker);
                    foreach (var site in _blockedSites.OrderBy(s => s))
                    {
                        allLines.Add($"{BlockIp}\t{site}");
                    }
                    allLines.Add(BlockEndMarker);
                }

                // Сохраняем файл
                File.WriteAllLines(HostsFilePath, allLines, Encoding.UTF8);
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                Console.WriteLine("Access denied: Administrator rights required to modify hosts file");
                return false;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error saving hosts file: {ex.Message}");
                return false;
            }
        }
    }
}


