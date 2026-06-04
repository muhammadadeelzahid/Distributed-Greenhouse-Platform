# Distributed Greenhouse Platform

Monorepo for an offline-capable distributed greenhouse system. It brings together
two parts of the product, each kept as its own self-contained project:

- **[`cloud/`](cloud/)** — Go gRPC backend (Protobuf, PostgreSQL migrations,
  Dockerfile, Render config); cloud ingest/command service for the gateways.
- **[`yocto/`](yocto/)** — Self-contained Yocto project for the Raspberry Pi
  gateway image (`meta-device-base` and dependencies): RAUC A/B OTA, Eclipse
  hawkBit, OverlayFS, systemd-networkd, U-Boot.

ESP32 node firmware lives in a separate repository:
<https://github.com/ryanamjad/ESP32-Industrial-IoT-Edge-Node>

Build/run instructions are in each part's own README
([cloud](cloud/README.md), [yocto](yocto/README.md)). The full target design —
transports, gateway services, data flows, and DB schema — is in
**[docs/architecture.md](docs/architecture.md)**.

## Secrets

Local-only credentials for the cloud service are documented in
[`cloud/README.md`](cloud/README.md). Gateway image build secrets, RAUC signing
keys, and the `build-rpi/` setup are documented in [`yocto/README.md`](yocto/README.md).

The root [`.gitignore`](.gitignore) excludes `.env`, `*.secret`, and `*.local`.
