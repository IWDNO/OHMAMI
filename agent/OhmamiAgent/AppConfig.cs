using System;
using System.Collections.Generic;
using System.Text;

namespace OhmamiAgent
{
    public class AppConfig
    {
        public string Host { get; set; } = "0.0.0.0";
        public int Port { get; set; } = 5000;
        public int MetricsIntervalSeconds { get; set; } = 2;
        public int MediaIntervalSeconds { get; set; } = 3;
        public string MdnsServiceType { get; set; } = "_ohmami._tcp";
        public string MdnsServiceNameTemplate { get; set; } = "Ohmami-{0}._ohmami._tcp.local.";
    }
}
