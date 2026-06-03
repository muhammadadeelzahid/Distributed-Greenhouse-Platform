# Database (gateway SQLite)

Local-first SQLite database for the Raspberry Pi gateway — the common
integration point between the transport gateways, `dashboard-api`, `local-rules`,
`cloud-sync`, and `health-agent`.

- **Path:** `/var/lib/greenhouse/gateway.db` (or `/data/greenhouse/gateway.db` on
  an immutable rootfs with a persistent data partition).
- **Schema:** [`schema.sql`](schema.sql) — `devices`, `telemetry`, `commands`,
  `alerts`, `health_reports`, `ota_status`, `sync_state`, `local_rules`,
  `ui_settings`, and an optional `can_frames` debug table.

Devices are transport-neutral: each row carries `transport` (`websocket` | `can`)
and an optional CAN `node_id`. The long-term/server-side schema (PostgreSQL) lives
in [cloud/migrations](../cloud/migrations/).

See [docs/architecture.md](../docs/architecture.md) §8.

> Status: `devices`, `telemetry`, `commands`, and `can_frames` are specified in
> the architecture; the remaining tables are drafted here and finalized during
> implementation.
