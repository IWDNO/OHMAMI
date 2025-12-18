using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting.WindowsServices;
using OhmamiAgent;
using OhmamiAgent.Mdns;
using OhmamiAgent.Stream;
using OhmamiAgent.SystemControl.FileSystem;
using OhmamiAgent.SystemControl.Media;
using OhmamiAgent.SystemControl.Security;
using System.Runtime.InteropServices;

var builder = WebApplication.CreateBuilder(args);

if (WindowsServiceHelpers.IsWindowsService())
{
    builder.Host.UseWindowsService(options =>
    {
        options.ServiceName = "OhmamiAgent";
    });

    // ����� ������� �������� ����� � exe
    builder.Host.UseContentRoot(AppContext.BaseDirectory);
}

builder.Services.Configure<AppConfig>(builder.Configuration);
builder.Services.AddControllers();


builder.Services.AddSingleton<FileSystemManager>();
builder.Services.AddSingleton<ApplicationManager>();
builder.Services.AddSingleton<AudioManager>();
builder.Services.AddSingleton<MediaManager>();
builder.Services.AddSingleton<BlocklistStore>();
builder.Services.AddSingleton<HostsManager>();
builder.Services.AddSingleton<OhmamiAgent.Ws.WebSocketManager>();
builder.Services.AddSingleton<MdnsPublisher>();
builder.Services.AddSingleton<ScreenShareService>();
//builder.Services.AddHostedService<MetricsHostedService>();
builder.Services.AddHostedService<ProcessBlockerHostedService>();

var app = builder.Build();

app.UseWebSockets();
app.MapControllers();


//var mediaManager = app.Services.GetRequiredService<MediaManager>();
if (!WindowsServiceHelpers.IsWindowsService())
{
    var mediaManager = app.Services.GetRequiredService<MediaManager>();
    await mediaManager.InitializeAsync();
}

var mdns = app.Services.GetRequiredService<MdnsPublisher>();
await mdns.RegisterAsync(app.Configuration);

var lifetime = app.Lifetime;
lifetime.ApplicationStopping.Register(() =>
{
    mdns.Dispose();
    app.Services.GetRequiredService<AudioManager>().Dispose();
    //mediaManager.Dispose();
});

app.Run($"http://{builder.Configuration.GetValue<string>("Host")}:{builder.Configuration.GetValue<int>("Port")}");


