# Plan — Developer C: Raspberry Pi Gateway

> **Owner:** Developer C (Raspberry Pi / Embedded Linux)
> **Folder:** `yocto/` (gateway services) + integration with `cloud/`
> **Architecture refs:** `docs/architecture.md` §4–§8, §13, §15–§17, §18.3
> **Mission:** Be the hub the edge nodes talk to — **Dev A's ESP32-S3** over Wi-Fi/WebSocket
> and **Dev B's ESP32-S3** over CAN. Normalize both into SQLite, deliver commands back out on
> the right transport, and (later) sync to the cloud over gRPC. **Your earliest job is to
> unblock Dev A and Dev B with test endpoints they can talk to today.**

> Note: per the team's focus, the deep Yocto image work is lower priority — get the
> *services and the integration seams* working first (they run fine on plain
> Raspberry Pi OS or even a laptop), then package with Yocto. The existing
> `origin/CAN` branch already adds SocketCAN (`can0`, `can-utils`, systemd-networkd)
> — reuse it.

---

## Why this track (resume / interview value)
- **Embedded Linux services**: multi-process systemd architecture, transport separation, an offline-first local DB.
- **Two device transports**: a WebSocket server *and* SocketCAN frame decoding into one normalized model.
- **A real local API** (REST + WebSocket) backing an HMI.
- **Cloud sync** over **gRPC/TLS** against the existing Go backend.
- **Device onboarding**: a mobile-app provisioning flow — LAN `dashboard-api` endpoints, a backend mobile API, and cloud→hub authorization over gRPC (see [`provisioning-and-onboarding-flow.md`](provisioning-and-onboarding-flow.md)).
- **(Later) Yocto/RAUC**: building a real device image with A/B OTA.

---

## Integration contract (you define it *with* Dev A and Dev B — you're the consumer)
You decode what the nodes emit, so you co-own both formats:
- **WebSocket JSON** (architecture §10) from Dev A — register/telemetry/heartbeat/command/ack/result.
- **CAN frames** (architecture §11) from Dev B — ID scheme + byte layouts + scaling factors.
- **SQLite as the integration point** (§8): both gateways write the same `devices`,
  `telemetry`, `commands`, `command_results` tables; everything downstream reads SQLite.

---

## Milestones

### M0 — Test harness to UNBLOCK the node devs (do this first)
Both ESP32-S3 nodes (Dev A Wi-Fi + Dev B CAN) need something to talk to *now*, before any real gateway exists.
- **WebSocket test endpoint** (small Python `websockets` or Go server): accepts a connection,
  replies to `register` with `register_ack`, and logs/prints incoming telemetry, heartbeat, command_result. Add a way to *push* a `command` so Dev A can test the inbound path.
- **CAN test bench**: bring up `vcan0` (virtual CAN) + `can-utils` (`candump`, `cansend`, `cangen`) so Dev B can verify the ESP32-S3 CAN frame layouts before the real Pi bus exists, and you can `cansend` test commands.
- **Deliverable:** documented "point your node here" instructions in a README; both Dev A and Dev B can integrate against it.
- **You learn:** WebSocket servers, SocketCAN/`vcan`, the value of a contract test harness.

### M1 — SQLite schema + tiny data-access layer
- Create the schema from §8 (`devices`, `telemetry`, `commands`, `command_results`, plus the optional `can_frames` debug table). Include the `transport` column (§7).
- A small module both gateway services share for upsert-device / insert-telemetry / read-pending-commands / update-command-status.
- **Acceptance:** schema migrates cleanly; basic CRUD covered by tests.
- **You learn:** local-first persistence, schema design for offline buffering + sync flags.

### M2 — `websocket-gateway.service` (Dev A's path; architecture §6.1, §17.1)
- Accept ESP32 WebSocket sessions; validate device token (§18.1); maintain the in-memory `device_id → connection` map.
- Parse §10 JSON → upsert device, insert telemetry (`synced=0`), track heartbeat/online state.
- Command loop (§13): read `pending` commands where `transport=websocket`, deliver to connected nodes, mark `sent`; handle inbound `command_ack`/`command_result`.
- **Acceptance:** Dev A's node registers, telemetry lands in SQLite, a command round-trips.
- **You learn:** connection management, JSON ingest, command delivery state machine.

### M3 — `can-gateway.service` (Dev B's ESP32-S3 CAN path; architecture §6.2, §17.2)
- Use SocketCAN (`python-can` or Go) on `can0` (reuse `origin/CAN` setup, typically a Microchip MCP2515 SPI-CAN hat); maintain `device_id ↔ node_id` map.
- Decode §11 frames from the ESP32-S3 CAN node → insert telemetry, update status, store command_results; infer online/offline from heartbeat timeout (no persistent connection).
- Command loop: read `pending` `transport=can` commands → encode → send on the bus (`cansend`/SocketCAN) → mark `sent`; match ack/result by `command_sequence`.
- **Acceptance:** the ESP32-S3 CAN node's telemetry lands in SQLite; a `cansend`-delivered command acks + results. This is the live **cross-stack (RTOS-firmware ↔ ARM-Linux) CAN link**.
- **You learn:** SocketCAN integration, binary frame decode/encode, connectionless device tracking.

### M4 — `dashboard-api.service` stub (architecture §6.3, §17.3)
- Local REST for queries/actions + a WebSocket event stream, reading/writing SQLite. Transport-neutral device view (§7) — the API must not leak whether a device is Wi-Fi or CAN.
- **Acceptance:** `GET /api/devices`, `GET /api/telemetry`, `POST /api/commands` work end-to-end into the right gateway.
- **You learn:** clean API boundaries, decoupling the UI from transport details.

### M5 — `cloud-sync.service` against the Go backend (architecture §6.4, §17.1)
- gRPC client to `cloud/` using `sensornet.proto`: `RegisterGateway`, `UploadTelemetry` (batch unsynced rows), `CheckCommands`, `ReportCommandResult`, `ReportHealth`. Mark rows `synced=1`; retry/backoff when offline.
- Handle **backend→hub device authorization** from the cloud (a `provision_device` push via `CheckCommands`/config, or a new `ProvisionDevice` RPC) → upsert the authorized device into the registry. Reconcile with locally-provisioned devices.
- **Acceptance:** telemetry from both nodes (ESP32-S3 Wi-Fi + ESP32-S3 CAN) reaches PostgreSQL; offline backlog flushes on reconnect; a cloud-authorized device shows up in the local registry.
- **You learn:** gRPC/TLS, sync state machines, offline buffering at the gateway tier.

### M6 — Provisioning & onboarding (app ↔ hub ↔ backend; see flow doc)
- `dashboard-api` endpoints: `POST /api/gateway/claim` (pairing-code/QR), `POST /api/provisioning/devices` (app→hub on the LAN pre-authorizes a new device + its token), `GET /api/provisioning/pending`. Advertise the hub over **mDNS** (`_greenhouse._tcp`) for app discovery; show a pairing code on the HMI.
- Backend (`cloud/`): mobile-facing API — claim gateway to an account, associate a device, read telemetry/status; then push authorization down to the hub (M5).
- Onboard the **ESP32-S3 CAN node** too: register its fixed `node_id`↔`device_id` via the same path (no Wi-Fi creds — §18.2).
- **Acceptance:** a factory-fresh ESP32 is provisioned from the phone and accepted by the hub via the LAN path *and* re-authorized from the cloud after a hub reset (offline-first + source-of-truth reconcile).
- **You learn:** secure device onboarding, mDNS discovery, LAN-vs-cloud authorization reconciliation, mobile-facing API design.

### M7 — Yocto packaging + systemd + (stretch) RAUC OTA (lower priority; §15, §16)
- Recipes for each service + `.service` units (`Restart=always`, `After=network-online.target`), `can0` via systemd-networkd, SQLite under `/data`. Stretch: RAUC A/B OTA via `meta-rauc`.
- **You learn:** Yocto layers/recipes, systemd service modeling, immutable rootfs + A/B updates.

---

## Cross-cutting
- Keep a **schema/contract doc** in sync with Dev A's JSON and Dev B's CAN frames — you're the consumer of both, so you're the natural keeper of the contract.
- Tests for the decoders and the command-delivery loops.
- A `health-agent` (§6.7) is a nice late add: connected node counts, CAN status, last sync time.

## Definition of done
Both transports (Dev A's ESP32-S3 Wi-Fi + Dev B's ESP32-S3 CAN) land normalized telemetry in
SQLite, commands route to the correct transport and round-trip with results, a local API
serves a transport-neutral device view, and unsynced data reaches PostgreSQL via gRPC —
with the test harness that kept Dev A and Dev B unblocked from day one.

## Interview talking points
- "I built a transport-abstraction gateway: a WebSocket server and a SocketCAN decoder normalizing into one SQLite model."
- "I designed an offline-first sync layer with sync flags and gRPC batch upload + retry, so the gateway works with no cloud."
- "I shipped a multi-process systemd architecture with clean fault isolation between transports."
- "(Stretch) I produced a Yocto image with RAUC A/B OTA."
