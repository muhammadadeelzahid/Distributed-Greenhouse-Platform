# Plan — Developer A: ESP32 Hybrid Node (Wi-Fi/WebSocket + CAN/TWAI)

> **Owner:** Developer A (ESP32) — *you*
> **Folder:** `firmware/esp32-hybrid-node/`
> **Architecture refs:** `docs/architecture.md` §9.1, §9.2, §9.3 (hybrid mode), §10, §11,
> §17, §18.1, §19 (Stages 1–2) + [`provisioning-and-onboarding-flow.md`](provisioning-and-onboarding-flow.md)
> **Mission:** Build a **dual-transport** ESP32 node. **Phase 1:** a Wi-Fi/WebSocket
> sensor path that closes the first end-to-end loop to the cloud, with **mobile-app
> provisioning**. **Phase 2:** add a **CAN/TWAI** path so the ESP32 joins the same
> physical CAN bus as the STM32 and the Pi, then act as a **Wi-Fi↔CAN bridge**. You
> personally master *both* transports, the binary CAN protocol, secure onboarding, and
> protocol-routing — and you put a second vendor's CAN controller (Espressif TWAI) on a
> **multi-vendor bus** alongside ST and Linux.

---

## Why this is a top-tier track for AMD / Qualcomm / NXP / TI

A hybrid, field-provisioned node is exactly the **edge-gateway / connected-device**
pattern these companies ship in automotive and IoT. You'll be able to say, truthfully:

- **Two transports on one MCU**: wireless **Wi-Fi/WebSocket/JSON** *and* wired industrial
  **CAN (TWAI, classic CAN 2.0)** — plus a **bridge** that routes between them.
- **Secure device onboarding**: BLE/SoftAP **Wi-Fi provisioning** (`wifi_provisioning`,
  protocomm, security scheme **sec2**) driven by a companion mobile app — real product onboarding.
- **CAN/TWAI bring-up**: bit timing at 500 kbps, acceptance filters, alerts, **bus-off
  detection + recovery** — the Espressif half of a **3-vendor CAN bus**.
- **Multi-vendor CAN interoperability**: your ESP32 TWAI frames interoperate on the same
  wire with **ST bxCAN** (Dev B's STM32F407) and **Linux SocketCAN** (Dev C) — proof you
  understand CAN at the *protocol* level, not one vendor's SDK.
- **ESP-IDF + FreeRTOS** multi-task design, a **multi-bus sensor suite** (I²C/SPI/1-Wire/ADC),
  **offline-first resilience**, and **(stretch) secure OTA**.

> **CAN FD note:** this whole build is **classic CAN 2.0** — the ESP32 TWAI is classic, and
> Dev B's **STM32F407 bxCAN is classic too** (the F407 has no FDCAN). Knowing classic-CAN vs
> CAN-FD, and that nothing here uses CAN FD, is a credibility signal in interviews.

> **System-level flex:** with this node, the project spans wireless + wired transports,
> three CAN-controller vendors on one bus, RTOS on two ISAs, embedded Linux, and a
> mobile-app onboarding flow — see [`portfolio-and-job-strategy.md`](portfolio-and-job-strategy.md).

---

## Integration contract (you co-own BOTH wire formats now)

This node speaks both transports, so you co-own *both* contracts with Dev B and Dev C:

- **WebSocket JSON** (§10): `register`, `register_ack`, `telemetry`, `heartbeat`,
  `command`, `command_ack`, `command_result`, `error`. Payload keys/units
  (`temperature_c`, `humidity_percent`, `soil_moisture_percent`, …) land verbatim in the
  cloud's `payload_json` (`cloud/proto/sensornet.proto`) — name them once, correctly.
- **CAN frames** (§11): ID layout (`class<<8 | node_id`), per-class byte layouts, scaling,
  `command_sequence`. **Identical to what Dev B's STM32 emits** — that's the point.
- **Provisioning payload** (see the flow doc): what the app hands the device — Wi-Fi creds,
  per-device token, hub address, `device_id`/role.

> **Shared portable C core (build with Dev B):** the vendor-neutral logic — data model,
> the **§11 CAN frame codec**, the **§10 JSON codec**, the command/result state machine,
> CRC/util — goes in one portable C library compiling on **both** your ESP32 (ESP-IDF)
> and the STM32 (ARM). Each MCU adds only a thin platform adapter. You + Dev B sharing one
> codec is how the multi-vendor bus stays in sync — a textbook "portable firmware + HAL boundary" story.

---

## Hardware notes
- **Sensor suite (confirm what you actually have — recommended set for max driver variety):**
  | Signal | Recommended part | Bus / interface — *what you learn* |
  |---|---|---|
  | Air temp + humidity (+ pressure) | BME280 / SHT3x | **I²C** |
  | Soil moisture | capacitive probe | **ADC** (calibrate dry↔wet; capacitive avoids corrosion) |
  | Ambient light | BH1750 | **I²C** (a 2nd I²C device → bus addressing) |
  | Soil/water temp | DS18B20 | **1-Wire** (a whole different protocol — great résumé breadth) |
  | Water/CO₂ (stretch) | float switch / SCD41 | **GPIO interrupt** / **I²C** |
  | Water flow (stretch) | hall flow sensor | **timer pulse-counting / input capture** |

  Hitting I²C **+** ADC **+** 1-Wire **+** GPIO-interrupt **+** timer-capture in one node is a
  strong "I can bring up any peripheral from a datasheet" demonstration.
- **CAN transceiver required** on the ESP32 (SN65HVD230 / TJA1050), same as the STM32. Pick
  two GPIOs for `TWAI_TX`/`TWAI_RX` clear of strapping pins.
- The CAN bus has **three controllers** (ESP32 TWAI, STM32F407 bxCAN, Pi SocketCAN); put
  **120 Ω termination at the two physical ends only**.

---

## Milestones

Each milestone = one mergeable PR with a demo.

## PHASE 1 — Wi-Fi / WebSocket sensor path + provisioning (architecture Stage 1)
*Goal: fastest visible end-to-end win, then make onboarding production-grade.*

### M0 — Project skeleton + shared portable core (design with Dev B)
- ESP-IDF project in `firmware/esp32-hybrid-node/`; FreeRTOS tasks: `wifi_task`,
  `websocket_task`, `sensor_task`, `actuator_task`, `heartbeat_task` (CAN tasks join Phase 2).
- Portable core (shared with Dev B): `device_id`/config in NVS, `telemetry_t`, `command_t`,
  logging, queues (`telemetry_queue`, `command_queue`, `result_queue`).
- **Acceptance:** clean `idf.py build`; tasks start; heartbeat log; CI builds it.
- **You learn:** ESP-IDF layout, components/CMake, FreeRTOS tasks/queues, stack tuning.

### M1 — Sensor suite → `telemetry_queue` (multi-bus)
- Bring up your sensors across **multiple buses** (see the table): I²C climate + light,
  ADC soil moisture (calibrated, filtered), 1-Wire soil temp; flag absent sensors as stale.
- `sensor_task` samples on an interval, packs `telemetry_t`, pushes to `telemetry_queue`.
- **Acceptance:** plausible filtered readings from every connected sensor; no crash if one is missing.
- **You learn:** I²C/SPI/1-Wire/ADC, calibration, filtering, fixed-rate sampling without `delay()`.

### M2 — Wi-Fi station + reconnect (dev creds first)
- `esp_wifi` + `esp_event`; for now read creds from NVS/Kconfig (replaced by real
  provisioning in M7). Event group for `WIFI_CONNECTED`/`WIFI_FAIL`; exponential backoff.
- **Acceptance:** auto-reconnects when the AP toggles; logs RSSI + IP.
- **You learn:** Wi-Fi lifecycle, ESP event loop, event groups.

### M3 — WebSocket connect + register handshake
- `espressif/esp_websocket_client`; send `register` (§10, `transport=websocket`); await `register_ack`. cJSON encode/decode.
- **Acceptance:** clean register/ack against Dev C's test endpoint; bad JSON rejected, not fatal.
- **You learn:** WebSocket client, JSON on a constrained device, handshakes.

### M4 — Telemetry + heartbeat publish
- Drain `telemetry_queue` → `telemetry` frames (exact §10 shape/units); `heartbeat` with uptime/free-heap/RSSI.
- **Acceptance:** stable cadence; no heap leak over a 1-hour soak. **Completes Stage 1 to PostgreSQL** once Dev C's cloud-sync runs.
- **You learn:** producer/consumer decoupling, cadence design, heap-leak hunting.

### M5 — Command path (receive → act → ack → result)
- Inbound `command` → `command_queue` → `actuator_task`; emit `command_ack` then `command_result`; echo `command_id`.
- **Acceptance:** exactly one ack + one result; unknown action → `error`.
- **You learn:** full-duplex command/response, idempotency, protocol → hardware.

### M6 — Resilience: offline buffer + auth (Stage 5, §18.1)
- Bounded ring-buffer of telemetry while offline; flush on reconnect; device token in `register`.
- **Acceptance:** pull the network 2 min → no data lost (within buffer), clean reflush.
- **You learn:** offline-first design, backpressure, lightweight auth.

### M7 — Mobile-app provisioning (Phase 1 capstone; see flow doc)
- Replace dev creds with the **ESP-IDF `wifi_provisioning` manager** over **BLE** (recommended;
  SoftAP fallback), security scheme **sec2** (SRP6a, Proof-of-Possession).
- On first boot (unprovisioned), advertise the provisioning service; the **mobile app** sends
  Wi-Fi SSID/password + per-device **token** + **hub address** (+ `device_id`/role) via
  Espressif's provisioning SDK. Store in NVS; connect; end provisioning; then `register` with the hub.
- Support a **re-provision / factory-reset** path (NVS erase via long-press / a reset command).
- **Acceptance:** a factory-fresh ESP32 is onboarded end-to-end from the phone (no code/flash
  to set creds); it then appears in the hub as an authorized device and streams telemetry.
- **You learn:** BLE GATT provisioning, protocomm, secure onboarding (PoP/sec2), NVS credential
  lifecycle, factory reset — the exact onboarding flow shipped in real connected products.

## PHASE 2 — CAN / TWAI path + bridge (architecture Stage 2 — the job-differentiator)
*Goal: put the ESP32 on the multi-vendor CAN bus and make it a Wi-Fi↔CAN bridge.*

### M8 — TWAI bring-up + loopback self-test
- Init `driver/twai.h` (`twai_general_config_t` with your TX/RX GPIOs, `TWAI_TIMING_CONFIG_500KBITS()`, acceptance filter). Add `can_rx_task`/`can_tx_task`.
- Prove it in **loopback/self-test mode** (no second node); log `twai_get_status_info` + alerts.
- **Acceptance:** stable 500 kbps loopback; filters accept only intended IDs; no error accumulation.
- **You learn:** CAN bit-timing, the TWAI driver state machine, alerts, tx/rx queueing.
- **Cross-vendor moment:** do this alongside Dev B's STM32 M3 and compare the two vendors' CAN APIs.

### M9 — CAN frame codec via the shared portable library + tests
- Use the **shared §11 codec** (the same one Dev B uses) for ESP32 encode/decode. Host unit tests.
- **Acceptance:** lossless round-trip; ESP32 and STM32 emit byte-identical frames for the same input (prove it).
- **You learn:** portable C, bit/byte packing, vendor-neutral protocol design.

### M10 — ESP32 as a CAN node on the real multi-vendor bus
- Send register/heartbeat/telemetry frames over TWAI on the **real bus shared with the STM32 and the Pi**.
- **Acceptance:** Dev C's `candump can0` shows correct ESP32 frames coexisting with STM32 traffic — **multi-vendor CAN interop demonstrably works**.
- **You learn:** real-bus debugging (logic analyzer/scope), arbitration/coexistence, cross-vendor interop.

### M11 — Wi-Fi↔CAN bridge (the headline hybrid feature)
- Route by `device_id`/`transport`: a command arriving over **WebSocket** for a CAN device is
  forwarded onto the **CAN bus** (e.g., to the STM32 pump); CAN telemetry/results surface back up over **WebSocket**.
- Maintain a routing table; preserve `command_id ↔ command_sequence` correlation across the hop.
- **Acceptance:** Dev C sends a Wi-Fi command targeting the STM32 *through* the ESP32 bridge; the STM32 actuates; the result flows back to the cloud.
- **You learn:** protocol gateways/bridging, message routing, cross-transport correlation — a real product pattern.

### M12 — Transport failover + CAN robustness
- If Wi-Fi drops, critical control still flows over CAN (graceful degradation, §12.2). Handle TWAI **bus-off** detection + recovery.
- **Acceptance:** kill Wi-Fi mid-demo → CAN path keeps working; inject a bus fault → node recovers.
- **You learn:** redundancy/failover, CAN error handling, fault injection + recovery.

## PHASE 3 — Stretch (each is a strong résumé line)
- **TLS (`wss://`) + secure OTA** (`esp_https_ota`, A/B `app_update`) — embedded TLS + rollback.
- **TWAI error-passive handling / bus diagnostics**, or **lightweight CAN message auth** (truncated HMAC, §18.2).
- **Power management** (light/deep sleep + wake sources) — relevant to Qualcomm IoT/modem roles.

---

## Cross-cutting (do continuously)
- **Unit tests** (Unity, host or on-target) for the JSON codec, CAN codec, and sensor-scaling math.
- **CI**: GitHub Actions runs `idf.py build` + host codec tests on every PR (repo CI matrix also builds Dev B's STM32 via `arm-none-eabi-gcc`+CMake).
- **README** in `firmware/esp32-hybrid-node/`: full pinout (sensors per bus, TWAI TX/RX + transceiver), bus termination, provisioning + factory-reset steps, build/flash/config.

## Knowledge-share checkpoints (you and Dev B now BOTH do CAN)
- After M8/M9: deep compare with Dev B — **ESP32 TWAI vs STM32F407 bxCAN** (same protocol, two vendors, two ISAs). Gold for interviews.
- Co-debug the multi-vendor bus on a logic analyzer with Dev B and Dev C at M10.
- You own the §10 JSON contract + device-side provisioning; you and Dev B jointly own the §11 CAN contract.

## Definition of done
A dual-transport ESP32 that (1) is **onboarded from a phone** (BLE/sec2 provisioning), (2)
streams a multi-bus sensor suite over WebSocket to the cloud, (3) is a CAN/TWAI node on a
working multi-vendor bus, (4) bridges Wi-Fi↔CAN with correct command/result correlation,
(5) fails over to CAN when Wi-Fi drops and recovers from bus-off — with shared codec, unit tests, CI, and a README.

## Interview talking points (AMD/Qualcomm-tuned)
- "I built a dual-transport edge node and a Wi-Fi↔CAN bridge — the protocol-gateway pattern used in automotive/IoT."
- "I implemented secure BLE provisioning (sec2/PoP) so a factory-fresh device is onboarded from a phone, with a factory-reset path."
- "I put a third CAN controller (Espressif TWAI) on a bus already running ST bxCAN (STM32F407) and Linux SocketCAN, proving cross-vendor interop with byte-identical frames from a shared codec."
- "I handled TWAI bus-off recovery and Wi-Fi→CAN failover for graceful degradation."
- "I brought up sensors across I²C, 1-Wire, ADC, and timer-capture from their datasheets."
