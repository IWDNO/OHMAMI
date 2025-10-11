import 'package:multicast_dns/multicast_dns.dart';

class AgentDiscovery {
    static const String ohmamiService = '_ohmami._tcp.local';

    static Future<List<String>> discoverAgents() async {
      final MDnsClient client = MDnsClient();
      final List<String> discovered = [];

      try {
        await client.start();
        await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(ohmamiService))) {
          await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(ptr.domainName))) {
            await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
                ResourceRecordQuery.addressIPv4(srv.target))) {
              discovered.add('http://${ip.address.address}:${srv.port}');
            }
          }
        }
      } catch (e) {
        print("mDNS discovery error: $e");
      } finally {
        client.stop();
      }

      return discovered;
    }
}