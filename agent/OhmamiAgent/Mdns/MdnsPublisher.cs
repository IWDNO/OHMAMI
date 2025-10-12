using Makaretu.Dns;
using System;
using System.Collections.Generic;
using System.Net;
using System.Text;

namespace OhmamiAgent.Mdns
{
    public class MdnsPublisher : IDisposable
    {
        private readonly ILogger<MdnsPublisher> logger;
        private readonly IConfiguration config;
        private MulticastService? multicast;
        private ServiceDiscovery? sd;
        private ServiceProfile? profile;

        public MdnsPublisher(ILogger<MdnsPublisher> logger, IConfiguration config)
        {
            this.logger = logger;
            this.config = config;
        }

        public Task RegisterAsync(IConfiguration configuration)
        {
            var port = configuration.GetValue<int>("Port");
            var template = configuration.GetValue<string>("MdnsServiceNameTemplate");
            var type = configuration.GetValue<string>("MdnsServiceType");

            var hostname = Dns.GetHostName();
            var serviceName = string.Format(template, hostname);

            multicast = new MulticastService();
            sd = new ServiceDiscovery(multicast);

            profile = new ServiceProfile(serviceName, type, (ushort)port);
            // properties example: path -> /ws
            profile.AddProperty("path", "/ws");

            multicast.Start();
            sd.Advertise(profile);

            logger.LogInformation("mDNS registered: {service} on port {port}", serviceName, port);
            return Task.CompletedTask;
        }

        public void Dispose()
        {
            try
            {
                if (sd != null && profile != null)
                {
                    sd.Unadvertise(profile);
                }
                multicast?.Stop();
                multicast?.Dispose();
                sd?.Dispose();
                logger.LogInformation("mDNS unregistered");
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error while unregistering mDNS");
            }
        }
    }
}
