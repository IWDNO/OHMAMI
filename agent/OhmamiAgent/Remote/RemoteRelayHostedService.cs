using Microsoft.Extensions.Options;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OhmamiAgent.Remote
{
    public sealed class RemoteRelayHostedService : BackgroundService
    {
        private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        private readonly ILogger<RemoteRelayHostedService> _logger;
        private readonly RemoteRelayOptions _options;
        private readonly IHttpClientFactory _httpClientFactory;

        public RemoteRelayHostedService(
            ILogger<RemoteRelayHostedService> logger,
            IOptions<RemoteRelayOptions> options,
            IHttpClientFactory httpClientFactory)
        {
            _logger = logger;
            _options = options.Value;
            _httpClientFactory = httpClientFactory;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            if (!_options.Enabled)
            {
                _logger.LogInformation("Remote relay is disabled");
                return;
            }

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await ConnectAndRunAsync(stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Remote relay connection failed");
                }

                await Task.Delay(TimeSpan.FromSeconds(Math.Max(1, _options.ReconnectSeconds)), stoppingToken);
            }
        }

        private async Task ConnectAndRunAsync(CancellationToken ct)
        {
            var agentId = string.IsNullOrWhiteSpace(_options.AgentId)
                ? Environment.MachineName
                : _options.AgentId;

            var serverUri = new Uri(_options.ServerUrl.TrimEnd('/'));
            var wsScheme = serverUri.Scheme == "https" ? "wss" : "ws";
            var wsUri = new UriBuilder(serverUri)
            {
                Scheme = wsScheme,
                Path = "/agent/ws",
                Query = $"agentId={Uri.EscapeDataString(agentId)}&token={Uri.EscapeDataString(_options.AgentToken)}&name={Uri.EscapeDataString(Environment.MachineName)}"
            }.Uri;

            using var socket = new ClientWebSocket();
            socket.Options.KeepAliveInterval = TimeSpan.FromSeconds(20);

            _logger.LogInformation("Connecting remote relay: {uri}", wsUri);
            await socket.ConnectAsync(wsUri, ct);
            _logger.LogInformation("Remote relay connected as {agentId}", agentId);

            using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct);
            using var sendLock = new SemaphoreSlim(1, 1);
            var eventTask = Task.Run(() => ForwardLocalEventsAsync(socket, sendLock, linked.Token), linked.Token);

            try
            {
                while (!ct.IsCancellationRequested && socket.State == WebSocketState.Open)
                {
                    var json = await ReceiveTextAsync(socket, ct);
                    if (json == null) break;

                    var envelope = JsonSerializer.Deserialize<RelayEnvelope>(json, JsonOptions);
                    if (envelope?.Type == "http_request" && !string.IsNullOrWhiteSpace(envelope.Id))
                    {
                        _ = Task.Run(() => HandleProxyRequestAsync(socket, sendLock, envelope, ct), ct);
                    }
                }
            }
            finally
            {
                linked.Cancel();
                try { await eventTask; } catch { }
            }
        }

        private async Task HandleProxyRequestAsync(
            ClientWebSocket socket,
            SemaphoreSlim sendLock,
            RelayEnvelope envelope,
            CancellationToken ct)
        {
            try
            {
                var response = await ExecuteLocalRequestAsync(envelope, ct);
                await SendAsync(socket, sendLock, new RelayEnvelope(
                    Type: "http_response",
                    Id: envelope.Id,
                    Status: response.Status,
                    Body: response.Body), ct);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Remote request failed: {endpoint}", envelope.Endpoint);
                await SendAsync(socket, sendLock, new RelayEnvelope(
                    Type: "error",
                    Id: envelope.Id,
                    Status: 500,
                    Message: ex.Message), ct);
            }
        }

        private async Task<ProxyResponse> ExecuteLocalRequestAsync(RelayEnvelope envelope, CancellationToken ct)
        {
            var endpoint = string.IsNullOrWhiteSpace(envelope.Endpoint) ? "/" : envelope.Endpoint;
            if (!endpoint.StartsWith('/')) endpoint = "/" + endpoint;

            var client = _httpClientFactory.CreateClient();
            var uri = new Uri(new Uri(_options.LocalBaseUrl.TrimEnd('/')), endpoint);
            using var request = new HttpRequestMessage(new HttpMethod(envelope.Method ?? "GET"), uri);

            if (envelope.Headers != null)
            {
                foreach (var header in envelope.Headers)
                {
                    request.Headers.TryAddWithoutValidation(header.Key, header.Value);
                }
            }

            if (envelope.Body.HasValue && !IsBodylessMethod(request.Method.Method))
            {
                request.Content = new StringContent(
                    envelope.Body.Value.GetRawText(),
                    Encoding.UTF8,
                    "application/json");
            }

            using var response = await client.SendAsync(request, ct);
            var text = await response.Content.ReadAsStringAsync(ct);
            JsonElement? body = null;

            if (!string.IsNullOrWhiteSpace(text))
            {
                try
                {
                    body = JsonDocument.Parse(text).RootElement.Clone();
                }
                catch
                {
                    body = JsonDocument.Parse(JsonSerializer.Serialize(new { raw = text })).RootElement.Clone();
                }
            }

            return new ProxyResponse((int)response.StatusCode, body);
        }

        private async Task ForwardLocalEventsAsync(ClientWebSocket relaySocket, SemaphoreSlim sendLock, CancellationToken ct)
        {
            var localBase = new Uri(_options.LocalBaseUrl.TrimEnd('/'));
            var wsScheme = localBase.Scheme == "https" ? "wss" : "ws";
            var localWs = new UriBuilder(localBase)
            {
                Scheme = wsScheme,
                Path = "/ws"
            }.Uri;

            while (!ct.IsCancellationRequested && relaySocket.State == WebSocketState.Open)
            {
                try
                {
                    using var localSocket = new ClientWebSocket();
                    localSocket.Options.KeepAliveInterval = TimeSpan.FromSeconds(15);
                    await localSocket.ConnectAsync(localWs, ct);

                    while (!ct.IsCancellationRequested &&
                           localSocket.State == WebSocketState.Open &&
                           relaySocket.State == WebSocketState.Open)
                    {
                        var text = await ReceiveTextAsync(localSocket, ct);
                        if (text == null) break;

                        JsonElement payload;
                        try
                        {
                            payload = JsonDocument.Parse(text).RootElement.Clone();
                        }
                        catch
                        {
                            payload = JsonDocument.Parse(JsonSerializer.Serialize(new { raw = text })).RootElement.Clone();
                        }

                        await SendAsync(relaySocket, sendLock, new RelayEnvelope(Type: "agent_event", Payload: payload), ct);
                    }
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "Local event forwarding stopped");
                }

                await Task.Delay(TimeSpan.FromSeconds(3), ct);
            }
        }

        private static bool IsBodylessMethod(string method)
        {
            return string.Equals(method, "GET", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(method, "HEAD", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(method, "DELETE", StringComparison.OrdinalIgnoreCase);
        }

        private static async Task SendAsync(ClientWebSocket socket, SemaphoreSlim sendLock, object payload, CancellationToken ct)
        {
            if (socket.State != WebSocketState.Open) return;
            var json = JsonSerializer.Serialize(payload, JsonOptions);
            var bytes = Encoding.UTF8.GetBytes(json);
            await sendLock.WaitAsync(ct);
            try
            {
                if (socket.State == WebSocketState.Open)
                {
                    await socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
                }
            }
            finally
            {
                sendLock.Release();
            }
        }

        private static async Task<string?> ReceiveTextAsync(WebSocket socket, CancellationToken ct)
        {
            var buffer = new byte[16 * 1024];
            using var stream = new MemoryStream();

            try
            {
                while (true)
                {
                    var result = await socket.ReceiveAsync(buffer, ct);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        return null;
                    }

                    stream.Write(buffer, 0, result.Count);
                    if (result.EndOfMessage)
                    {
                        return Encoding.UTF8.GetString(stream.ToArray());
                    }
                }
            }
            catch (WebSocketException)
            {
                return null;
            }
        }

        private sealed record ProxyResponse(int Status, JsonElement? Body);

        private sealed record RelayEnvelope(
            string Type,
            string? Id = null,
            string? Method = null,
            string? Endpoint = null,
            Dictionary<string, string>? Headers = null,
            JsonElement? Body = null,
            int? Status = null,
            JsonElement? Payload = null,
            string? Message = null);
    }
}
