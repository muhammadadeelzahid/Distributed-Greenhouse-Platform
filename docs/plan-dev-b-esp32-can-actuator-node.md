# Plan — Developer B: ESP32-S3 CAN Actuator + Safety Node (silicon-depth half)

> **Owner:** Developer B (ESP32-S3 / Xtensa LX7 dual-core + ULP-RISC-V)
> **Folder:** `firmware/esp32s3-can-node/`
> **Architecture refs:** `docs/architecture.md` §9.2 (ESP32 CAN node — *this is the canonical
> design*), §11 (CAN protocol — vendor-neutral), §12.2, §17.2/§17.4, §18.2, §19 (Stage 2)
> **MCU:** **ESP32-S3** — dual-core **Xtensa LX7 @240 MHz**, a separate **ULP-RISC-V**
> coprocessor, **MCPWM** motor-control peripheral, **TWAI** (classic CAN 2.0), native
> **USB-OTG + built-in USB-Serial-JTAG**, BLE 5.0, vector/SIMD ("AI") instructions, PSRAM.
> Reference: the **ESP32-S3 Technical Reference Manual (TRM)** + datasheet.
> **Mission:** Build the wired, deterministic actuator node (pump / fan / relay) that talks
> to the gateway over **TWAI (classic CAN 2.0)** and **keeps the greenhouse safe
> autonomously when the gateway is offline** — engineered to be the **silicon-depth + real-time
> + heterogeneous-compute** half of the project: register-level peripheral bring-up from the
> TRM, dual-core affinity for hard-real-time isolation, and an **always-on safety monitor
> running bare-metal on the ULP-RISC-V core** while the main cores sleep.

---

## Why this track is your strongest card for AMD / Intel (and any silicon/firmware team)

Node A is the *connectivity* node (Wi-Fi, BLE, bridge). **This node is the one that proves
you understand the chip** — and on the ESP32-S3 you can go just as deep as you would on a
bare-metal Cortex-M, while telling a story that maps *better* onto what AMD and Intel screen
for (heterogeneous compute, RISC-V, real-time determinism, performance):

- **Register-level peripheral driver work from the TRM**: bring up **MCPWM** (motor-control
  PWM — dead-time, fault/brake inputs) and **TWAI** (bit timing, acceptance filters, alerts)
  *below* the high-level ESP-IDF drivers — touching the peripheral registers, the **GPIO
  matrix / IO-MUX**, the **interrupt matrix** (peripheral→CPU interrupt routing), and the
  system clock/reset registers. You can explain where things live and how the silicon routes
  a signal — not "I called a library."
- **Heterogeneous compute, on one chip**: the S3 is **two Xtensa LX7 cores _plus_ a RISC-V
  ULP coprocessor**. You'll pin the **hard-real-time safety task to one core** (isolated from
  comms jitter), run CAN/telemetry on the other, and offload an **always-on watchdog to the
  ULP-RISC-V** — three compute elements, two ISAs, deliberately partitioned. This is the
  modern, defensible version of the "heterogeneous embedded" story.
- **A second ISA — RISC-V — bare-metal**: you write the ULP coprocessor program in **C (+ a
  little asm) against the RISC-V toolchain**, accessing RTC peripherals directly. RISC-V is a
  current, high-signal interview topic at both AMD and Intel; "I wrote bare-metal RISC-V for
  an always-on safety core" is a line most candidates can't say.
- **Hard-real-time reasoning + performance**: place hot ISRs in **IRAM** to avoid flash-cache
  jitter, measure interrupt/path latency with the **CCOUNT cycle counter**, reason about
  cache misses and cross-core contention. Determinism and profiling are exactly what
  firmware/perf interviews probe.
- **RTOS on a dual-core SMP target**: FreeRTOS in **SMP mode** — core affinity
  (`xTaskCreatePinnedToCore`), cross-core critical sections (`portMUX` spinlocks), ISR-to-task
  signaling with the interrupt matrix.
- **CAN error confinement up to bus-off recovery** (error-active / passive / bus-off, TEC/REC)
  — automotive/industrial-grade knowledge AMD/Xilinx (industrial, automotive) and Intel
  (IoT/edge) care about.
- **Boot & memory depth**: the ROM→2nd-stage-bootloader→app boot flow, the **partition table**,
  the flash/PSRAM memory map and XIP-via-cache, IRAM vs DRAM vs RTC memory, and the linker
  fragments — the S3 equivalent of "I read the linker script and know where every section lives."
- **Portable, HAL-abstracted C** shared with Node A — the same protocol logic compiling across
  **both nodes and (stretch) the RISC-V ULP**, proving real abstraction/portability judgment.

> **Why two ESP32-S3 boards isn't "the same thing twice":** real products pair a **connectivity
> SoC** with a **dedicated real-time/safety controller**. That's exactly the A↔B split here —
> same silicon family, deliberately *different jobs*, talking over a field bus. Owning the
> control/safety half end-to-end (register level → RTOS → RISC-V coprocessor → fail-safe) is a
> complete systems story on its own.

> **CAN FD note:** the ESP32-S3 TWAI is **classic CAN 2.0** (no CAN FD on this silicon). Knowing
> classic-CAN vs CAN-FD — and that this whole bus is classic — is a credibility signal in interviews.

---

## Integration contract (co-own with Dev A and Dev C)

The CAN protocol in architecture §11 is **vendor-neutral** classic CAN, so it applies unchanged
whether frames come from this node's TWAI, Node A's TWAI, or the Pi's SocketCAN. Pin these with
the team before writing protocol code (these are the seams):

- **CAN ID layout** (§11): bits `10..8` = message class, `7..0` = `node_id`. Classes:
  `0x100` register, `0x200` heartbeat, `0x300` telemetry, `0x400` command, `0x500` ack,
  `0x600` result, `0x700` error.
- **Node IDs**: e.g. `relay-node-001 = 0x21`, `pump-node-001 = 0x22`, `fan-node-001 = 0x23`.
- **Byte layouts** of each frame (§11.1–§11.5) + scaling factors + `command_type`/`target`/`value` enums.
- **Bus speed**: 500 kbps. **`command_sequence`** semantics for ack/result matching.

> **Shared, portable core (build with Dev A):** factor the *vendor-neutral* logic — the
> `telemetry`/`command` data model, the §11 **frame codec** (pure C, no vendor headers), the
> command/result state machine, CRC/util helpers — into a small **portable C library** that
> compiles on **both** ESP32-S3 nodes. Each node adds only a thin platform adapter (CAN
> send/recv, GPIO, timing). **Stretch:** also compile the codec for the **RISC-V ULP** target —
> the same source on Xtensa *and* RISC-V is the strongest possible "portable firmware + HAL
> boundary across two ISAs" proof. Building this with Dev A is the single highest-leverage move.

---

## Hardware & toolchain notes

- **Board: ESP32-S3** (dual-core Xtensa LX7 @240 MHz, ULP-RISC-V, ≥512 KB SRAM, optional
  octal/quad PSRAM). A DevKitC-1 (with USB for both the native USB-OTG port and the built-in
  USB-Serial-JTAG port) is ideal.
- **Actuators:** relay channel(s) via **GPIO**; a small **DC fan/pump driven through a
  MOSFET/motor-driver from an MCPWM output** (the sensor kit ships sensors, not actuators — add
  a relay module + a small fan/pump + a low-side MOSFET or motor-driver breakout). Enforce a
  **safe default at reset** (pump OFF) — no glitch pulse at boot.
- **Local safety sensor:** give this node *its own* sensor so safety never depends on the
  network. For the **ULP-RISC-V always-on path**, use an **analog sensor on an ADC1 / RTC-capable
  pin** (e.g. the kit's water-level or soil-moisture module, or a thermistor) — the ULP-RISC-V
  can read the SAR ADC in deep sleep. (Note: the DHT11 is *not* ULP-friendly — its bit-banged
  µs timing isn't an RTC peripheral; keep DHT-style reads on a main-core task.)
- **Actuator pins for the sleep path:** any actuator the ULP must hold safe during deep sleep
  has to be on an **RTC-capable GPIO** (only those keep state / are drivable while the main
  domain is powered down). Pick pins accordingly — exactly the datasheet detail interviewers like.
- **CAN transceiver required:** TWAI needs an external transceiver (SN65HVD230 / TJA1050). The
  bus carries **three controllers** — this node's TWAI, Node A's TWAI, and Dev C's **Pi
  SocketCAN** (typically a Microchip **MCP2515** SPI-CAN hat, i.e. a *second CAN-controller
  vendor* on the wire). Put **120 Ω termination at the two physical ends only**. Pick TX/RX
  GPIOs clear of strapping pins.
- **Toolchain & debug (shows depth, CI-friendly):** ESP-IDF + CMake; the **Xtensa toolchain**
  for the main cores and the **`riscv32-esp-elf` toolchain** for the ULP. Flash/debug over the
  **built-in USB-Serial-JTAG** (no external probe) with **OpenOCD + `gdb`**; trace via
  `esp_apptrace` / the JTAG console. Two toolchains, two ISAs, on-chip debug — a strong line.
- **Dev without the full bus:** TWAI **loopback/self-test mode** lets you TX→own-RX with no
  second node — perfect for M4 bring-up and CI. Move to the real **multi-node bus** (peered with
  Node A's TWAI and Dev C's SocketCAN) at M6.

---

## Milestones

Each milestone = one mergeable PR with a demo. Aligns with architecture Stage 2.

### M0 — Project skeleton + toolchain + memory map
- ESP-IDF project in `firmware/esp32s3-can-node/`; CMake build producing the app image; flash &
  monitor over **USB-Serial-JTAG**. Get a breakpoint with **OpenOCD + gdb** over the built-in JTAG.
- Read the **partition table** and the linker fragments; know what lives in **IRAM / DRAM / flash
  (XIP via cache) / RTC memory**, and the **ROM → 2nd-stage bootloader → app** boot flow.
- **Deliverable:** board boots, logs, halts at a breakpoint over JTAG; you can point at the memory map.
- **Acceptance:** `idf.py build` is clean; CI builds the image; gdb attaches over USB-JTAG.
- **You learn:** the ESP-IDF/CMake layout, the boot chain, partitions, the S3 memory map, on-chip debug.

### M1 — Actuator drivers with provably safe defaults (MCPWM, register-aware)
- Relay channels via **GPIO** (through the IO-MUX / GPIO matrix); fan/pump speed via **MCPWM**
  — configure timer/operator/generator, frequency, duty, and **dead-time**; wire an MCPWM
  **fault/brake input** so an over-condition forces the output to a safe level **in hardware**.
- Enforce a **safe boot state** (pump OFF) with **no glitch pulse** at reset.
- Do at least the MCPWM (and later TWAI) config **at the register level from the TRM**, not only
  via the high-level driver — and write up the register map you used.
- **Deliverable:** faked-local commands drive relay/fan; the scope shows correct PWM freq/duty +
  dead-time; the brake input forces safe state; boot state is provably clean.
- **You learn:** the MCPWM peripheral (motor-control-grade PWM), the GPIO matrix/IO-MUX, hardware
  fault handling, fail-safe defaults — register-level, from the manual.

### M2 — FreeRTOS SMP + dual-core task/queue architecture (real-time isolation)
- Bring up FreeRTOS in **SMP mode**. Create the §9.2 tasks: `can_rx_task`, `can_tx_task`,
  `sensor_task`, `actuator_task`, `heartbeat_task`, `local_safety_task`, plus
  `telemetry_queue` / `command_queue` / `result_queue`.
- **Pin `local_safety_task` (and the actuator path) to one core** (e.g. APP_CPU) and comms/CAN to
  the other (PRO_CPU) so network bursts can't add jitter to safety timing. Protect shared state
  with **`portMUX` spinlocks**; signal ISR→task correctly via the interrupt matrix.
- **Deliverable:** all tasks run on their assigned cores; heartbeat tick; an ISR safely wakes a task.
- **Acceptance:** no config-assert / priority inversion; stack high-water marks healthy; core
  affinity verified (log `xPortGetCoreID()`).
- **You learn:** SMP scheduling, core affinity for real-time isolation, cross-core synchronization,
  ISR-to-task patterns on the S3 interrupt matrix.

### M3 — Determinism pass (IRAM ISRs + latency measurement)
- Mark the CAN-RX / safety-critical ISRs **`IRAM_ATTR`** (and their data in DRAM) so they don't
  stall on a flash-cache miss; measure handler/path latency with the **CCOUNT cycle counter**.
- **Deliverable:** a short measured table — ISR latency with vs without IRAM placement, worst-case
  over a soak — and a one-paragraph explanation of *why* (cache, XIP).
- **You learn:** hard-real-time determinism on a cached XIP MCU, cycle-accurate measurement,
  the IRAM/flash-cache tradeoff — a genuine performance talking point for AMD/Intel.

### M4 — TWAI bring-up (register-level) + loopback self-test
- Configure **TWAI from the TRM**: bit timing for **500 kbps** (compute BRP/seg/SJW for a
  ~75–87.5% sample point), acceptance filter, the alert/status model, TX/RX queues.
- Verify in **loopback self-test mode** (TX → own RX) — no second node needed; log status/error counters.
- **Deliverable:** transmit a frame and receive it back via loopback; bit timing + filters correct.
- **Acceptance:** stable at 500 kbps; no error accumulation; filters accept only intended IDs.
- **You learn:** CAN bit-timing math, acceptance filtering, the TWAI controller model — register-deep.
- **Cross-node moment:** do this alongside Node A's TWAI bring-up and compare how each of you
  configured the *same* controller for the *same* bus.

### M5 — Frame codec (shared portable C) + unit tests
- Implement encode/decode for all §11 frames (register, heartbeat, telemetry, command, ack,
  result, error) incl. ID compose/parse and scaling — in the **portable C library shared with
  Node A** (no vendor headers).
- **Host unit tests** (CMake host build + Unity) — pure logic, fast feedback.
- **Deliverable:** a tested `can_codec` used by *both* nodes.
- **Acceptance:** lossless round-trip for every frame; boundary values covered; both nodes emit
  **byte-identical** frames for the same input (prove it); tests in CI.
- **You learn:** portable C, bit/byte packing, endianness, host-testable firmware design.

### M6 — Real bus: register + heartbeat + telemetry (multi-node link)
- Send register (`0x100|node`), periodic heartbeat (`0x200|node`, §11.1), telemetry
  (`0x300|node`, §11.2). Read the local safety sensor on a main-core task (and/or via the
  ADC path you'll reuse for the ULP in M9).
- Bring up the **real multi-node CAN bus** (Dev C's SocketCAN Pi + Node A's TWAI); verify with
  `candump can0`.
- **Deliverable:** this node's frames decoded live on the Pi, coexisting with Node A's TWAI
  traffic — a working **multi-controller bus** (two Espressif TWAI + Linux SocketCAN/MCP2515),
  i.e. cross-stack **RTOS↔Linux** interop.
- **Acceptance:** correct IDs/layouts on the wire; cadence matches design; verified against Dev C's
  decoder; no arbitration/error issues sharing the bus.
- **You learn:** real-bus debugging with a logic analyzer/scope, arbitration/coexistence,
  RTOS↔Linux interop.

### M7 — Inbound command path (validate → ack → execute → result)
- Decode `0x400|node` commands → validate → `command_ack` (`0x500`, §11.4) → execute via
  `actuator_task` → `command_result` (`0x600`, §11.5). Handle **`command_sequence`**: correlate
  ack/result, **dedup** repeats, reject stale sequences.
- **Deliverable:** Dev C (or `cansend`) issues a relay/fan command; node acks, actuates, reports result.
- **Acceptance:** exactly one ack + one result per command; duplicates ignored; bad commands → error frame.
- **You learn:** request/response correlation on a connectionless bus, idempotency, protocol→hardware.

### M8 — Local safety logic (the headline) + CAN error confinement
- `local_safety_task` runs **independent of the gateway** (§9.2, §12.2):
  - **Gateway-loss watchdog:** no command/heartbeat within a timeout → drive actuators to safe state.
  - **Max-runtime guard:** a pump can never run longer than X seconds, regardless of commands.
  - **Sensor failsafe:** local threshold ceiling (e.g. over-temp / over-level → shut off).
  - Wire the **RTC watchdog (RWDT)** as the lowest-level fail-safe so a full firmware hang itself
    resets to a safe boot state (note the S3's three watchdog layers: Task WDT, Interrupt WDT, RWDT).
- **CAN error confinement & bus-off recovery:** track TEC/REC; handle error-active → passive →
  **bus-off**; auto-recover the TWAI controller after a bus fault and rejoin.
- **Deliverable:** cut the CAN link mid-run → pump returns to safe state autonomously; inject a bus
  fault → node recovers; force a hang → RWDT resets it safely.
- **Acceptance:** safe state always reached within the timeout; node never wedges after bus-off; RWDT fires on a forced hang.
- **You learn:** autonomous fail-safe state machines, the S3 watchdog hierarchy, **CAN error states**
  — the automotive/industrial differentiator.

### M9 — ULP-RISC-V always-on safety coprocessor (the differentiator)
- Move the **most critical, always-on check onto the ULP-RISC-V**: with the main cores in **deep
  sleep**, the ULP wakes periodically, reads the **RTC ADC** (the local safety sensor), and on a
  threshold breach either **holds an RTC-GPIO actuator in the safe state** and/or **wakes the SoC**.
- Write the ULP program in **C against the `riscv32-esp-elf` toolchain** (drop to asm for the
  hot loop if you want the deepest line); share constants with the main app via **RTC slow memory**.
- **Deliverable:** unplug everything but power; the system deep-sleeps; the ULP-RISC-V still
  enforces the safety ceiling and wakes the SoC on breach. Show the µA-level sleep current if you
  have a meter.
- **Acceptance:** safety holds across a full deep-sleep cycle driven *only* by the ULP-RISC-V; the
  main cores confirm the breach on wake.
- **You learn:** **bare-metal RISC-V**, a real coprocessor-offload/heterogeneous-compute design,
  RTC peripherals (RTC ADC / RTC GPIO / RTC memory), and ultra-low-power architecture — the most
  distinctive line in the whole project.

### M10 — Stretch (pick one; each is a strong résumé line — tuned to the S3)
- **No-driver TWAI or MCPWM** (raw registers only, straight from the TRM) — *prove* silicon depth,
  exactly what SoC firmware interviews probe. **(Top pick.)**
- **Use the S3 vector/SIMD ("AI") ISA**: run sensor filtering (FIR/IIR) via **ESP-DSP**, or a tiny
  **on-device anomaly detector** (ESP-DL/ESP-NN) that flags abnormal readings locally — an edge-AI
  + performance story Intel (OpenVINO/edge) and AMD (AI engines) screen for directly.
- **Compile the §11 codec for the ULP-RISC-V** too — the same C on Xtensa *and* RISC-V (ultimate portability proof).
- **CAN bootloader / IAP**: update node firmware over the bus — "OTA without a network."
- **Deeper low-power**: characterize/optimize the deep-sleep + ULP duty cycle with measured current.
> Note: the S3 TWAI is **classic CAN only** — CAN FD isn't available on this silicon. Naming that
> correctly is a common interview gotcha you'll get right.

---

## Cross-cutting (do continuously)
- **Unit tests** (host, Unity) for the codec and the safety state machine (drive it with simulated time).
- **CI**: a GitHub Actions job that runs the `idf.py` build + host tests on every PR (repo CI matrix
  builds *both* ESP32-S3 nodes and runs the shared host codec tests).
- **README** in `firmware/esp32s3-can-node/`: exact board, full pinout (relay/MCPWM/CAN TX-RX +
  transceiver, RTC-capable actuator + ADC pins for the ULP), termination, CAN bit-timing, the
  USB-JTAG/OpenOCD debug setup, and the ULP-RISC-V build/flow.

## Knowledge-share checkpoints (heterogeneous-by-design — learn the other half too)
- After M4: 30-min swap with Dev A — both nodes bring up the **same TWAI controller** for the
  **same bus**; compare your configs, then they explain **Wi-Fi/WebSocket/JSON + BLE provisioning**
  and you explain **register-level peripherals + dual-core/ULP-RISC-V real-time**.
- After M9: walk the team through the **dual-Xtensa + ULP-RISC-V** partition — three compute
  elements, two ISAs, on one chip. Gold for interviews.
- Cross-review the command paths — same state machine, two transports, one shared codec.
- With Dev A + Dev C: pair-debug the live multi-node CAN bus on a logic analyzer (M6).

## Definition of done
An ESP32-S3 actuator node that boots and runs **dual-core FreeRTOS SMP** with the **safety task
isolated on its own core**, brings up **MCPWM + TWAI from the TRM** (register-level), sends
register/heartbeat/telemetry and executes commands with ack+result + sequence dedup over a **real
multi-node CAN bus**, **enforces local safety autonomously** (incl. the RWDT fail-safe) and
recovers from bus-off, runs an **always-on safety monitor on the ULP-RISC-V** through deep sleep,
shares a portable tested codec with Node A, and has CI + a documented README.

## Interview talking points (AMD/Intel-tuned)
- "I built a deterministic real-time controller on the ESP32-S3: I pinned the safety task to a
  dedicated core, placed its ISRs in IRAM to avoid flash-cache jitter, and measured the latency win with the cycle counter."
- "I brought up MCPWM and the TWAI CAN controller at the register level from the Technical
  Reference Manual — bit timing, acceptance filters, dead-time, a hardware brake input."
- "I offloaded the always-on safety watchdog to the RISC-V ULP coprocessor: it reads the RTC ADC
  and holds actuators safe while the main Xtensa cores deep-sleep — bare-metal RISC-V, heterogeneous compute, ultra-low-power."
- "I handled CAN error confinement up to bus-off recovery and wired the RTC watchdog so a firmware hang still fails safe."
- "I wrote a portable, HAL-abstracted C codec that compiles unchanged across both nodes — and (stretch) on the RISC-V ULP too — proving the abstraction boundary across two ISAs."
- "(Stretch) I used the S3's vector/SIMD instructions for on-device sensor filtering / anomaly detection — an edge-AI + performance angle, not just toggling GPIO."
