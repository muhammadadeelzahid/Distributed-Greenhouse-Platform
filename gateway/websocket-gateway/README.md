# websocket-gateway.service

Handles local ESP32 communication over Wi-Fi using WebSocket.

**Responsibilities**
- Accept and authenticate ESP32 WebSocket connections (per-device token)
- Register Wi-Fi devices; track online/offline state
- Receive telemetry, heartbeats, command acks/results → write to SQLite
- Read `pending` commands with `target_transport = websocket` and deliver them

**Runtime state:** in-memory map `device_id -> active WebSocket connection`
(live connections only; persistent state is in SQLite).

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.1.
