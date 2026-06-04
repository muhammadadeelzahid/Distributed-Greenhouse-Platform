# Distributed Greenhouse Platform

> **Work in progress.** This project is under active development. Components may be
> incomplete, undocumented, or change without notice.

Repository for an offline-capable distributed greenhouse system. It brings together
the cloud service, the Linux gateway image, and ESP32 edge-node firmware in one place:

- [**`cloud/`**](cloud/) — Go gRPC backend (Protobuf, PostgreSQL migrations,
Dockerfile, Render config); cloud ingest/command service for the gateways.
- [**`yocto/`**](yocto/) — Yocto project for the Raspberry Pi gateway image
(`meta-device-base` and BSP/dependency layers).
- [**`firmware/`**](firmware/) — ESP32 node firmware (sensors, local control, and
communication with the gateway).

Build and run instructions live in each component’s README  
([cloud](cloud/README.md), [yocto](yocto/README.md), [firmware](firmware/README.md)).  
The full target design — transports, gateway services, data flows, and DB schema —  
is in **[docs/architecture.md](docs/architecture.md)**.

## Secrets

Local-only credentials for the cloud service are documented in [`cloud/README.md`](cloud/README.md). Gateway image build secrets, RAUC signing keys, and the `build-rpi/` setup are documented in [`yocto/README.md`](yocto/README.md). 
