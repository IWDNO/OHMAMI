using Microsoft.Extensions.Options;
using System.Text;
using System.Text.Json;

namespace OhmamiAgent.Remote
{
    public sealed class RemotePairingService
    {
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly RemoteRelayOptions _options;

        public RemotePairingService(IHttpClientFactory httpClientFactory, IOptions<RemoteRelayOptions> options)
        {
            _httpClientFactory = httpClientFactory;
            _options = options.Value;
        }

        public async Task<PairingCodeResult> CreatePairingCodeAsync(CancellationToken ct)
        {
            if (!_options.Enabled)
            {
                throw new InvalidOperationException("Remote relay is disabled");
            }

            var agentId = string.IsNullOrWhiteSpace(_options.AgentId)
                ? Environment.MachineName
                : _options.AgentId;

            var serverUri = new Uri(_options.ServerUrl.TrimEnd('/'));
            var endpoint = new Uri(serverUri, $"/agents/{Uri.EscapeDataString(agentId)}/pairing-codes");

            var client = _httpClientFactory.CreateClient();
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
            {
                Content = new StringContent("{}", Encoding.UTF8, "application/json")
            };
            request.Headers.TryAddWithoutValidation("X-Agent-Bootstrap-Token", _options.AgentToken);

            using var response = await client.SendAsync(request, ct);
            var json = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"Relay returned {(int)response.StatusCode}: {json}");
            }

            var payload = JsonSerializer.Deserialize<PairingEnvelope>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (payload?.Data == null)
            {
                throw new InvalidOperationException("Relay returned empty pairing payload");
            }

            return payload.Data;
        }

        private sealed record PairingEnvelope(PairingCodeResult? Data);
    }

    public sealed record PairingCodeResult(string Code, DateTimeOffset ExpiresAt);
}
