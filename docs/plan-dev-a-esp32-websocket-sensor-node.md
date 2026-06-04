# Plan — Developer A: ESP32 Wi-Fi / WebSocket Sensor Node

> **Owner:** Developer A (ESP32)
> **Folder:** `firmware/esp32-websocket-node/`
> **Architecture refs:** `docs/architecture.md` §9.1, §10, §17.1, §18.1, §19 (Stage 1)
> **Mission:** Build the Wi-Fi sensor node that reads climate + soil sensors and
> streams JSON telemetry to the gateway over a WebSocket — with real reconnect,
> offline buffering, and command handling. This is the node that closes the
> *first end-to-end loop* (ESP32 → WebSocket → Pi → SQLite → cloud).

---

## Why this track (resume / interview value)

You will be able to say, truthfully, that you built embedded firmware that does:

- **ESP-IDF + FreeRTOS** multi-task design with queues and event groups (not Arduino `loop()`).
- **Wi-Fi station lifecycle**: connect, disconnect events, auto-reconnect with backoff.
- **A real application-layer protocol** over WebSocket: register → telemetry → heartbeat → command → ack → result.
- **Sensor acquisition**: I²C climate sensor + ADC soil-moisture, with calibration and filtering.
- **Resilience**: offline ring-buffer, resend-on-reconnect, watchdog, NVS-stored config/credentials.
- **(Stretch) Secure OTA** with `esp_https_ota` and A/B partitions.

These are the bullet points hiring managers for embedded/IoT roles actually look for.

---

## Integration contract (co-own with Dev B and Dev C)

Before writing protocol code, agree on the **wire formats** with the team and pin
them in a shared doc/PR. These are the seams between the three of you.

- **JSON message shapes** (architecture §10): `register`, `register_ack`, `telemetry`,
  `heartbeat`, `command`, `command_ack`, `command_result`, `error`.
- **`device_id` naming**: e.g. `climate-node-001`, `soil-node-001`.
- **`payload` keys & units**: `temperature_c`, `humidity_percent`, `soil_moisture_percent` — these land verbatim in the cloud's `payload_json` (see `cloud/proto/sensornet.proto`), so name them once, correctly.
- **Device token** string format (for §18.1 auth).
- **WebSocket URL** the gateway exposes (Dev C provides a test endpoint — see Dev C M0).

> Tip: factor everything transport-neutral (device identity, config, the telemetry
> struct, the command struct, NVS helpers, logging) into a **shared `node_core`
> component** that both you and Dev B reuse. Build this together in M0. It is the
> single highest-leverage thing you can do for both learning and integration.

---

## Milestones

Each milestone = one mergeable PR with a demo. Aligns with architecture Stage 1 → 5.

### M0 — Project skeleton + shared `node_core` (pair with Dev B)
- Create the ESP-IDF project in `firmware/esp32-websocket-node/` (`idf.py create-project`, `set-target esp32`).
- Stand up the FreeRTOS task/queue skeleton from §9.1:
  `wifi_task`, `websocket_task`, `sensor_task`, `actuator_task`, `heartbeat_task`.
- Define the shared `node_core` component: `device_id`/config in NVS, a `telemetry_t`
  struct, a `command_t` struct, logging tags, and the inter-task **queues**
  (`telemetry_queue`, `command_queue`, `result_queue`).
- **Deliverable:** boots, all tasks start, a heartbeat log prints every N seconds.
- **Acceptance:** `idf.py build` clean; tasks visible in `vTaskList`/logs; CI builds the project (see Cross-cutting).
- **You learn:** ESP-IDF project layout, components, CMake, FreeRTOS task creation, queue handles, stack-size tuning.

### M1 — Sensor drivers → `telemetry_queue`
- Climate sensor over **I²C** (new `driver/i2c_master.h` API) on your real BME280/SHT3x —
  scope/logic-analyze the bus if readings look off. (Wokwi/sim is the CI fallback only.)
- Soil moisture over **ADC** (`esp_adc/adc_oneshot`): calibrate against your actual probe
  (dry-air vs water-submerged endpoints) → percent, with a moving-average filter.
- `sensor_task` reads on an interval, packs a `telemetry_t`, pushes to `telemetry_queue`.
- **Deliverable:** live sensor values in the serial monitor.
- **Acceptance:** plausible, filtered readings; graceful handling when a sensor is absent (no crash, flagged as stale).
- **You learn:** I²C transactions, ADC calibration, sensor fusion/filtering, fixed-rate sampling without `delay()`.

### M2 — Wi-Fi station + reconnect
- `wifi_task` using `esp_wifi` + `esp_event`; credentials from NVS (not hardcoded — see §18.1).
- Use a FreeRTOS **event group** for `WIFI_CONNECTED` / `WIFI_FAIL`; exponential backoff on disconnect.
- **Deliverable:** node connects, survives the AP being toggled off/on.
- **Acceptance:** auto-reconnects within backoff window; logs RSSI + IP.
- **You learn:** Wi-Fi driver lifecycle, the ESP event loop, event groups, why credentials live in NVS.

### M3 — WebSocket connect + register handshake
- Add `espressif/esp_websocket_client` via the component manager.
- On connect, send `register` (§10) with `device_type=esp32_sensor`, `transport=websocket`,
  `capabilities`, `firmware_version`; wait for `register_ack`.
- JSON encode/decode with **cJSON**.
- **Deliverable:** node registers against Dev C's test WebSocket endpoint and gets acked.
- **Acceptance:** clean register/ack round-trip; malformed inbound JSON is rejected, not fatal.
- **You learn:** WebSocket client API, JSON (de)serialization on a constrained device, protocol handshakes.

### M4 — Telemetry + heartbeat publish
- `websocket_task` drains `telemetry_queue` → emits `telemetry` frames (exact §10 shape, correct units).
- `heartbeat_task` emits `heartbeat` on an interval (include uptime, free heap, RSSI).
- **Deliverable:** continuous telemetry visible on Dev C's gateway/SQLite; this **completes Stage 1 end-to-end** once Dev C's cloud-sync runs.
- **Acceptance:** stable cadence, no heap leak over a 1-hour soak (watch `esp_get_free_heap_size`).
- **You learn:** producer/consumer decoupling via queues, message cadence design, heap-leak hunting.

### M5 — Command path (receive → act → ack → result)
- Inbound `command` → `command_queue` → `actuator_task` (drive at minimum the onboard LED, or a relay if you have one).
- Emit `command_ack` immediately, then `command_result` after execution; echo `command_id`.
- **Deliverable:** Dev C (or the test harness) sends a command; node acks, acts, reports result.
- **Acceptance:** every command produces exactly one ack + one result; unknown actions return an `error`.
- **You learn:** full-duplex command/response state, idempotency, mapping protocol → hardware action.

### M6 — Resilience: offline buffer + auth (architecture Stage 5, §18.1)
- Ring-buffer telemetry while the socket is down; flush on reconnect (bounded — drop oldest when full).
- Send the **device token** in `register`; gateway rejects unknown IDs.
- **Deliverable:** pull the network for 2 min during a demo → no data lost (within buffer), auto-flushes on reconnect.
- **Acceptance:** bounded memory; no duplicate or out-of-order chaos after reconnect.
- **You learn:** offline-first design, backpressure, lightweight auth, the tradeoffs of buffer sizing.

### M7 — Stretch: TLS + OTA
- Upgrade to `wss://` (TLS); then add `esp_https_ota` with A/B `app_update` partitions and an `ota_task` (§9.1).
- **You learn:** embedded TLS, partition tables, robust field-update strategy + rollback — strong senior-level talking points.

---

## Cross-cutting (do continuously)

- **Unit tests** for the codec (JSON encode/decode) and sensor-scaling math with **Unity** (host or on-target).
- **CI**: a GitHub Actions job that runs `idf.py build` for this node on every PR (Dev C can share one workflow across both nodes).
- **README** in `firmware/esp32-websocket-node/` documenting pinout, build, flash, and config.

## Knowledge-share checkpoints (so both ESP32 devs learn both transports)
- After M3: 30-min walkthrough swapping with Dev B — you explain WebSocket/JSON, they explain TWAI/CAN frames.
- Code-review each other's M5 command paths (the logic is parallel; the transport differs).
- Stretch swap: implement one small frame in the *other* node so you've each touched both stacks.

## Definition of done
ESP32 sensor node registers, streams correct telemetry, handles commands with ack+result,
survives Wi-Fi/cloud outages via buffering, authenticates with a token, has codec unit
tests and CI, and a documented README. Stage-1 loop demonstrably reaches PostgreSQL.

## Interview talking points
- "I designed a FreeRTOS task/queue pipeline so sensor sampling, networking, and actuation never block each other."
- "I implemented offline-first buffering with bounded resend, so a Wi-Fi drop doesn't lose telemetry."
- "I built a JSON application protocol with register/ack/command/result semantics and idempotent command handling."
- "(Stretch) I shipped secure OTA over TLS with A/B partitions and rollback."
