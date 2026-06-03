# Distributed Greenhouse Platform

Monorepo for an offline-capable distributed greenhouse system. It brings together
two parts of the product, each kept as its own self-contained project:

- **[`cloud/`](cloud/)** — Go gRPC backend (Protobuf, PostgreSQL migrations,
  Dockerfile, Render config); cloud ingest/command service for the gateways.
- **[`yocto/meta-device-base/`](yocto/meta-device-base/)** — Yocto layer for the
  Raspberry Pi gateway image: RAUC A/B OTA, Eclipse hawkBit, OverlayFS,
  systemd-networkd, U-Boot.

ESP32 node firmware lives in a separate repository:
<https://github.com/ryanamjad/ESP32-Industrial-IoT-Edge-Node>

Build/run instructions are in each part's own README
([cloud](cloud/README.md), [layer](yocto/meta-device-base/README.md)). The full
target design — transports, gateway services, data flows, and DB schema — is in
**[docs/architecture.md](docs/architecture.md)**.
