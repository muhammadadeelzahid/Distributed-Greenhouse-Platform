# Qt HMI

Front-facing touchscreen application for the Raspberry Pi. It talks **only** to
`dashboard-api.service` (REST for actions, WebSocket for live updates) — never
directly to ESP32 nodes, CAN, SQLite, RAUC, or the cloud.

**Screens** (see [docs/architecture.md](../../docs/architecture.md) §14):
1. **Overview** — system / cloud / CAN status, online node counts, latest readings, actuator state, alerts
2. **Devices** — id, type, transport, CAN node_id, last seen, firmware, RSSI/heap, capabilities
3. **Telemetry** — latest values, recent history, graphs, min/max
4. **Manual control** — pump / fan / light / valve, duration commands (transport shown)
5. **Rules** — thresholds, watering duration, enable/disable automation
6. **Alerts** — device offline, sensor stale, command failed, cloud/Wi-Fi/CAN faults, disk low, OTA failed
7. **OTA** — current version + RAUC slot, available update, install status, reboot required
8. **Cloud status** — connection state, last sync, unsynced count, last error
9. **Settings** — network, CAN bitrate/interface, gateway identity, display, thresholds

Runs as `qt-hmi.service` (kiosk / `eglfs`) — see
[deployment/systemd/qt-hmi.service](../../deployment/systemd/qt-hmi.service).

> Status: design stub.
