# Tools

Developer utilities for working on the platform.

Planned:
- **proto** — regenerate gRPC stubs from [cloud/proto](../cloud/proto/).
- **sim** — fake ESP32 nodes (WebSocket + CAN) to drive the gateway without hardware.
- **canlog** — decode/replay CAN frames against the frame spec
  ([docs/architecture.md](../docs/architecture.md) §11).
- **db** — initialize / inspect the gateway SQLite database
  ([database/schema.sql](../database/schema.sql)).

> Status: scaffold.
