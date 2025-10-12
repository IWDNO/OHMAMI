using System.Diagnostics;
using System.Management;

namespace OhmamiAgent.Metrics
{
    public static class MetricsCollector
    {
        private static PerformanceCounter? cpuCounter;

        static MetricsCollector()
        {
            try
            {
                cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total");
                // Первый вызов отдаёт неизмеримое значение, вызовем один раз, чтобы потом получать корректные значения
                _ = cpuCounter.NextValue();
            }
            catch
            {
                cpuCounter = null;
            }
        }

        public static object Gather()
        {
            float cpu = 0;
            try
            {
                if (cpuCounter != null)
                    cpu = cpuCounter.NextValue();
            }
            catch
            {
                cpu = 0;
            }

            // Получим total и free memory через WMI (Win32_OperatingSystem)
            ulong totalBytes = 0;
            ulong freeBytes = 0;
            try
            {
                using var searcher = new ManagementObjectSearcher("SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem");
                foreach (ManagementObject? mo in searcher.Get())
                {
                    if (mo == null) continue;
                    // WMI возвращает значения в килобайтах
                    var totalKbObj = mo["TotalVisibleMemorySize"];
                    var freeKbObj = mo["FreePhysicalMemory"];
                    if (totalKbObj != null && freeKbObj != null)
                    {
                        if (ulong.TryParse(totalKbObj.ToString(), out var totalKb))
                            totalBytes = totalKb * 1024;
                        if (ulong.TryParse(freeKbObj.ToString(), out var freeKb))
                            freeBytes = freeKb * 1024;
                    }
                    break;
                }
            }
            catch
            {
                totalBytes = 0;
                freeBytes = 0;
            }

            var usedBytes = (totalBytes > freeBytes) ? (totalBytes - freeBytes) : 0UL;
            double memPercent = totalBytes > 0 ? (double)usedBytes / totalBytes * 100.0 : 0.0;

            return new
            {
                cpu_percent = Math.Round(cpu, 1),
                mem_total = totalBytes,
                mem_used = usedBytes,
                mem_percent = Math.Round(memPercent, 1)
            };
        }
    }
}
