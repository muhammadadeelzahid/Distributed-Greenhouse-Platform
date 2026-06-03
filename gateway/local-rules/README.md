# local-rules.service

Offline automation so the system keeps working without the cloud.

**Responsibilities**
- Read latest sensor values from SQLite and apply rules
- Create local commands in SQLite (delivered by the matching transport gateway)
- Store rule-evaluation results and alerts

Example rules: soil moisture < 30% → pump on 10 s; temperature > 30 °C → fan on;
stale sensor data → raise alert.

It never sends CAN/WebSocket messages directly — it only writes commands to SQLite.

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.5.
