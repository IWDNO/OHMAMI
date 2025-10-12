using LibreHardwareMonitor.Hardware;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

namespace OhmamiAgent.Metrics
{
    public static class MetricsCollector
    {
        private static readonly Computer _computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMemoryEnabled = true,
            IsMotherboardEnabled = true,
            IsControllerEnabled = true,
            IsNetworkEnabled = true,
            IsStorageEnabled = true
        };

        private static readonly Dictionary<string, long> _lastNetworkBytes = new();
        private static readonly Stopwatch _networkTimer = Stopwatch.StartNew();

        static MetricsCollector()
        {
            _computer.Open();
        }

        public static object Gather()
        {
            UpdateHardware();

            var cpuInfo = GetCpuInfo();
            var gpuInfo = GetGpuInfo();
            var memoryInfo = GetMemoryInfo();
            var networkInfo = GetNetworkInfo();
            var systemInfo = GetSystemInfo();
            var batteryInfo = GetBatteryInfo();

            return new
            {
                timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
                cpu = cpuInfo,
                gpu = gpuInfo,
                memory = memoryInfo,
                network = networkInfo,
                system = systemInfo,
                battery = batteryInfo
            };
        }

        private static void UpdateHardware()
        {
            foreach (var hardware in _computer.Hardware)
            {
                hardware.Update();
            }
        }

        private static object GetCpuInfo()
        {
            string name = "Unknown CPU";
            double? usage = null;
            int? coresLogical = null;
            int? coresPhysical = null;
            int? baseClockMhz = null;
            int? currentClockMhz = null;
            double? temperature = null;

            foreach (var hardware in _computer.Hardware)
            {
                if (hardware.HardwareType == HardwareType.Cpu)
                {
                    name = hardware.Name;

                    // Логические ядра — из Environment
                    coresLogical = Environment.ProcessorCount;

                    // Физические ядра — через WMI или оценка
                    coresPhysical = GetPhysicalCpuCores();

                    // Базовая частота — из WMI
                    baseClockMhz = GetCpuBaseClockMhz();

                    foreach (var sensor in hardware.Sensors)
                    {
                        switch (sensor.SensorType)
                        {
                            case SensorType.Load when sensor.Name?.Contains("CPU Total") == true:
                                usage = sensor.Value;
                                break;
                            case SensorType.Clock:
                                // Берём максимальную текущую частоту среди ядер
                                if (currentClockMhz == null || (sensor.Value.HasValue && sensor.Value > currentClockMhz))
                                    currentClockMhz = (int?)sensor.Value;
                                break;
                            case SensorType.Temperature when sensor.Name?.Contains("CPU Package") == true ||
                                                            sensor.Name?.Contains("Core") == true:
                                if (temperature == null || (sensor.Value.HasValue && sensor.Value > temperature))
                                    temperature = sensor.Value;
                                break;
                        }
                    }
                }
            }

            return new
            {
                usage_percent = Math.Round(usage ?? 0, 1),
                name,
                cores_logical = coresLogical ?? Environment.ProcessorCount,
                cores_physical = coresPhysical ?? (Environment.ProcessorCount / 2), // fallback
                base_clock_mhz = baseClockMhz ?? 0,
                current_clock_mhz = currentClockMhz ?? baseClockMhz ?? 0,
                temperature_c = temperature.HasValue ? Math.Round(temperature.Value, 1) : (double?)null
            };
        }

        private static object GetGpuInfo()
        {
            string name = "Unknown GPU";
            double? usage = null;
            int? memoryTotal = null;
            int? memoryUsed = null;
            int? memoryFree = null;
            double? temperature = null;
            string driverVersion = GetGpuDriverVersion();

            foreach (var hardware in _computer.Hardware)
            {
                if (hardware.HardwareType == HardwareType.GpuNvidia ||
                    hardware.HardwareType == HardwareType.GpuAmd)
                {
                    name = hardware.Name;

                    foreach (var sensor in hardware.Sensors)
                    {
                        switch (sensor.SensorType)
                        {
                            case SensorType.Load when sensor.Name?.Contains("GPU Core") == true:
                                usage = sensor.Value;
                                break;
                            case SensorType.Temperature:
                                temperature = sensor.Value;
                                break;
                            case SensorType.SmallData when sensor.Name?.Contains("Memory Used") == true:
                                memoryUsed = (int?)(sensor.Value * 1); // в MB
                                break;
                            case SensorType.SmallData when sensor.Name?.Contains("Memory Total") == true:
                                memoryTotal = (int?)(sensor.Value * 1);
                                break;
                        }
                    }

                    // Если есть total и used — вычисляем free
                    if (memoryTotal.HasValue && memoryUsed.HasValue)
                    {
                        memoryFree = memoryTotal.Value - memoryUsed.Value;
                    }
                }
            }

            // Если OpenHardwareMonitor не дал память — попробуем WMI (ограниченно)
            if (!memoryTotal.HasValue)
            {
                var wmiMem = GetGpuMemoryFromWmi();
                memoryTotal = wmiMem.total;
                memoryUsed = wmiMem.used;
                memoryFree = wmiMem.free;
            }

            return new
            {
                name,
                usage_percent = usage.HasValue ? Math.Round(usage.Value, 1) : (double?)null,
                memory_total_mb = memoryTotal,
                memory_used_mb = memoryUsed,
                memory_free_mb = memoryFree,
                temperature_c = temperature.HasValue ? Math.Round(temperature.Value, 1) : (double?)null,
                driver_version = driverVersion
            };
        }

        private static object GetMemoryInfo()
        {
            long total = 0, available = 0;

            foreach (var hardware in _computer.Hardware)
            {
                if (hardware.HardwareType == HardwareType.Memory)
                {
                    foreach (var sensor in hardware.Sensors)
                    {
                        if (sensor.SensorType == SensorType.Data && sensor.Name == "Memory Used")
                        {
                            // OpenHardwareMonitor даёт память в GB
                            available = 0; // не напрямую
                        }
                    }
                }
            }

            // Лучше использовать PerformanceCounter для точности
            var totalMb = GetTotalPhysicalMemoryMb();
            var availableMb = (long)new PerformanceCounter("Memory", "Available MBytes").NextValue();
            var usedMb = totalMb - availableMb;
            var usagePercent = (double)usedMb / totalMb * 100;

            return new
            {
                total_mb = totalMb,
                used_mb = (int)usedMb,
                free_mb = (int)availableMb,
                usage_percent = Math.Round(usagePercent, 1)
            };
        }

        private static object GetNetworkInfo()
        {
            var interfaces = NetworkInterface.GetAllNetworkInterfaces()
                .Where(nic => nic.OperationalStatus == OperationalStatus.Up &&
                              nic.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                              !nic.Name.StartsWith("VMware") &&
                              !nic.Name.StartsWith("vEthernet"));

            long totalSent = 0, totalReceived = 0;

            foreach (var nic in interfaces)
            {
                var stats = nic.GetIPv4Statistics();
                totalSent += stats.BytesSent;
                totalReceived += stats.BytesReceived;
            }

            // Рассчитываем скорость за последнюю секунду
            double elapsedSeconds = _networkTimer.Elapsed.TotalSeconds;
            if (elapsedSeconds < 1) elapsedSeconds = 1;

            long sentPerSec = 0, receivedPerSec = 0;
            if (_lastNetworkBytes.TryGetValue("sent", out var lastSent))
            {
                sentPerSec = (long)((totalSent - lastSent) / elapsedSeconds);
                receivedPerSec = (long)((totalReceived - _lastNetworkBytes["recv"]) / elapsedSeconds);
            }

            _lastNetworkBytes["sent"] = totalSent;
            _lastNetworkBytes["recv"] = totalReceived;
            _networkTimer.Restart();

            return new
            {
                bytes_sent_per_sec = Math.Max(0, sentPerSec),
                bytes_received_per_sec = Math.Max(0, receivedPerSec)
            };
        }

        private static object GetSystemInfo()
        {
            var systemProcess = Process.GetProcessesByName("System").FirstOrDefault();
            double uptimeHours = systemProcess != null
                ? (DateTime.Now - systemProcess.StartTime).TotalHours
                : 0;

            return new
            {
                uptime_hours = Math.Round(uptimeHours, 1),
                os = RuntimeInformation.OSDescription,
                machine_name = Environment.MachineName
            };
        }

        // --- Вспомогательные методы (WMI) ---

        private static int GetPhysicalCpuCores()
        {
            using var searcher = new System.Management.ManagementObjectSearcher("SELECT NumberOfCores FROM Win32_Processor");
            int cores = 0;
            foreach (var obj in searcher.Get())
                cores += Convert.ToInt32(obj["NumberOfCores"]);
            return cores;
        }

        private static int GetCpuBaseClockMhz()
        {
            using var searcher = new System.Management.ManagementObjectSearcher("SELECT MaxClockSpeed FROM Win32_Processor");
            foreach (var obj in searcher.Get())
                return Convert.ToInt32(obj["MaxClockSpeed"]);
            return 0;
        }

        private static string GetGpuDriverVersion()
        {
            using var searcher = new System.Management.ManagementObjectSearcher("SELECT DriverVersion FROM Win32_VideoController");
            foreach (var obj in searcher.Get())
                return obj["DriverVersion"]?.ToString();
            return "Unknown";
        }

        private static (int? total, int? used, int? free) GetGpuMemoryFromWmi()
        {
            try
            {
                using var searcher = new System.Management.ManagementObjectSearcher("SELECT AdapterRAM FROM Win32_VideoController");
                foreach (var obj in searcher.Get())
                {
                    var ramBytes = Convert.ToUInt64(obj["AdapterRAM"]);
                    var totalMb = (int)(ramBytes / (1024 * 1024));
                    // WMI не даёт used/free — только total
                    return (totalMb, null, null);
                }
            }
            catch { }
            return (null, null, null);
        }

        private static int GetTotalPhysicalMemoryMb()
        {
            using var searcher = new System.Management.ManagementObjectSearcher("SELECT TotalPhysicalMemory FROM Win32_ComputerSystem");
            foreach (var obj in searcher.Get())
            {
                var bytes = Convert.ToInt64(obj["TotalPhysicalMemory"]);
                return (int)(bytes / (1024 * 1024));
            }
            return 0;
        }

        private static object GetBatteryInfo()
        {
            try
            {
                // Используем полное имя, чтобы избежать конфликта с LibreHardwareMonitor.Hardware.SystemInformation
                var power = System.Windows.Forms.SystemInformation.PowerStatus;
                bool isBatteryPresent = power.BatteryChargeStatus != System.Windows.Forms.BatteryChargeStatus.NoSystemBattery;

                if (!isBatteryPresent)
                {
                    return new
                    {
                        is_present = false,
                        charge_percent = (double?)null,
                        status = "NoBattery",
                        time_remaining_minutes = (int?)null
                    };
                }

                double chargePercent = power.BatteryLifePercent * 100;
                string status = power.PowerLineStatus switch
                {
                    System.Windows.Forms.PowerLineStatus.Offline => "Discharging",
                    System.Windows.Forms.PowerLineStatus.Online => "Charging",
                    System.Windows.Forms.PowerLineStatus.Unknown => "Unknown",
                    _ => "Unknown"
                };

                int? timeRemainingMinutes = power.BatteryLifeRemaining > 0
                    ? (int?)Math.Max(0, power.BatteryLifeRemaining / 60)
                    : null;

                return new
                {
                    is_present = true,
                    charge_percent = Math.Round(chargePercent, 1),
                    status,
                    time_remaining_minutes = timeRemainingMinutes
                };
            }
            catch
            {
                return new
                {
                    is_present = false,
                    charge_percent = (double?)null,
                    status = "Unavailable",
                    time_remaining_minutes = (int?)null
                };
            }
        }

    }
}