# Ohmami Relay

HTTP/WS relay for remote Ohmami connections through a VPS.

## Run locally

```powershell
dotnet run --project relay/OhmamiRelay/OhmamiRelay.csproj
```

Default URL: `http://0.0.0.0:8080`.

## VPS

Publish and run the app on the VPS, then open TCP port `8080`.

```bash
dotnet publish -c Release -o /opt/ohmami-relay
cd /opt/ohmami-relay
Relay__AgentToken='change-this-token' ASPNETCORE_URLS='http://0.0.0.0:8080' dotnet OhmamiRelay.dll
```

Agent WebSocket:

```text
ws://VPS_IP:8080/agent/ws?agentId=MY-PC&token=change-this-token
```

Flutter proxy base:

```text
http://VPS_IP:8080
```
