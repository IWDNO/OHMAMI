using Microsoft.Extensions.Hosting;
using System.Drawing;
using System.Windows.Forms;

namespace OhmamiAgent.Tray;

public sealed class TrayIconHostedService : IHostedService, IDisposable
{
    private readonly IServiceProvider _services;
    private readonly ILogger<TrayIconHostedService> _logger;
    private Thread? _uiThread;
    private ApplicationContext? _context;

    public TrayIconHostedService(IServiceProvider services, ILogger<TrayIconHostedService> logger)
    {
        _services = services;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        // Tray icon only makes sense in interactive session.
        _uiThread = new Thread(RunMessageLoop)
        {
            IsBackground = true,
            Name = "OhmamiAgentTray"
        };
        _uiThread.SetApartmentState(ApartmentState.STA);
        _uiThread.Start();
        return Task.CompletedTask;
    }

    private void RunMessageLoop()
    {
        try
        {
            using var icon = new NotifyIcon
            {
                Text = "OhmamiAgent",
                Icon = SystemIcons.Application,
                Visible = true
            };

            var menu = new ContextMenuStrip();
            var showCode = new ToolStripMenuItem("Show pairing code (copy)");
            var exit = new ToolStripMenuItem("Exit");
            menu.Items.Add(showCode);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exit);
            icon.ContextMenuStrip = menu;

            showCode.Click += async (_, __) =>
            {
                try
                {
                    using var scope = _services.CreateScope();
                    var pairing = scope.ServiceProvider.GetRequiredService<Remote.RemotePairingService>();
                    var result = await pairing.CreatePairingCodeAsync(CancellationToken.None);

                    try
                    {
                        Clipboard.SetText(result.Code);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogDebug(ex, "Failed to write to clipboard");
                    }

                    icon.BalloonTipTitle = "Pairing code copied";
                    icon.BalloonTipText = $"{result.Code}\nExpires: {result.ExpiresAt:HH:mm:ss}";
                    icon.ShowBalloonTip(4000);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to create pairing code");
                    icon.BalloonTipTitle = "Failed to create pairing code";
                    icon.BalloonTipText = ex.Message;
                    icon.ShowBalloonTip(5000);
                }
            };

            exit.Click += (_, __) =>
            {
                try
                {
                    icon.Visible = false;
                    Application.Exit();
                }
                catch { }
            };

            _context = new ApplicationContext();
            Application.Run(_context);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Tray UI loop failed");
        }
        finally
        {
            _context = null;
        }
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        try
        {
            if (_context != null)
            {
                try { _context.ExitThread(); } catch { }
            }
            try { Application.ExitThread(); } catch { }
        }
        catch { }

        return Task.CompletedTask;
    }

    public void Dispose()
    {
        try { _context?.Dispose(); } catch { }
    }
}

