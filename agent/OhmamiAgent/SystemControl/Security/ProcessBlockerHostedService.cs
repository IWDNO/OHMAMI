using System;
using System.Diagnostics;
using System.IO;
using System.Management;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;

namespace OhmamiAgent.SystemControl.Security
{
    public class ProcessBlockerHostedService : IHostedService, IDisposable
    {
        private readonly BlocklistStore _store;
        private ManagementEventWatcher? _watcher;
        private bool _disposed;

        public ProcessBlockerHostedService(BlocklistStore store)
        {
            _store = store;
        }

        public Task StartAsync(CancellationToken cancellationToken)
        {
            try
            {
                string query = "SELECT ProcessID, ProcessName FROM Win32_ProcessStartTrace";
                _watcher = new ManagementEventWatcher(query);
                _watcher.EventArrived += OnProcessStarted;
                _watcher.Start();
                Console.WriteLine("ProcessBlockerHostedService is runnig");
            }
            catch (Exception ex)
            {

                Console.WriteLine($"ProcessBlockerHostedService failed: {ex}");
            }
            return Task.CompletedTask;
        }

        private void OnProcessStarted(object sender, EventArrivedEventArgs e)
        {
            try
            {
                var pidObj = e.NewEvent.Properties["ProcessID"].Value;
                if (pidObj == null) return;
                var pid = Convert.ToInt32(pidObj);

                string? exePath = null;
                try
                {
                    using var searcher = new ManagementObjectSearcher($"SELECT ExecutablePath FROM Win32_Process WHERE ProcessId = {pid}");
                    foreach (ManagementObject mo in searcher.Get())
                    {
                        exePath = mo["ExecutablePath"] as string;
                        break;
                    }
                }
                catch { }

                if (string.IsNullOrWhiteSpace(exePath)) return;

                var norm = Path.GetFullPath(exePath);
                foreach (var blocked in _store.List())
                {
                    if (string.Equals(blocked, norm, StringComparison.OrdinalIgnoreCase))
                    {
                        try
                        {
                            using var p = Process.GetProcessById(pid);
                            p.Kill(true);
                            Console.WriteLine($"Process {pid} killed by ProcessBlockerHostedService: {norm}");
                        }
                        catch { }
                        break;
                    }
                }
            }
            catch
            {
                // swallow errors to keep watcher alive
            }
        }

        public Task StopAsync(CancellationToken cancellationToken)
        {
            try { _watcher?.Stop(); } catch { }
            return Task.CompletedTask;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _watcher?.Dispose(); } catch { }
        }
    }
}