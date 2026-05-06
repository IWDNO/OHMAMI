namespace OhmamiAgent.Remote
{
    public sealed class RemoteRelayOptions
    {
        public bool Enabled { get; set; }
        public string ServerUrl { get; set; } = "";
        public string AgentId { get; set; } = "";
        public string AgentToken { get; set; } = "";
        public string LocalBaseUrl { get; set; } = "http://127.0.0.1:5000";
        public int ReconnectSeconds { get; set; } = 5;
    }
}
