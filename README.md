# Distributed Greenhouse Platform

> **Work in progress.** This monorepo is under active development. Components may be
> incomplete, undocumented, or change without notice.

Monorepo for an offline-capable distributed greenhouse system. It brings together
the cloud service, the Linux gateway image, and ESP32 edge-node firmware:

- **[`cloud/`](cloud/)** — Go gRPC backend (Protobuf, PostgreSQL migrations,
  Dockerfile, Render config); cloud ingest/command service for the gateways.
- **[`yocto/`](yocto/)** — Yocto project for the Raspberry Pi gateway image
  (`meta-device-base` and BSP/dependency layers).
- **[`firmware/`](firmware/)** — ESP32 node firmware (sensors, local control, and
  communication with the gateway).

Build and run instructions live in each component’s README
([cloud](cloud/README.md), [yocto](yocto/README.md), [firmware](firmware/README.md)).
The full target design — transports, gateway services, data flows, and DB schema —
is in **[docs/architecture.md](docs/architecture.md)**.

## Linux gateway (implemented)

The following is implemented today in the Yocto / `meta-device-base` stack (see
[yocto/README.md](yocto/README.md) for build, flash, OTA, and secrets):

- **A/B atomic updates** — two rootfs slots managed by RAUC; U-Boot picks the
  active slot from `BOOT_ORDER` with a three-strike fallback so a bad update
  automatically rolls back.
- **Signed OTA via Eclipse hawkBit** — bundles are signed at build time and
  delivered through a self-hosted hawkBit server using the DDI HTTP API.
- **Immutable rootfs + persistent overlay** — each slot is mounted read-only;
  `/etc`, `/var`, and `/home` use OverlayFS on a dedicated `data` partition so
  state survives updates without compromising the rootfs.
- **systemd-native networking** — `wpa_supplicant@wlan0`, `systemd-networkd`,
  `systemd-resolved`, and `systemd-networkd-wait-online` scoped to `wlan0`.
- **Per-device identity** — hawkBit target name derived from hardware serial on
  each boot.

## Secrets

Local-only credentials for the cloud service are documented in
[`cloud/README.md`](cloud/README.md). Gateway image build secrets, RAUC signing
keys, and the `build-rpi/` setup are documented in [`yocto/README.md`](yocto/README.md).

The root [`.gitignore`](.gitignore) excludes `.env`, `*.secret`, and `*.local`.
