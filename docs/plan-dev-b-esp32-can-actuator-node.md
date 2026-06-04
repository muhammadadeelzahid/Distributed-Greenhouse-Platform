# Plan — Developer B: ESP32 CAN (TWAI) Actuator Node

> **Owner:** Developer B (ESP32)
> **Folder:** `firmware/esp32-can-node/`
> **Architecture refs:** `docs/architecture.md` §9.2, §11, §12.2, §17.2/§17.4, §18.2, §19 (Stage 2)
> **Mission:** Build the wired, deterministic actuator node (pump / fan / relay) that
> talks to the gateway over the **CAN bus via the ESP32 TWAI controller**, packs
> compact binary frames, and **keeps the greenhouse safe even when the gateway is
> offline**. This is the "industrial / automotive-flavored" half of the project.

---

## Why this track (resume / interview value)

CAN is what separates "I blinked an LED" from "I can work on automotive/industrial
embedded systems." You'll be able to say you built:

- **ESP32 TWAI (CAN 2.0)** driver bring-up at 500 kbps, with bus-off detection and recovery.
- **A binary protocol** with an 11-bit CAN ID scheme (message class + node id) and byte-packed payloads — no JSON, real bit/byte work.
- **Deterministic actuator control**: relays (GPIO) and fan (PWM/LEDC) with safe default states.
- **Local safety logic** that runs autonomously when the network is down (fail-safe state machine, command timeouts, max-runtime guards) — the single most *interview-quotable* feature in this project.
- **Robustness**: command sequence numbers, dedup, error frames, watchdogs.

Automotive, robotics, and industrial-controls teams specifically interview for CAN +
fail-safe design. This track targets exactly those roles.

---

## Integration contract (co-own with Dev A and Dev C)

Pin these with the team before coding the protocol — they are the seam between the
ESP32 node and Dev C's `can-gateway.service`:

- **CAN ID layout** (architecture §11): bits `10..8` = message class, `7..0` = `node_id`.
  Classes: `0x100` register, `0x200` heartbeat, `0x300` telemetry, `0x400` command,
  `0x500` ack, `0x600` result, `0x700` error.
- **Node IDs**: e.g. `relay-node-001 = 0x21`, `pump-node-001 = 0x22`, `fan-node-001 = 0x23`.
- **Byte layouts** of each frame (§11.1–§11.5): heartbeat, telemetry, command, ack, result. Agree on scaling factors (e.g. `temperature_c = byte/2`) and `command_type`/`target`/`value` enums.
- **Bus speed**: 500 kbps. **Command sequence** semantics for ack/result matching.

> Reuse the **shared `node_core` component** built with Dev A (device identity,
> config in NVS, the `command_t`/`telemetry_t` structs, the inter-task queues,
> logging). Only the *transport* and *serialization* differ between your node and
> Dev A's — keep everything else common so you both learn the shared core.

---

## Hardware note
The ESP32 has an internal TWAI controller but needs an **external CAN transceiver**
(SN65HVD230 / TJA1050 / MCP2551) — wire it up and target a **real bus** from the start.
Remember the bus needs **120 Ω termination at both ends**; mind the transceiver's 3.3 V
vs 5 V logic level on the ESP32 TX/RX pins. Pair early with Dev C's SocketCAN side
(MCP2515 HAT or USB-CAN) so you're decoding against a real peer.
**TWAI loopback/self-test mode** (the controller receives its own frames) stays useful
for *initial bring-up before wiring* and for **CI** — but it's the fallback, not the
default dev path now that you have transceivers.

---

## Milestones

Each milestone = one mergeable PR with a demo. Aligns with architecture Stage 2.

### M0 — Project skeleton + shared `node_core` (pair with Dev A)
- Create the ESP-IDF project in `firmware/esp32-can-node/`; FreeRTOS tasks from §9.2:
  `can_rx_task`, `can_tx_task`, `sensor_task`, `actuator_task`, `heartbeat_task`, `local_safety_task`.
- Wire up `telemetry_queue`, `command_queue`, `result_queue` from `node_core`.
- **Deliverable:** boots, tasks run, heartbeat tick logs.
- **Acceptance:** clean build; CI builds the project.
- **You learn:** ESP-IDF/FreeRTOS structure, the shared-component pattern.

### M1 — Actuator drivers with safe defaults
- Relay channels via **GPIO**; fan speed via **LEDC PWM**. Define and enforce a **safe
  default state** (pump OFF, fan as configured) on boot and on fault.
- `actuator_task` consumes `command_t` from `command_queue` and drives hardware.
- **Deliverable:** commands (faked locally for now) toggle relay/fan; boot state is safe.
- **Acceptance:** no glitch pulses on the relay at boot; PWM duty maps correctly.
- **You learn:** GPIO drive strength, relay flyback/safety, LEDC PWM, fail-safe defaults.

### M2 — TWAI bring-up + loopback self-test
- Init `driver/twai.h`: `twai_general_config_t`, `TWAI_TIMING_CONFIG_500KBITS()`, accept-all filter.
- `can_rx_task` blocks on `twai_receive`; `can_tx_task` drains a tx queue to `twai_transmit`.
- Prove it with **TWAI loopback mode** (node receives its own frames) — no second device required.
- **Deliverable:** node transmits a frame and reads it back via loopback; alerts/bus state logged.
- **Acceptance:** stable at 500 kbps; `twai_get_status_info` reported; no error accumulation.
- **You learn:** CAN bit timing, the TWAI driver state machine, alert flags, tx/rx queueing.

### M3 — Frame codec (pack/unpack) + unit tests
- Implement encode/decode for all frames in §11 (heartbeat, telemetry, command, ack, result, error),
  including the CAN-ID compose/parse (`class | node_id`) and the scaling factors.
- **Unity unit tests** for the codec — this is pure logic, perfect for fast host tests.
- **Deliverable:** a tested `can_codec` module.
- **Acceptance:** round-trip encode→decode is lossless for every frame; boundary values tested.
- **You learn:** byte/bit packing, endianness, scaling/quantization, testable codec design.

### M4 — Outbound: register + heartbeat + telemetry over CAN
- On boot send register (`0x100|node`), then periodic heartbeat (`0x200|node`, §11.1) and
  telemetry (`0x300|node`, §11.2) from sensors (or simulated values).
- **Deliverable:** frames visible on the bus via `candump can0` (real HW) or on `vcan0`/loopback.
- **Acceptance:** correct IDs and byte layouts; cadence matches design; verified against Dev C's decoder.
- **You learn:** mapping app data → constrained frames, why CAN telemetry must be compact (§11).

### M5 — Inbound command path (validate → ack → execute → result)
- Decode `0x400|node` commands → validate → send `command_ack` (`0x500`, §11.4) →
  execute via `actuator_task` → send `command_result` (`0x600`, §11.5).
- Handle **`command_sequence`**: match ack/result, **dedup** repeated frames, reject stale sequences.
- **Deliverable:** Dev C (or `cansend`) issues a relay command; node acks, actuates, reports result.
- **Acceptance:** exactly one ack + one result per command; duplicates ignored; bad commands → error frame.
- **You learn:** request/response correlation without connections (CAN is message-based, §6.2), idempotency.

### M6 — Local safety logic (the headline feature) + bus-off recovery
- `local_safety_task` runs **independent of the gateway** (§9.2, §12.2):
  - **Gateway-loss watchdog:** if no command/heartbeat from the gateway within a timeout, drive actuators to the safe state.
  - **Max-runtime guard:** a pump can never stay on longer than X seconds, even if told to.
  - **Sensor-driven failsafe:** optional local threshold (e.g., stop watering past a moisture ceiling).
- **Bus-off recovery:** detect `TWAI_ALERT_BUS_OFF`, recover, and re-init cleanly.
- **Deliverable:** unplug the CAN link mid-operation → pump returns to safe state on its own; bus recovers after a fault injection.
- **Acceptance:** safe state always reached within the timeout; node never wedges after bus-off.
- **You learn:** autonomous fail-safe state machines, watchdog design, fault injection + recovery — *the* differentiator for safety-critical embedded roles.

### M7 — Stretch
- **CAN FD** (larger payloads) or **lightweight message auth** (truncated HMAC per §18.2),
  or **hybrid mode** (a node that can speak both Wi-Fi and CAN, §9 advanced).
- **You learn:** protocol evolution, embedded crypto tradeoffs, multi-transport architecture.

---

## Cross-cutting (do continuously)
- **Unit tests** (Unity) for the codec and the safety state machine (drive it with simulated time/events).
- **CI**: `idf.py build` for this node on every PR (share the workflow with Dev A).
- **README** in `firmware/esp32-can-node/`: transceiver wiring, CAN ID map, frame layouts, safety rules.

## Knowledge-share checkpoints
- After M3: swap walkthroughs with Dev A (you explain CAN frames/bit-packing, they explain WebSocket/JSON).
- Cross-review M5 command paths — same state machine, different transport.
- Stretch swap: implement one small piece of the WebSocket node so you've touched both stacks.

## Definition of done
CAN actuator node registers, heartbeats, sends telemetry, executes commands with
ack+result + sequence dedup, **enforces local safety autonomously when the gateway is
gone**, recovers from bus-off, has codec + safety unit tests and CI, with a documented
README. Stage-2 CAN path demonstrably reaches SQLite via Dev C's `can-gateway`.

## Interview talking points
- "I brought up the ESP32 TWAI controller at 500 kbps and designed an 11-bit CAN ID scheme with byte-packed frames."
- "I built a fail-safe state machine that drives actuators to a safe state on gateway loss, with a hard max-runtime guard — and tested it with fault injection."
- "I handled bus-off detection and recovery so a wiring fault can't permanently wedge the node."
- "I correlated commands with sequence numbers and made execution idempotent on a connectionless bus."
