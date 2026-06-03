# cloud-sync.service

gRPC client to the Render cloud backend ([cloud/](../../cloud/)).

**Responsibilities**
- Open a secure gRPC connection (TLS); handle retry/reconnect
- Upload unsynced telemetry, command results, health reports, OTA status
- Download cloud commands and configuration updates
- Mark local records `synced` after upload; update cloud status in SQLite

Talks to ESP32 nodes only indirectly — through SQLite.

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.4.
