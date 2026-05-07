# Ohmami Relay

HTTP/WS relay for remote Ohmami connections through a VPS with PostgreSQL-backed
mobile devices, pairings, and agent registry.

## PostgreSQL

Example database bootstrap on Ubuntu:

```bash
sudo -u postgres psql
create database ohmami_relay;
create user ohmami with encrypted password 'change-me';
grant all privileges on database ohmami_relay to ohmami;
\q
```

## Run locally

```powershell
dotnet run --project relay/OhmamiRelay/OhmamiRelay.csproj
```

Default URL: `http://0.0.0.0:8080`.

## VPS

Publish and run the app on the VPS, then open TCP port `8080`.

```bash
dotnet publish -c Release -o /opt/ohmami-relay relay/OhmamiRelay/OhmamiRelay.csproj
cd /opt/ohmami-relay
ConnectionStrings__Postgres='Host=127.0.0.1;Port=5432;Database=ohmami_relay;Username=ohmami;Password=change-me' \
Relay__AgentBootstrapToken='change-this-token' \
ASPNETCORE_URLS='http://0.0.0.0:8080' \
dotnet OhmamiRelay.dll
```

## Main flows

Agent websocket:

```text
ws://VPS_IP:8080/agent/ws?agentId=MY-PC&token=change-this-token&name=DESKTOP-NAME
```

Create pairing code from the agent:

```http
POST /agents/MY-PC/pairing-codes
X-Agent-Bootstrap-Token: change-this-token
```

Register mobile device:

```http
POST /mobile-devices/register
Content-Type: application/json

{
  "deviceId": "generated-mobile-uuid",
  "deviceName": "Android phone"
}
```

Pair mobile device with agent:

```http
POST /mobile-devices/me/pair
X-Mobile-Device-Id: generated-mobile-uuid
X-Mobile-Access-Token: issued-token
Content-Type: application/json

{
  "code": "483921"
}
```

Load paired PCs:

```http
GET /mobile-devices/me/agents
X-Mobile-Device-Id: generated-mobile-uuid
X-Mobile-Access-Token: issued-token
```
