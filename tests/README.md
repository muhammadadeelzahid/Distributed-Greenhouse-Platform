# Tests

Cross-component and integration tests for the platform.

Planned coverage:
- **cloud** — Go unit/integration tests for the gRPC service (`cloud/`).
- **gateway** — service-level tests against an in-memory/temp SQLite database.
- **transport** — end-to-end telemetry/command flows over WebSocket and CAN
  (`vcan0` virtual CAN for CI).
- **fixtures** — sample telemetry payloads and recorded CAN frames.

> Status: scaffold. See [docs/architecture.md](../docs/architecture.md) §17 for
> the data flows under test.
