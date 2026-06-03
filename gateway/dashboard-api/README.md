# dashboard-api.service

Local backend for the Qt HMI. Exposes a transport-neutral view of the system.

**Responsibilities**
- REST API for queries/actions; WebSocket event stream for live UI updates
- Read device state, telemetry history, alerts, health, OTA + cloud status from SQLite
- Write manual-control commands and local-rule changes into SQLite
- Acknowledge alerts; hide whether a device is Wi-Fi or CAN

Example endpoints: `http://127.0.0.1:8080/api`, `ws://127.0.0.1:8080/events`
(bind to `127.0.0.1` only).

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.3.
