# Provisioning & Onboarding Flow (Mobile App → Hub → Backend → Pi)

> Adds a **companion mobile app** and a production-style **onboarding flow** to the
> greenhouse platform. This is the "how does a brand-new device safely join the system"
> story — a high-value, end-to-end IoT capability that ties the firmware, the gateway,
> the cloud, and a phone together.
>
> Architecture context: `docs/architecture.md` §7 (transport/registry), §18 (security),
> §6.3 (`dashboard-api`), §6.4 (`cloud-sync`), and `cloud/proto/sensornet.proto`.

---

## Components & who owns what

| Component | Role in onboarding | Owner |
|---|---|---|
| **Mobile app** (companion, **Flutter**) | Log in, claim the hub, provision devices, show status | **Dev A (you)** — see [§ Mobile app](#mobile-app-workstream) |
| **ESP32 hybrid node** | Receives Wi-Fi creds + token + hub address over BLE/SoftAP; registers | Dev A |
| **ESP32-S3 CAN node** | Onboarded by registering its fixed `node_id`↔`device_id` in the hub (no Wi-Fi creds) | Dev B + Dev C |
| **Raspberry Pi hub** (`dashboard-api`, `cloud-sync`) | Accepts "device provisioned" from the app (LAN) and authorization from the cloud (gRPC) | Dev C |
| **Cloud backend** (Render) | Mobile-facing API (auth, claim, associate device); pushes authorization to the Pi | Dev C |

---

## Two-stage onboarding

### Stage A — Claim the hub to a user account (once per gateway)
```
 Mobile app                Backend (cloud)            Raspberry Pi hub
    |  login (HTTPS/OAuth)     |                            |
    |------------------------->|                            |
    |  claim gateway G         |                            |
    |  (scan QR / serial, or   |                            |
    |   mDNS-discover + enter  |                            |
    |   pairing code from HMI) |                            |
    |------------------------->|  record owner(A,G),        |
    |                          |  mint gateway token        |
    |                          |---- gRPC RegisterGateway-->|  store identity + token,
    |                          |     / config push          |  bind hub to account A
    |   "hub claimed" <--------|<---------------------------|
```
Result: the hub is bound to the user's account and trusts the backend over gRPC/TLS.

### Stage B — Provision a new ESP32 node (per device)
```
 ESP32 (unprovisioned)     Mobile app            Pi hub (dashboard-api)   Backend (cloud)
   | BLE advertise prov svc   |                        |                       |
   |<--- discover + connect --|                        |                       |
   |<--- sec2 handshake (PoP)-|                        |                       |
   |<--- Wi-Fi SSID/pass,     |                        |                       |
   |     device token,        |                        |                       |
   |     hub address,         |                        |                       |
   |     device_id/role ------|                        |                       |
   | store NVS, join Wi-Fi    |                        |                       |
   | end provisioning         |                        |                       |
   |                          | (1) POST /api/provisioning/devices            |
   |                          |     {device_id, token, caps}  (LAN)           |
   |                          |----------------------->| pre-authorize device  |
   |                          |                        | in devices table      |
   |                          | (2) associate device with account (HTTPS)     |
   |                          |---------------------------------------------->| store + authorize
   |                          |                        |  (3) gRPC CheckCommands / config:
   |                          |                        |<---- "provision_device"-------|
   |                          |                        |  apply authorization  |
   | register (WebSocket, token) ------------------->  | token matches → accept|
   | telemetry flows ...      |                        |                       |
```

**Why both (1) local and (3) cloud paths?** Path (1) lets onboarding work **on the LAN even
if the cloud is down** (offline-first, matches §12). Path (3) keeps the cloud the **source
of truth** and re-syncs the hub after any reset. The hub accepts the device when *either*
path has authorized its token — and reconciles the two. That redundancy is the realistic,
interview-worthy design choice.

---

## Security (maps to architecture §18)
- **BLE/SoftAP provisioning:** ESP-IDF `wifi_provisioning` + protocomm, **security scheme
  sec2** (SRP6a) with a per-device **Proof-of-Possession**; never ship sec0 (plaintext) in production.
- **Per-device token** handed at provisioning time → used in the WebSocket `register` (§18.1);
  the hub rejects unknown/unauthorized device IDs.
- **App ↔ backend:** HTTPS + account auth (OAuth/JWT). **App ↔ hub (LAN):** the hub binds
  `dashboard-api` to the LAN and authenticates the app with the gateway/account token.
- **Backend ↔ hub:** gRPC over TLS with the gateway token (§18.4); mTLS later.
- **Factory reset / re-provision:** long-press or a `factory_reset` command erases NVS creds
  and returns the device to provisioning mode.

---

## Proto / API additions (for Dev C)
- **`cloud/proto/sensornet.proto`** — add an authorization push. Either a dedicated RPC
  `ProvisionDevice(gateway_id, device_id, token, capabilities_json)` **or** reuse
  `CheckCommands` with a `CloudCommand` whose `payload_json` is `{"type":"provision_device", …}`.
- **`dashboard-api`** — `POST /api/provisioning/devices` (app→hub, LAN), `POST /api/gateway/claim`
  (pairing-code/QR), `GET /api/provisioning/pending` (app shows onboarding status). mDNS/`_greenhouse._tcp` advertisement for app discovery.
- **Backend mobile API** — `POST /v1/account/gateways` (claim), `POST /v1/gateways/{g}/devices` (associate), device/telemetry read endpoints for the app dashboard.

---

## Mobile app workstream
**Owned by you (Dev A), in Flutter** — a single cross-platform (iOS + Android) codebase that
showcases full-stack IoT range alongside your firmware work.
- **Stack:** Flutter + Dart. For the BLE provisioning step, **don't hand-roll the GATT
  protocol** — use a Flutter plugin that wraps Espressif's native provisioning SDK
  (e.g. `flutter_esp_ble_prov`), or write a thin **platform channel** to the official
  `esp-idf-provisioning-android` / `-ios` SDKs. Networking to the backend/hub via `dio`/`http`.
- **Screens:** login → claim hub (QR/mDNS + pairing code) → "add device" (BLE scan → sec2 PoP
  → send Wi-Fi creds + token + hub address) → device list / live telemetry (from backend or
  hub) → re-provision / factory-reset / remove.
- **Ties to your firmware:** the app is the *client* for the ESP32 provisioning you build in
  Dev A **M7** — build them together so you can demo the full onboarding loop end-to-end.

**Mobile app milestones**
- **MA0** — App skeleton + login against the backend (HTTPS/JWT).
- **MA1** — Claim the hub (QR/serial or mDNS discovery + pairing code on the HMI) → backend.
- **MA2** — BLE provisioning of an ESP32 via the Espressif provisioning plugin/SDK (sec2/PoP): send Wi-Fi creds + token + hub address. Pairs with Dev A firmware M7.
- **MA3** — Notify the hub (LAN `POST /api/provisioning/devices`) **and** the backend (associate device).
- **MA4** — Device dashboard: live telemetry + status; re-provision / factory-reset trigger.

> **Sequencing:** since you own both the ESP32 firmware *and* the Flutter app, build MA2
> together with firmware **M7** — that's the moment the whole onboarding loop becomes demoable
> (and a great clip for the portfolio video). MA0/MA1 can start anytime; MA4 comes once
> telemetry is flowing (after Phase 1).

---

## How this strengthens the portfolio (AMD/Intel)
- Demonstrates **secure device onboarding** end-to-end — the single most common "real product"
  gap in student/portfolio projects.
- Shows **offline-first + cloud-source-of-truth reconciliation**, a genuine distributed-systems design.
- Adds BLE + a companion app to a story that already spans CAN, Wi-Fi, RTOS on a heterogeneous edge (Xtensa LX7 cores + a RISC-V ULP coprocessor — two ISAs), and embedded Linux.
