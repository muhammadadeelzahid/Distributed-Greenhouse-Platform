# Plan — Developer A: ESP32-S3 Hybrid Node (Wi-Fi/WebSocket + CAN/TWAI bridge)

> **Owner:** Developer A (ESP32-S3) — *you*
> **Folder:** `firmware/esp32s3-hybrid-node/`
> **MCU:** **ESP32-S3** — dual-core Xtensa LX7 @240 MHz, Wi-Fi + **BLE 5.0**, **TWAI**
> (classic CAN 2.0), native **USB-OTG + built-in USB-Serial-JTAG**, PSRAM, vector/SIMD ISA.
> **Architecture refs:** `docs/architecture.md` §9.1, §9.2, §9.3 (hybrid mode), §10, §11,
> §17, §18.1, §19 (Stages 1–2) + [`provisioning-and-onboarding-flow.md`](provisioning-and-onboarding-flow.md)
> **Mission:** Build the **connectivity + sensing** half of the system — a **dual-transport**
> ESP32-S3 node. **Phase 1:** a Wi-Fi/WebSocket sensor path that closes the first end-to-end
> loop to the cloud, with **mobile-app BLE provisioning**. **Phase 2:** add a **CAN/TWAI**
> path so this node joins the same physical CAN bus as **Node B (the ESP32-S3 actuator node)**
> and the Pi, then act as a **Wi-Fi↔CAN bridge**. You personally master *both* transports, the
> binary CAN protocol, secure onboarding, and protocol-routing — owning the wireless/edge-gateway
> half while Node B owns real-time control/safety.

---

## Why this is a top-tier track for AMD / Intel (and any connected-device firmware team)

A hybrid, field-provisioned node is exactly the **edge-gateway / connected-device**
pattern these companies ship in IoT, networking, and industrial. You'll be able to say, truthfully:

- **Two transports on one SoC**: wireless **Wi-Fi/WebSocket/JSON** *and* wired industrial
  **CAN (TWAI, classic CAN 2.0)** — plus a **bridge** that routes between them.
- **Secure device onboarding**: **BLE 5.0 / SoftAP Wi-Fi provisioning** (`wifi_provisioning`,
  protocomm, security scheme **sec2**) driven by a companion mobile app — real product onboarding.
- **CAN/TWAI bring-up**: bit timing at 500 kbps, acceptance filters, alerts, **bus-off
  detection + recovery** — one of two TWAI controllers on a **multi-controller bus**.
- **Multi-controller CAN interoperability**: your TWAI frames interoperate on the same wire with
  **Node B's ESP32-S3 TWAI** and **Linux SocketCAN** (Dev C, typically a Microchip MCP2515 SPI-CAN
  controller — a second CAN-controller vendor), with **byte-identical frames from a shared codec**
  — proof you understand CAN at the *protocol* level, plus **cross-stack RTOS↔Linux interop**.
- **ESP-IDF + dual-core FreeRTOS** multi-task design, a **multi-bus sensor suite** (I²C/1-Wire/ADC),
  **native USB** (USB-Serial-JTAG debug; optional USB-CDC console), **offline-first resilience**,
  and **(stretch) secure OTA + on-device anomaly detection on the S3 vector/SIMD ISA**.

> **CAN FD note:** this whole build is **classic CAN 2.0** — the ESP32-S3 TWAI is classic, and so
> is Node B's. Knowing classic-CAN vs CAN-FD, and that nothing here uses CAN FD, is a credibility
> signal in interviews.

> **System-level flex:** the project spans wireless + wired transports, a **multi-controller CAN
> bus** with **cross-stack RTOS↔Linux interop**, **heterogeneous compute inside the SoC** (this
> node's dual Xtensa LX7 cores; Node B adds a **RISC-V ULP** coprocessor → two ISAs on one chip),
> embedded Linux, gRPC to the cloud, and a mobile-app onboarding flow — see
> [`portfolio-and-job-strategy.md`](portfolio-and-job-strategy.md).

---

## Integration contract (you co-own BOTH wire formats now)

This node speaks both transports, so you co-own *both* contracts with Dev B and Dev C:

- **WebSocket JSON** (§10): `register`, `register_ack`, `telemetry`, `heartbeat`,
  `command`, `command_ack`, `command_result`, `error`. Payload keys/units
  (`temperature_c`, `humidity_percent`, `soil_moisture_percent`, …) land verbatim in the
  cloud's `payload_json` (`cloud/proto/sensornet.proto`) — name them once, correctly.
- **CAN frames** (§11): ID layout (`class<<8 | node_id`), per-class byte layouts, scaling,
  `command_sequence`. **Identical to what Node B's ESP32-S3 emits** — that's the point.
- **Provisioning payload** (see the flow doc): what the app hands the device — Wi-Fi creds,
  per-device token, hub address, `device_id`/role.

> **Shared portable C core (build with Dev B):** the vendor-neutral logic — data model,
> the **§11 CAN frame codec**, the **§10 JSON codec**, the command/result state machine,
> CRC/util — goes in one portable C library compiling on **both** ESP32-S3 nodes (and, as a
> Node-B stretch, on its **RISC-V ULP** target too). Each node adds only a thin platform adapter.
> You + Dev B sharing one codec is how the multi-controller bus stays byte-for-byte in sync — a
> textbook "portable firmware + HAL boundary" story.

---

## Hardware notes
- **Sensor suite (the 3 sensors actually used in this build — chosen for maximum *interface*
  variety, which is what proves "I can bring up any peripheral"):**
  | Signal | Part (on hand) | Bus / interface — *what you learn* |
  |---|---|---|
  | Air temp + pressure | **GY-BMP280** | **I²C** — register-level driver from the datasheet (chip ID, calibration coefficients, oversampling, compensation formula) |
  | Air temp + humidity | **DHT11** | **single-wire timing protocol** — bit-banged, microsecond-accurate start pulse + 40-bit read with a checksum (no vendor SDK hiding the timing) |
  | Soil moisture | **resistive soil module** | **ADC** — raw counts → calibrated %, dry↔wet two-point calibration, moving-average filtering, ADC1 + attenuation |

  Three sensors, **three completely different driver styles** — I²C register map, a
  timing-critical single-wire protocol, and an analog ADC front-end. That's a stronger
  "datasheet bring-up" story than three sensors on the same bus.

  > **Wiring/board notes (ESP32-S3 — the GPIO matrix lets you route I²C/peripherals to almost any free GPIO):**
  > - **BMP280** on I²C: route `SDA`/`SCL` to any free GPIOs (DevKitC-1 commonly uses `GPIO8`/`GPIO9`), 3.3 V (most GY-BMP280 boards default to addr `0x76`).
  > - **DHT11** on a single GPIO (e.g. `GPIO4`); add a 4.7k–10k pull-up on DATA if the module board doesn't already include one.
  > - **Soil moisture** AOUT on an **ADC1** channel (**`GPIO1`–`GPIO10`** on the S3) — ADC1 only, because **ADC2 is unavailable while Wi-Fi is on**. Don't leave a resistive probe powered 24/7 (corrosion); power it from a GPIO and energize only around sampling if you want to be thorough.
  > - Avoid the strapping pins (`GPIO0`, `GPIO45`, `GPIO46`) and the USB-JTAG pins (`GPIO19`/`GPIO20`) for sensors.
  > - **Stale-flagging:** if a sensor read fails (I²C NACK, DHT checksum mismatch, ADC out of range), mark that field stale instead of crashing.

  > **Stretch sensors (from the same kit — add only *after* M4 streams to the cloud):**
  > PIR (`SR501`) → GPIO interrupt · HC-SR04 → timer/echo pulse timing · SW-420 vibration →
  > debounced interrupt · KY-003 Hall → digital edge counting. Each adds a distinct résumé line
  > (interrupts, input-capture/timing) without changing the core 3-sensor design.
- **CAN transceiver required** on the ESP32-S3 (SN65HVD230 / TJA1050), same as Node B. Pick
  two GPIOs for `TWAI_TX`/`TWAI_RX` clear of the strapping/USB-JTAG pins.
- The CAN bus has **three controllers** (this node's TWAI, Node B's TWAI, Pi SocketCAN —
  typically a Microchip MCP2515 hat); put **120 Ω termination at the two physical ends only**.

---

## Milestones

Each milestone = one mergeable PR with a demo.

## PHASE 1 — Wi-Fi / WebSocket sensor path + provisioning (architecture Stage 1)
*Goal: fastest visible end-to-end win, then make onboarding production-grade.*

### M0 — Project skeleton + shared portable core (design with Dev B)
- ESP-IDF project in `firmware/esp32s3-hybrid-node/`; dual-core FreeRTOS (SMP) tasks: `wifi_task`,
  `websocket_task`, `sensor_task`, `actuator_task`, `heartbeat_task` (CAN tasks join Phase 2).
- Portable core (shared with Dev B): `device_id`/config in NVS, `telemetry_t`, `command_t`,
  logging, queues (`telemetry_queue`, `command_queue`, `result_queue`).
- **Acceptance:** clean `idf.py build`; tasks start; heartbeat log; CI builds it.
- **You learn:** ESP-IDF layout, components/CMake, FreeRTOS tasks/queues, stack tuning.

### M1 — Sensor suite → `telemetry_queue` (multi-bus: I²C + single-wire + ADC)
- Bring up the **three sensors**, each a different driver style (see the hardware table):
  1. **BMP280 over I²C** — write a small driver: read the chip-ID register, read the factory
     calibration coefficients, configure oversampling, do a measurement, apply the
     compensation formula to get `temperature_c` and `pressure_hpa`. Keys land verbatim in the
     §10 telemetry payload.
  2. **DHT11 over a single GPIO** — bit-bang the start pulse, read the 40-bit response with
     precise timing, verify the checksum; produce `humidity_percent` (and a cross-check temp).
  3. **Soil moisture over ADC1** — sample raw counts, apply dry↔wet two-point calibration to a
     `soil_moisture_percent`, smooth with a moving average.
- `sensor_task` samples on a fixed interval (no blocking `delay()` spin), packs `telemetry_t`,
  pushes to `telemetry_queue`. On read failure (I²C NACK / DHT checksum fail / ADC out of range),
  flag that field **stale** rather than crashing.
- **Acceptance:** plausible, filtered readings from all three sensors; breathe on the DHT11 and
  humidity rises; touch a wet cloth to the soil probe and the % rises; unplug any one sensor and
  the node keeps running with that field marked stale.
- **You learn:** I²C register-map bring-up + sensor compensation math, a timing-critical
  single-wire protocol, ADC calibration/filtering, and fixed-rate sampling without `delay()`.

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
*Goal: put this node on the multi-controller CAN bus and make it a Wi-Fi↔CAN bridge.*

### M8 — TWAI bring-up + loopback self-test
- Init `driver/twai.h` (`twai_general_config_t` with your TX/RX GPIOs, `TWAI_TIMING_CONFIG_500KBITS()`, acceptance filter). Add `can_rx_task`/`can_tx_task`.
- Prove it in **loopback/self-test mode** (no second node); log `twai_get_status_info` + alerts.
- **Acceptance:** stable 500 kbps loopback; filters accept only intended IDs; no error accumulation.
- **You learn:** CAN bit-timing, the TWAI driver state machine, alerts, tx/rx queueing.
- **Cross-node moment:** do this alongside Node B's TWAI bring-up (M4) and compare how each of you
  configured the *same* controller for the *same* bus — then trade notes on Node B's register-level approach.

### M9 — CAN frame codec via the shared portable library + tests
- Use the **shared §11 codec** (the same one Dev B uses) for ESP32-S3 encode/decode. Host unit tests.
- **Acceptance:** lossless round-trip; **both ESP32-S3 nodes emit byte-identical frames** for the same input (prove it).
- **You learn:** portable C, bit/byte packing, vendor-neutral protocol design.

### M10 — ESP32-S3 as a CAN node on the real multi-controller bus
- Send register/heartbeat/telemetry frames over TWAI on the **real bus shared with Node B and the Pi**.
- **Acceptance:** Dev C's `candump can0` shows correct frames from this node coexisting with Node B's TWAI traffic — **multi-controller CAN interop demonstrably works**.
- **You learn:** real-bus debugging (logic analyzer/scope), arbitration/coexistence, cross-stack (RTOS↔Linux) interop.

### M11 — Wi-Fi↔CAN bridge (the headline hybrid feature)
- Route by `device_id`/`transport`: a command arriving over **WebSocket** for a CAN device is
  forwarded onto the **CAN bus** (e.g., to Node B's pump); CAN telemetry/results surface back up over **WebSocket**.
- Maintain a routing table; preserve `command_id ↔ command_sequence` correlation across the hop.
- **Acceptance:** Dev C sends a Wi-Fi command targeting Node B *through* this bridge; Node B actuates; the result flows back to the cloud.
- **You learn:** protocol gateways/bridging, message routing, cross-transport correlation — a real product pattern.

### M12 — Transport failover + CAN robustness
- If Wi-Fi drops, critical control still flows over CAN (graceful degradation, §12.2). Handle TWAI **bus-off** detection + recovery.
- **Acceptance:** kill Wi-Fi mid-demo → CAN path keeps working; inject a bus fault → node recovers.
- **You learn:** redundancy/failover, CAN error handling, fault injection + recovery.

## PHASE 3 — Stretch (each is a strong résumé line)
- **TLS (`wss://`) + secure OTA** (`esp_https_ota`, A/B `app_update`) — embedded TLS + rollback.
- **On-device anomaly detection on the S3 vector/SIMD ("AI") ISA** (ESP-DSP / ESP-DL/ESP-NN):
  flag abnormal sensor patterns locally before they reach the cloud — an **edge-AI + performance**
  story Intel (OpenVINO/edge) and AMD (AI engines) screen for directly.
- **Native USB**: a **USB-CDC** debug/config console or **USB DFU** firmware update over the S3's USB-OTG.
- **TWAI error-passive handling / bus diagnostics**, or **lightweight CAN message auth** (truncated HMAC, §18.2).
- **Power management** (light/deep sleep + wake sources) — relevant to IoT/edge roles at both companies.

---

## Cross-cutting (do continuously)
- **Unit tests** (Unity, host or on-target) for the JSON codec, CAN codec, and sensor-scaling math.
- **CI**: GitHub Actions runs `idf.py build` + host codec tests on every PR (repo CI matrix builds *both* ESP32-S3 nodes and runs the shared host codec tests).
- **README** in `firmware/esp32s3-hybrid-node/`: full pinout (sensors per bus, TWAI TX/RX + transceiver), bus termination, provisioning + factory-reset steps, USB-JTAG debug, build/flash/config.

## Knowledge-share checkpoints (you and Dev B split connectivity vs control)
- After M8/M9: deep compare with Dev B — you explain **Wi-Fi/WebSocket/JSON + BLE provisioning + the bridge**; Dev B explains **register-level peripherals + dual-core affinity + the RISC-V ULP**. Same chip family, two very different masteries — gold for interviews.
- Co-debug the multi-controller bus on a logic analyzer with Dev B and Dev C at M10.
- You own the §10 JSON contract + device-side provisioning; you and Dev B jointly own the §11 CAN contract + shared codec.

## Definition of done
A dual-transport ESP32-S3 that (1) is **onboarded from a phone** (BLE/sec2 provisioning), (2)
streams a multi-bus sensor suite over WebSocket to the cloud, (3) is a CAN/TWAI node on a
working multi-controller bus, (4) bridges Wi-Fi↔CAN with correct command/result correlation,
(5) fails over to CAN when Wi-Fi drops and recovers from bus-off — with shared codec, unit tests, CI, and a README.

## Interview talking points (AMD/Intel-tuned)
- "I built a dual-transport edge node and a Wi-Fi↔CAN bridge — the protocol-gateway pattern used in IoT/industrial."
- "I implemented secure BLE provisioning (sec2/PoP) so a factory-fresh device is onboarded from a phone, with a factory-reset path."
- "I put my TWAI controller on a multi-controller CAN bus alongside a second TWAI node and Linux SocketCAN (a Microchip MCP2515), proving cross-stack RTOS↔Linux interop with byte-identical frames from a shared codec."
- "I handled TWAI bus-off recovery and Wi-Fi→CAN failover for graceful degradation."
- "I brought up three sensors with three different driver styles from their datasheets — a register-level I²C driver (BMP280, including the calibration/compensation math), a timing-critical bit-banged single-wire protocol (DHT11), and a calibrated/filtered ADC analog front-end (soil moisture)."
- "(Stretch) I ran on-device anomaly detection on the ESP32-S3's vector/SIMD instructions — edge AI at the sensor, not in the cloud."
