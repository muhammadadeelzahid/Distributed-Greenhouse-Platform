# Embedded Greenhouse Gateway

An offline-capable distributed embedded system. ESP32 sensor/actuator nodes talk
to a Raspberry Pi embedded-Linux gateway over **Wi-Fi/WebSocket** or **CAN bus**;
the gateway runs a local **Qt HMI**, buffers everything in **SQLite**, and syncs
to a **Render** cloud backend over **gRPC/TLS** into **PostgreSQL**.

```
ESP32 nodes
   │   Wi-Fi WebSocket   /   CAN bus
   ▼
Raspberry Pi Gateway   ──   Qt HMI  +  SQLite (local-first)
   │   gRPC over TLS
   ▼
Render Cloud Backend   +   PostgreSQL
```

This is a single monorepo for the whole product. The ESP32 firmware lives in a
companion repository (see [`firmware/`](firmware/)).

## Repository layout

| Path | What it is | Status |
|---|---|---|
| [`cloud/`](cloud/) | Go gRPC backend + Protobuf + PostgreSQL migrations + Dockerfile + Render config | implemented |
| [`yocto/meta-greenhouse/`](yocto/meta-greenhouse/) | Yocto layer: RAUC A/B OTA, hawkBit, OverlayFS, systemd-networkd, U-Boot | implemented |
| [`firmware/`](firmware/) | ESP32 Wi-Fi + CAN node firmware (companion repo) | external |
| [`gateway/`](gateway/) | Raspberry Pi services: websocket/can gateway, dashboard-api, cloud-sync, local-rules, health-agent | design stubs |
| [`hmi/qt-hmi/`](hmi/qt-hmi/) | Front-facing Qt touchscreen application | design stub |
| [`database/`](database/) | Local SQLite schema for the gateway | schema draft |
| [`deployment/`](deployment/) | systemd units + provisioning scripts | reference |
| [`docs/`](docs/architecture.md) | Full architecture document | — |
| [`tests/`](tests/) · [`tools/`](tools/) · [`demo/`](demo/) | Integration tests, dev tools, showcase assets | scaffold |

Full design and data flows: **[docs/architecture.md](docs/architecture.md)**.

## Quickstart

### Cloud backend — [`cloud/`](cloud/)
```bash
cd cloud
go build ./...
DATABASE_URL=postgres://user:pass@host/db PORT=8080 go run ./cmd/server
```
gRPC service is defined in [`cloud/proto/sensornet.proto`](cloud/proto/sensornet.proto);
deployment to Render is configured in [`cloud/render.yaml`](cloud/render.yaml).

### Gateway image — [`yocto/meta-greenhouse/`](yocto/meta-greenhouse/)
A Yocto `scarthgap` layer that builds a flashable Raspberry Pi 4/5 image with
signed RAUC A/B updates delivered via Eclipse hawkBit. Build and flash
instructions are in [its README](yocto/meta-greenhouse/README.md).

### Firmware — [`firmware/`](firmware/)
ESP-IDF firmware in the companion repo:
<https://github.com/ryanamjad/ESP32-Industrial-IoT-Edge-Node>

## Key properties
- **Local-first / offline-capable** — SQLite buffers telemetry and commands; the
  gateway keeps running and automating (via `local-rules`) when the cloud is down.
- **Two device transports** — Wi-Fi/WebSocket for flexible sensor nodes, CAN for
  reliable wired actuators; the HMI and cloud stay transport-neutral.
- **Production-style updates** — RAUC A/B rootfs + hawkBit OTA with automatic rollback.

## Team & workflow

| Area | Owner |
|---|---|
| `gateway/`, `hmi/`, `cloud/`, `database/`, `deployment/`, `yocto/` | Person 1 |
| `firmware/` — esp32-websocket-node | Person 2 |
| `firmware/` — esp32-can-node | Person 3 |

Feature work lands via pull requests into `dev`; stable demos are promoted to `main`.
