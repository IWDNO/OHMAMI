using Makaretu.Dns;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OhmamiAgent;
using OhmamiAgent.Api;
using OhmamiAgent.Mdns;
using OhmamiAgent.Metrics;
using OhmamiAgent.SystemControl;
using OhmamiAgent.Ws;

var builder = WebApplication.CreateBuilder(args);


builder.Services.Configure<AppConfig>(builder.Configuration);

builder.Services.AddControllers();
builder.Services.AddSingleton<AudioManager>();
builder.Services.AddSingleton<OhmamiAgent.Ws.WebSocketManager>();
builder.Services.AddSingleton<MdnsPublisher>();
//builder.Services.AddHostedService<MetricsHostedService>();

var app = builder.Build();
app.UseWebSockets();
app.MapControllers();

var mdns = app.Services.GetRequiredService<MdnsPublisher>();
await mdns.RegisterAsync(app.Configuration);

var lifetime = app.Lifetime;
lifetime.ApplicationStopping.Register(() =>
{
    mdns.Dispose();
});

app.Run($"http://{builder.Configuration.GetValue<string>("Host")}:{builder.Configuration.GetValue<int>("Port")}");
