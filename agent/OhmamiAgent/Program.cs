using OhmamiAgent;
using OhmamiAgent.Mdns;
using OhmamiAgent.SystemControl;

var builder = WebApplication.CreateBuilder(args);


builder.Services.Configure<AppConfig>(builder.Configuration);
builder.Services.AddControllers();


builder.Services.AddSingleton<AudioManager>();
builder.Services.AddSingleton<MediaManager>();
builder.Services.AddSingleton<OhmamiAgent.Ws.WebSocketManager>();
builder.Services.AddSingleton<MdnsPublisher>();
//builder.Services.AddHostedService<MetricsHostedService>();

var app = builder.Build();
app.UseWebSockets();
app.MapControllers();


var mediaManager = app.Services.GetRequiredService<MediaManager>();
await mediaManager.InitializeAsync();

var mdns = app.Services.GetRequiredService<MdnsPublisher>();
await mdns.RegisterAsync(app.Configuration);

var lifetime = app.Lifetime;
lifetime.ApplicationStopping.Register(() =>
{
    mdns.Dispose();
});

app.Run($"http://{builder.Configuration.GetValue<string>("Host")}:{builder.Configuration.GetValue<int>("Port")}");
