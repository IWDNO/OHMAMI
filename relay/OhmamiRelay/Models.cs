using System.Text.Json;

public sealed record RegisterMobileDeviceRequest(string DeviceId, string? DeviceName);
public sealed record PairMobileDeviceRequest(string Code);
public sealed record CreatePairingCodeResponse(string Code, DateTimeOffset ExpiresAt);
public sealed record MobileDeviceAuth(Guid Id, string DeviceId, string DeviceName);
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
public sealed record AgentInfo(string AgentId, bool Online, DateTimeOffset ConnectedAt);
public sealed record AccessibleAgent(
    string AgentId,
    string Name,
    bool IsOnline,
    DateTimeOffset LastSeenAt,
    DateTimeOffset PairedAt);
