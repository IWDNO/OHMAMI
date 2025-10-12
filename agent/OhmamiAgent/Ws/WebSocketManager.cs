using OhmamiAgent.SystemControl;
using System;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace OhmamiAgent.Ws
{
    public class WebSocketManager
    {
        private readonly List<WebSocket> active = new();
        private readonly ILogger<WebSocketManager> logger;
        private readonly IConfiguration configuration;
        private readonly int metricsInterval;
        private readonly int mediaInterval;
        private readonly MediaManager mediaManager;

        public WebSocketManager(ILogger<WebSocketManager> logger, IConfiguration configuration, MediaManager media)
        {
            this.logger = logger;
            this.configuration = configuration;
            this.metricsInterval = configuration.GetValue<int>("MetricsIntervalSeconds", 2);
            this.mediaInterval = configuration.GetValue<int>("MediaIntervalSeconds", 3);
            this.mediaManager = media;
        }

        public async Task HandleConnectionAsync(WebSocket ws, CancellationToken ct)
        {
            lock (active) { active.Add(ws); }
            logger.LogInformation("WebSocket connected. Total clients: {n}", active.Count);

            var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            var senderTask = Task.Run(() => MetricsSenderLoop(ws, linkedCts.Token), linkedCts.Token);
            var mediaTask = Task.Run(() => MediaSenderLoop(ws, linkedCts.Token), linkedCts.Token);

            var buffer = new byte[4096];
            try
            {
                while (!ct.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    var res = await ws.ReceiveAsync(buffer, ct);
                    if (res.MessageType == WebSocketMessageType.Close)
                    {
                        break;
                    }
                    var text = Encoding.UTF8.GetString(buffer, 0, res.Count);
                    logger.LogDebug("Received from client: {text}", text);

                    var reply = new { type = "cmd_result", input = text, result = $"echo: {text}" };
                    await SendAsync(ws, reply, ct);
                }
            }
            catch (OperationCanceledException) { }
            catch (WebSocketException wex)
            {
                logger.LogWarning(wex, "WebSocket error");
            }
            finally
            {
                try
                {
                    linkedCts.Cancel();
                    await senderTask;
                }
                catch { /* ignore */ }

                lock (active) { active.Remove(ws); }
                if (ws.State == WebSocketState.Open || ws.State == WebSocketState.CloseReceived)
                {
                    try { await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "closing", CancellationToken.None); } catch { }
                }

                logger.LogInformation("WebSocket disconnected. Remaining clients: {n}", active.Count);
            }
        }

        private async Task MetricsSenderLoop(WebSocket ws, CancellationToken ct)
        {
            try
            {
                while (!ct.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    var payload = new { type = "metrics", payload = Metrics.MetricsCollector.Gather() };
                    await SendAsync(ws, payload, ct);
                    await Task.Delay(TimeSpan.FromSeconds(metricsInterval), ct);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "Metrics sender stopped");
            }
        }

        private async Task MediaSenderLoop(WebSocket ws, CancellationToken ct)
        {
            try
            {
                while (!ct.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    var status = await mediaManager.GetStatusAsync();
                    if (status != null)
                    {
                        var payload = new { type = "media_update", payload = status };
                        await SendAsync(ws, payload, ct);
                    }
                    await Task.Delay(TimeSpan.FromSeconds(mediaInterval), ct);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "Media sender stopped");
            }
        }

        public async Task SendAsync(WebSocket ws, object data, CancellationToken ct)
        {
            if (ws.State != WebSocketState.Open) return;
            var json = JsonSerializer.Serialize(data);
            var bytes = Encoding.UTF8.GetBytes(json);
            await ws.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, cancellationToken: ct);
        }

        public async Task BroadcastAsync(object data)
        {
            var json = JsonSerializer.Serialize(data);
            var bytes = Encoding.UTF8.GetBytes(json);
            List<WebSocket> clients;
            lock (active) { clients = active.ToList(); }

            foreach (var ws in clients)
            {
                if (ws.State != WebSocketState.Open) { lock (active) { active.Remove(ws); } continue; }
                try
                {
                    await ws.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
                }
                catch
                {
                    lock (active) { active.Remove(ws); }
                }
            }
        }
    }
}
