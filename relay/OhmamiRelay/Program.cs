using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
});

var app = builder.Build();
var relay = new RelayHub(app.Logger);
var requiredAgentToken = app.Configuration.GetValue<string>("Relay:AgentToken") ?? "";

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(20)
});

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/agents", () =>
{
    var agents = relay.ListAgents();
    return Results.Ok(new { status = "ok", data = agents });
});

app.MapPost("/agents/{agentId}/proxy", async (string agentId, ProxyRequest request, HttpContext context) =>
{
    try
    {
        var response = await relay.SendRequestAsync(agentId, request, context.RequestAborted);
        return Results.Json(response.Body, statusCode: response.Status);
    }
    catch (KeyNotFoundException ex)
    {
        return Results.NotFound(new { status = "error", message = ex.Message });
    }
    catch (TimeoutException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status504GatewayTimeout);
    }
    catch (IOException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (WebSocketException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (InvalidOperationException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.Map("/agent/ws", async context =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    var agentId = context.Request.Query["agentId"].ToString();
    var token = context.Request.Query["token"].ToString();

    if (string.IsNullOrWhiteSpace(agentId))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("agentId is required");
        return;
    }

    if (!string.IsNullOrEmpty(requiredAgentToken) && token != requiredAgentToken)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await relay.HandleAgentAsync(agentId, socket, context.RequestAborted);
});

app.Map("/clients/ws", async context =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    var agentId = context.Request.Query["agentId"].ToString();
    if (string.IsNullOrWhiteSpace(agentId))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("agentId is required");
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await relay.HandleClientEventsAsync(agentId, socket, context.RequestAborted);
});

app.Run();

public sealed record AgentInfo(string AgentId, bool Online, DateTimeOffset ConnectedAt);

public sealed record ProxyRequest(
    string Method,
    string Endpoint,
    Dictionary<string, string>? Headers = null,
    JsonElement? Body = null);

public sealed record ProxyResponse(int Status, JsonElement? Body);

public sealed record RelayEnvelope(
    string Type,
    string? Id = null,
    string? Method = null,
    string? Endpoint = null,
    Dictionary<string, string>? Headers = null,
    JsonElement? Body = null,
    int? Status = null,
    JsonElement? Payload = null,
    string? Message = null);

public sealed class RelayHub
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ConcurrentDictionary<string, AgentConnection> _agents = new();
    private readonly ConcurrentDictionary<string, PendingRequest> _pending = new();
    private readonly ConcurrentDictionary<string, ConcurrentDictionary<Guid, WebSocket>> _clientEventSockets = new();
    private readonly ILogger _logger;

    public RelayHub(ILogger logger)
    {
        _logger = logger;
    }

    public IReadOnlyCollection<AgentInfo> ListAgents()
    {
        return _agents
            .Select(pair => new AgentInfo(pair.Key, pair.Value.Socket.State == WebSocketState.Open, pair.Value.ConnectedAt))
            .OrderBy(agent => agent.AgentId)
            .ToArray();
    }

    public async Task HandleAgentAsync(string agentId, WebSocket socket, CancellationToken ct)
    {
        var connection = new AgentConnection(socket, DateTimeOffset.UtcNow);
        _agents.AddOrUpdate(agentId, connection, (_, old) =>
        {
            TryAbort(old.Socket);
            return connection;
        });

        _logger.LogInformation("Agent {agentId} connected", agentId);

        try
        {
            while (!ct.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var json = await ReceiveTextAsync(socket, ct);
                if (json == null) break;

                var envelope = JsonSerializer.Deserialize<RelayEnvelope>(json, JsonOptions);
                if (envelope == null) continue;

                if (envelope.Type == "http_response" && !string.IsNullOrWhiteSpace(envelope.Id))
                {
                    if (_pending.TryRemove(envelope.Id, out var pending))
                    {
                        pending.Complete(new ProxyResponse(envelope.Status ?? 500, envelope.Body));
                    }
                }
                else if (envelope.Type == "agent_event")
                {
                    await BroadcastEventAsync(agentId, envelope.Payload ?? envelope.Body, ct);
                }
                else if (envelope.Type == "error" && !string.IsNullOrWhiteSpace(envelope.Id))
                {
                    if (_pending.TryRemove(envelope.Id, out var pending))
                    {
                        pending.Fail(new InvalidOperationException(envelope.Message ?? "Agent returned error"));
                    }
                }
            }
        }
        finally
        {
            var isCurrentConnection = _agents.TryGetValue(agentId, out var current) && ReferenceEquals(current, connection);
            if (isCurrentConnection)
            {
                _agents.TryRemove(agentId, out _);
                foreach (var request in _pending.Where(pair => pair.Value.AgentId == agentId).ToArray())
                {
                    if (_pending.TryRemove(request.Key, out var pending))
                    {
                        pending.Fail(new IOException("Agent disconnected"));
                    }
                }
            }

            _logger.LogInformation("Agent {agentId} disconnected", agentId);
        }
    }

    public async Task HandleClientEventsAsync(string agentId, WebSocket socket, CancellationToken ct)
    {
        var id = Guid.NewGuid();
        var sockets = _clientEventSockets.GetOrAdd(agentId, _ => new ConcurrentDictionary<Guid, WebSocket>());
        sockets[id] = socket;

        try
        {
            while (!ct.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var message = await ReceiveTextAsync(socket, ct);
                if (message == null) break;
            }
        }
        finally
        {
            sockets.TryRemove(id, out _);
        }
    }

    public async Task<ProxyResponse> SendRequestAsync(string agentId, ProxyRequest request, CancellationToken ct)
    {
        if (!_agents.TryGetValue(agentId, out var agent) || agent.Socket.State != WebSocketState.Open)
        {
            throw new KeyNotFoundException($"Agent '{agentId}' is not connected");
        }

        var id = Guid.NewGuid().ToString("N");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));

        var pending = new PendingRequest(agentId, timeout.Token);
        if (!_pending.TryAdd(id, pending))
        {
            throw new InvalidOperationException("Could not register pending request");
        }

        var envelope = new RelayEnvelope(
            Type: "http_request",
            Id: id,
            Method: request.Method,
            Endpoint: request.Endpoint,
            Headers: request.Headers,
            Body: request.Body);

        try
        {
            await SendAsync(agent, envelope, timeout.Token);
        }
        catch
        {
            _pending.TryRemove(id, out _);
            throw;
        }

        try
        {
            return await pending.Task.WaitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            _pending.TryRemove(id, out _);
            throw new TimeoutException("Agent did not respond in time");
        }
    }

    private async Task BroadcastEventAsync(string agentId, JsonElement? payload, CancellationToken ct)
    {
        if (!_clientEventSockets.TryGetValue(agentId, out var sockets)) return;
        var data = payload.HasValue ? payload.Value.GetRawText() : "{}";
        var bytes = Encoding.UTF8.GetBytes(data);

        foreach (var pair in sockets.ToArray())
        {
            var socket = pair.Value;
            if (socket.State != WebSocketState.Open)
            {
                sockets.TryRemove(pair.Key, out _);
                continue;
            }

            try
            {
                await socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
            }
            catch
            {
                sockets.TryRemove(pair.Key, out _);
            }
        }
    }

    private static async Task SendAsync(AgentConnection agent, object payload, CancellationToken ct)
    {
        var socket = agent.Socket;
        var json = JsonSerializer.Serialize(payload, JsonOptions);
        var bytes = Encoding.UTF8.GetBytes(json);
        await agent.SendLock.WaitAsync(ct);
        try
        {
            if (socket.State == WebSocketState.Open)
            {
                await socket.SendAsync(bytes, WebSocketMessageType.Text, true, ct);
            }
        }
        finally
        {
            agent.SendLock.Release();
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

    private static void TryAbort(WebSocket socket)
    {
        try { socket.Abort(); } catch { }
    }

    private sealed record AgentConnection(WebSocket Socket, DateTimeOffset ConnectedAt)
    {
        public SemaphoreSlim SendLock { get; } = new(1, 1);
    }

    private sealed class PendingRequest
    {
        private readonly TaskCompletionSource<ProxyResponse> _source = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public PendingRequest(string agentId, CancellationToken ct)
        {
            AgentId = agentId;
            ct.Register(() => _source.TrySetCanceled(ct));
        }

        public string AgentId { get; }
        public Task<ProxyResponse> Task => _source.Task;
        public void Complete(ProxyResponse response) => _source.TrySetResult(response);
        public void Fail(Exception exception) => _source.TrySetException(exception);
    }
}
