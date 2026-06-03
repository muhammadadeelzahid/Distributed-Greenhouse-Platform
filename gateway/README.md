# Gateway (Raspberry Pi services)

Local-first embedded Linux gateway that runs on the Raspberry Pi. A small set of
systemd services communicate **only through the local SQLite database**
(`/var/lib/greenhouse/gateway.db`), which decouples device transports from the UI
and the cloud.

| Service | Role |
|---|---|
| [websocket-gateway](websocket-gateway/) | ESP32 Wi-Fi/WebSocket sessions, telemetry, command delivery |
| [can-gateway](can-gateway/) | ESP32 CAN frames via SocketCAN, decode/encode, command delivery |
| [dashboard-api](dashboard-api/) | Local REST + WebSocket backend for the Qt HMI |
| [cloud-sync](cloud-sync/) | gRPC client to the Render cloud backend; upload backlog + download commands |
| [local-rules](local-rules/) | Offline automation; writes commands into SQLite |
| [health-agent](health-agent/) | System/service health into SQLite |

Gateway OS updates (OTA) are handled by the Yocto RAUC + hawkBit path in
[yocto/meta-greenhouse](../yocto/meta-greenhouse/), not a service here.

## Design rules
- The Qt HMI talks only to `dashboard-api`, never directly to ESP32, CAN, or SQLite.
- Each device row carries a `transport` (`websocket` | `can`); the matching gateway
  service delivers its commands.
- All persistent state lives in SQLite so the system survives reboots and cloud outages.

Systemd unit files: [deployment/systemd](../deployment/systemd/).
Full responsibilities: [docs/architecture.md](../docs/architecture.md) §6.

> Status: design stubs — implementation in progress.
