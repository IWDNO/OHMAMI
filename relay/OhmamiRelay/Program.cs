using System.Text.Json;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull;
});

var relayOptions = builder.Configuration.GetSection("Relay").Get<RelayOptions>() ?? new RelayOptions();
builder.Services.AddSingleton(relayOptions);

var connectionString = builder.Configuration.GetConnectionString("Postgres")
    ?? throw new InvalidOperationException("ConnectionStrings:Postgres is required");
builder.Services.AddSingleton(_ => new NpgsqlDataSourceBuilder(connectionString).Build());
builder.Services.AddSingleton<RelayDb>();
builder.Services.AddSingleton<RelayHub>();
builder.Services.AddHostedService<RelayDbInitializer>();

var app = builder.Build();

app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(20)
});

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/ping", () => Results.Ok(new { status = "ok" }));

app.MapPost("/mobile-devices/register", async (RegisterMobileDeviceRequest request, RelayDb db, HttpContext context) =>
{
    if (string.IsNullOrWhiteSpace(request.DeviceId))
    {
        return Results.BadRequest(new { status = "error", message = "deviceId is required" });
    }

    var result = await db.RegisterMobileDeviceAsync(request.DeviceId.Trim(), request.DeviceName, context.RequestAborted);
    return Results.Ok(new
    {
        status = "ok",
        data = new
        {
            deviceId = result.Device.DeviceId,
            deviceName = result.Device.DeviceName,
            accessToken = result.AccessToken
        }
    });
});

app.MapPost("/mobile-devices/me/pair", async (
    PairMobileDeviceRequest request,
    RelayDb db,
    RelayHub relay,
    HttpContext context) =>
{
    var device = await AuthenticateMobileDeviceAsync(context, db);
    if (device is null)
    {
        return Results.Json(new { status = "error", message = "Unauthorized mobile device" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    if (string.IsNullOrWhiteSpace(request.Code))
    {
        return Results.BadRequest(new { status = "error", message = "code is required" });
    }

    var agent = await db.PairMobileDeviceAsync(device.Id, request.Code.Trim(), relay.IsAgentOnline, context.RequestAborted);
    if (agent is null)
    {
        return Results.BadRequest(new { status = "error", message = "Invalid or expired pairing code" });
    }

    return Results.Ok(new { status = "ok", data = agent });
});

app.MapGet("/mobile-devices/me/agents", async (RelayDb db, RelayHub relay, HttpContext context) =>
{
    var device = await AuthenticateMobileDeviceAsync(context, db);
    if (device is null)
    {
        return Results.Json(new { status = "error", message = "Unauthorized mobile device" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    var agents = await db.GetAgentsForMobileDeviceAsync(device.Id, relay.IsAgentOnline, context.RequestAborted);
    return Results.Ok(new { status = "ok", data = agents });
});

app.MapGet("/agents", (RelayHub relay) =>
{
    var agents = relay.ListAgents();
    return Results.Ok(new { status = "ok", data = agents });
});

app.MapPost("/agents/{agentId}/pairing-codes", async (string agentId, RelayDb db, RelayHub relay, HttpContext context) =>
{
    if (!AuthorizeBootstrapAgent(context, relayOptions))
    {
        return Results.Json(new { status = "error", message = "Unauthorized agent" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    if (!relay.IsAgentOnline(agentId))
    {
        return Results.Json(new { status = "error", message = "Agent is offline" }, statusCode: StatusCodes.Status409Conflict);
    }

    if (!await db.AgentExistsAsync(agentId, context.RequestAborted))
    {
        return Results.NotFound(new { status = "error", message = $"Agent '{agentId}' is not registered" });
    }

    var pairingCode = await db.CreatePairingCodeAsync(agentId, context.RequestAborted);
    return Results.Ok(new { status = "ok", data = pairingCode });
});

app.MapPost("/agents/{agentId}/proxy", async (string agentId, ProxyRequest request, RelayDb db, RelayHub relay, HttpContext context) =>
{
    var device = await AuthenticateMobileDeviceAsync(context, db);
    if (device is null)
    {
        return Results.Json(new { status = "error", message = "Unauthorized mobile device" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    if (!await db.HasPairingAsync(device.Id, agentId, context.RequestAborted))
    {
        return Results.Json(new { status = "error", message = "This device is not paired with the agent" }, statusCode: StatusCodes.Status403Forbidden);
    }

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
    catch (System.Net.WebSockets.WebSocketException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (InvalidOperationException ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.MapGet("/agents/{agentId}/files/download", async (string agentId, string path, RelayDb db, RelayHub relay, HttpContext context) =>
{
    var device = await AuthenticateMobileDeviceAsync(context, db);
    if (device is null)
    {
        return Results.Json(new { status = "error", message = "Unauthorized mobile device" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    if (!await db.HasPairingAsync(device.Id, agentId, context.RequestAborted))
    {
        return Results.Json(new { status = "error", message = "This device is not paired with the agent" }, statusCode: StatusCodes.Status403Forbidden);
    }

    var endpoint = $"/fs/download?path={Uri.EscapeDataString(path)}";

    try
    {
        var response = await relay.SendRequestAsync(agentId, new ProxyRequest("GET", endpoint), context.RequestAborted);
        if (response.Status != 200 || response.Body is null)
        {
            return Results.Json(response.Body, statusCode: response.Status);
        }

        var payload = response.Body.Value;
        var base64 = payload.TryGetProperty("contentBase64", out var base64Node) ? base64Node.GetString() : null;
        if (string.IsNullOrWhiteSpace(base64))
        {
            return Results.Json(new { status = "error", message = "Relay did not return file content" }, statusCode: StatusCodes.Status502BadGateway);
        }

        var bytes = Convert.FromBase64String(base64);
        var contentType = payload.TryGetProperty("contentType", out var contentTypeNode)
            ? contentTypeNode.GetString()
            : "application/octet-stream";
        var fileName = payload.TryGetProperty("fileName", out var fileNameNode)
            ? fileNameNode.GetString()
            : Path.GetFileName(path);

        return Results.File(bytes, contentType ?? "application/octet-stream", fileName ?? Path.GetFileName(path));
    }
    catch (Exception ex) when (ex is KeyNotFoundException or TimeoutException or IOException or System.Net.WebSockets.WebSocketException or InvalidOperationException)
    {
        return ToRelayErrorResult(ex);
    }
});

app.MapPost("/agents/{agentId}/files/upload", async (string agentId, string dest, RelayDb db, RelayHub relay, HttpContext context) =>
{
    var device = await AuthenticateMobileDeviceAsync(context, db);
    if (device is null)
    {
        return Results.Json(new { status = "error", message = "Unauthorized mobile device" }, statusCode: StatusCodes.Status401Unauthorized);
    }

    if (!await db.HasPairingAsync(device.Id, agentId, context.RequestAborted))
    {
        return Results.Json(new { status = "error", message = "This device is not paired with the agent" }, statusCode: StatusCodes.Status403Forbidden);
    }

    if (!context.Request.HasFormContentType)
    {
        return Results.BadRequest(new { status = "error", message = "Multipart form is required" });
    }

    var form = await context.Request.ReadFormAsync(context.RequestAborted);
    var file = form.Files["file"] ?? form.Files.FirstOrDefault();
    if (file == null || file.Length == 0)
    {
        return Results.BadRequest(new { status = "error", message = "File is required" });
    }

    await using var stream = file.OpenReadStream();
    using var memory = new MemoryStream();
    await stream.CopyToAsync(memory, context.RequestAborted);

    var endpoint = $"/fs/upload-base64?dest={Uri.EscapeDataString(dest)}";
    var body = JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(new
    {
        fileName = file.FileName,
        contentBase64 = Convert.ToBase64String(memory.ToArray())
    })).RootElement.Clone();

    try
    {
        var response = await relay.SendRequestAsync(agentId, new ProxyRequest("POST", endpoint, Body: body), context.RequestAborted);
        return Results.Json(response.Body, statusCode: response.Status);
    }
    catch (Exception ex) when (ex is KeyNotFoundException or TimeoutException or IOException or System.Net.WebSockets.WebSocketException or InvalidOperationException)
    {
        return ToRelayErrorResult(ex);
    }
});

app.Map("/agent/ws", async (HttpContext context, RelayHub relay, RelayDb db) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    if (!AuthorizeBootstrapAgent(context, relayOptions))
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return;
    }

    var agentId = context.Request.Query["agentId"].ToString();
    var name = context.Request.Query["name"].ToString();

    if (string.IsNullOrWhiteSpace(agentId))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("agentId is required");
        return;
    }

    var resolvedName = string.IsNullOrWhiteSpace(name) ? agentId : name;
    await db.UpsertAgentAsync(agentId, resolvedName, context.RequestAborted);

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await relay.HandleAgentAsync(agentId, socket, context.RequestAborted);
});

app.Map("/clients/ws", async (HttpContext context, RelayHub relay, RelayDb db) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }

    var device = await AuthenticateMobileDeviceFromQueryAsync(context, db);
    if (device is null)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        return;
    }

    var agentId = context.Request.Query["agentId"].ToString();
    if (string.IsNullOrWhiteSpace(agentId))
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("agentId is required");
        return;
    }

    if (!await db.HasPairingAsync(device.Id, agentId, context.RequestAborted))
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await relay.HandleClientEventsAsync(agentId, socket, context.RequestAborted);
});

app.Run();

static async Task<MobileDeviceAuth?> AuthenticateMobileDeviceAsync(HttpContext context, RelayDb db)
{
    var deviceId = context.Request.Headers["X-Mobile-Device-Id"].ToString();
    var accessToken = context.Request.Headers["X-Mobile-Access-Token"].ToString();

    if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(accessToken))
    {
        return null;
    }

    return await db.AuthenticateMobileDeviceAsync(deviceId.Trim(), accessToken.Trim(), context.RequestAborted);
}

static async Task<MobileDeviceAuth?> AuthenticateMobileDeviceFromQueryAsync(HttpContext context, RelayDb db)
{
    var deviceId = context.Request.Query["deviceId"].ToString();
    var accessToken = context.Request.Query["token"].ToString();

    if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(accessToken))
    {
        return null;
    }

    return await db.AuthenticateMobileDeviceAsync(deviceId.Trim(), accessToken.Trim(), context.RequestAborted);
}

static bool AuthorizeBootstrapAgent(HttpContext context, RelayOptions options)
{
    var provided = context.Request.Headers["X-Agent-Bootstrap-Token"].ToString();
    if (string.IsNullOrWhiteSpace(provided))
    {
        provided = context.Request.Query["token"].ToString();
    }

    return !string.IsNullOrWhiteSpace(provided) &&
           string.Equals(provided.Trim(), options.AgentBootstrapToken, StringComparison.Ordinal);
}

static IResult ToRelayErrorResult(Exception ex)
{
    return ex switch
    {
        KeyNotFoundException keyNotFound => Results.NotFound(new { status = "error", message = keyNotFound.Message }),
        TimeoutException timeout => Results.Json(new { status = "error", message = timeout.Message }, statusCode: StatusCodes.Status504GatewayTimeout),
        IOException io => Results.Json(new { status = "error", message = io.Message }, statusCode: StatusCodes.Status503ServiceUnavailable),
        System.Net.WebSockets.WebSocketException ws => Results.Json(new { status = "error", message = ws.Message }, statusCode: StatusCodes.Status503ServiceUnavailable),
        InvalidOperationException invalid => Results.Json(new { status = "error", message = invalid.Message }, statusCode: StatusCodes.Status503ServiceUnavailable),
        _ => Results.Json(new { status = "error", message = ex.Message }, statusCode: StatusCodes.Status500InternalServerError)
    };
}
