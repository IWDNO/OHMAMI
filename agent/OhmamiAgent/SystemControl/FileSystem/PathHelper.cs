using System;
using System.IO;

namespace OhmamiAgent.SystemControl.FileSystem
{
    public static class PathHelper
    {
        /// <summary>
        /// Базовая нормализация пути без валидации на пустоту.
        /// Убирает завершающий разделитель директории, кроме корня диска (C:\)
        /// </summary>
        public static string NormalizeSafe(string path)
        {
            var full = Path.GetFullPath(path);
            // Убираем завершающий слеш, кроме корня диска (C:\)
            if (full.Length > 3 && full.EndsWith(Path.DirectorySeparatorChar.ToString()))
                full = full.TrimEnd(Path.DirectorySeparatorChar);
            return full;
        }

        /// <summary>
        /// Нормализация с валидацией - выбрасывает исключение если путь пустой.
        /// Относительные пути разрешаются от текущего процесса.
        /// </summary>
        public static string NormalizeRequired(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Path is required.", nameof(path));

            // Относительные пути разрешаем от текущего процесса
            var resolved = Path.IsPathFullyQualified(path)
                ? path
                : Path.GetFullPath(path);

            return NormalizeSafe(resolved);
        }

        /// <summary>
        /// Проверяет, находится ли путь candidate под префиксом prefix (или равен ему).
        /// Сравнение выполняется по границам каталогов.
        /// </summary>
        public static bool IsSameOrUnder(string candidate, string prefix)
        {
            if (candidate.Equals(prefix, StringComparison.OrdinalIgnoreCase))
                return true;

            var withSep = prefix.EndsWith(Path.DirectorySeparatorChar.ToString())
                ? prefix
                : prefix + Path.DirectorySeparatorChar;

            return candidate.StartsWith(withSep, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Проверяет, оканчивается ли путь на разделитель директории (\ или /)
        /// </summary>
        public static bool EndsWithDirectorySeparator(string path)
        {
            return path.EndsWith(Path.DirectorySeparatorChar)
                || path.EndsWith(Path.AltDirectorySeparatorChar);
        }

        /// <summary>
        /// Безопасная проверка готовности диска без выбрасывания исключений.
        /// </summary>
        public static bool IsDriveReady(DriveInfo drive)
        {
            try { return drive.IsReady; }
            catch { return false; }
        }
    }
}

