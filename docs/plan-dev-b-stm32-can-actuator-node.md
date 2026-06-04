# Plan — Developer B: STM32F407 (ARM Cortex-M4F) CAN Actuator Node

> **Owner:** Developer B (STM32F407 / ARM Cortex-M4F)
> **Folder:** `firmware/stm32-can-node/`
> **Architecture refs:** `docs/architecture.md` §9.2 (adapted: STM32 instead of ESP32/TWAI),
> §11 (CAN protocol — vendor-neutral), §12.2, §17.2/§17.4, §18.2, §19 (Stage 2)
> **MCU:** STM32F407 — Cortex-**M4F** @168 MHz, hardware **FPU + DSP**, **bxCAN** (classic
> CAN 2.0; *no CAN FD* on this part), dual CAN1/CAN2. Reference manual **RM0090**.
> **Mission:** Build the wired, deterministic actuator node (pump / fan / relay) on a
> **bare-metal + FreeRTOS STM32F407 (ARM Cortex-M4F)**, talking to the gateway over the
> **bxCAN peripheral (CAN1, classic CAN 2.0)**, and keeping the greenhouse safe
> autonomously when the gateway is offline. This is the **silicon-depth** half of
> the project — register-level MCU work, not a framework.

---

## Why this track is your strongest card for AMD / Qualcomm / NXP / TI / Infineon

Silicon and SoC companies don't hire "I called an Arduino library." They hire people
who **understand the chip**: the memory map, the peripherals, the bus, the real-time
behavior — straight from the reference manual. This STM32 track is engineered to give
you exactly those talking points:

- **ARM Cortex-M4F from the ground up**: startup code, vector table, linker script,
  memory map, the NVIC, SysTick, the clock tree (RCC/PLL to 168 MHz), and the **hardware
  FPU/DSP**. You can explain how the chip boots and where every section lives.
- **Register-level peripheral driver work**: configure the **bxCAN peripheral** — bit
  timing, acceptance filter banks, TX mailboxes / RX FIFOs — from RM0090, plus GPIO,
  timers (PWM), and ADC.
- **DMA + interrupts**: zero-CPU sensor acquisition and logging; ISR-to-task signaling
  with correct NVIC priorities. Hard-real-time reasoning.
- **RTOS on ARM**: FreeRTOS Cortex-M port (PendSV/SysTick, `configMAX_SYSCALL_INTERRUPT_PRIORITY`).
- **Pro toolchain & debug**: `arm-none-eabi-gcc` + CMake + OpenOCD + `gdb` over **SWD**,
  SWO/ITM trace, and a **logic analyzer / oscilloscope** on a live CAN bus.
- **CAN error confinement up to bus-off recovery** (error-active / passive / bus-off,
  TEC/REC) — automotive-grade knowledge Qualcomm's Snapdragon-Digital-Chassis and
  AMD/Xilinx automotive teams care about.
- **Portable, HAL-abstracted C** shared with the ESP32 node — the same firmware logic
  compiling across **two vendors and two ISAs** (ST ARM + Espressif Xtensa).

> **System-level flex:** the finished portfolio spans the *entire* embedded spectrum —
> bare-metal/RTOS on ARM Cortex-M (this node), RTOS on Xtensa (ESP32), and embedded
> Linux on ARM Cortex-A (the Pi), tied together by CAN and a real protocol. That
> heterogeneity is itself a standout interview story.

---

## Integration contract (co-own with Dev A and Dev C)

The CAN protocol in architecture §11 is **vendor-neutral** — it's just classic CAN, so
it applies unchanged whether the frames come from an ESP32 TWAI or an STM32 bxCAN.
Pin these with the team before writing protocol code (these are the seams):

- **CAN ID layout** (§11): bits `10..8` = message class, `7..0` = `node_id`. Classes:
  `0x100` register, `0x200` heartbeat, `0x300` telemetry, `0x400` command, `0x500` ack,
  `0x600` result, `0x700` error.
- **Node IDs**: e.g. `relay-node-001 = 0x21`, `pump-node-001 = 0x22`, `fan-node-001 = 0x23`.
- **Byte layouts** of each frame (§11.1–§11.5) + scaling factors + `command_type`/`target`/`value` enums.
- **Bus speed**: 500 kbps. **`command_sequence`** semantics for ack/result matching.

> **Shared, portable core:** factor the *vendor-neutral* logic — the `telemetry`/`command`
> data model, the §11 **frame codec** (pure C, no vendor headers), the command/result
> state machine, CRC/util helpers — into a small **portable C library** that compiles on
> *both* the STM32 (this node) and the ESP32 (Dev A). Each MCU then provides only a thin
> platform adapter (CAN send/recv, GPIO, timing). Building this with Dev A is the single
> highest-leverage move for learning *and* it's a textbook "portable firmware + HAL
> boundary" story for interviews.

---

## Hardware & toolchain notes

- **Board: STM32F407** (Cortex-**M4F** @168 MHz, hardware FPU + DSP). The CAN peripheral is
  **bxCAN** (classic CAN 2.0 — *no CAN FD* on this silicon). The F407 actually has **two**
  bxCAN cells (CAN1 + CAN2); CAN2 is a "slave" that needs CAN1's clock enabled and shares the
  28 filter banks + 512-byte CAN SRAM with CAN1. We only need **CAN1** for the single bus —
  bringing up CAN2 too is a tidy advanced stretch (M8). Boards: STM32F4-Discovery or a
  Nucleo-F407 + a transceiver on the CAN1 pins (PB8/PB9 or PD0/PD1 or PA11/PA12).
- **Transceiver required:** the STM32 CAN peripheral needs an external transceiver
  (SN65HVD230 / TJA1050 / MCP2551). The bus now carries **three controllers** — your STM32,
  Dev A's **ESP32 TWAI**, and Dev C's **Pi SocketCAN** — so put **120 Ω termination at the
  two physical ends only**. Mind 3.3 V vs 5 V logic on the STM32 CAN_TX/CAN_RX pins.
- **Toolchain (CI-friendly, shows depth):** use **STM32CubeMX** to generate clock/pin init
  + the HAL skeleton, but **build with CMake + `arm-none-eabi-gcc`** (not the CubeIDE
  Eclipse project) so it builds headlessly in CI. Flash/debug with **OpenOCD + ST-Link +
  `arm-none-eabi-gdb`** over **SWD**; log via UART and/or **SWO/ITM**.
- **Dev without the full bus:** the CAN peripheral's **loopback/silent-loopback self-test
  mode** lets you transmit and receive your own frames with no second node — perfect for
  M3 bring-up and CI. Move to the real **multi-vendor bus** (peered with Dev A's ESP32 TWAI
  and Dev C's SocketCAN) at M5 — that's the cross-vendor interop centerpiece.

---

## Milestones

Each milestone = one mergeable PR with a demo. Aligns with architecture Stage 2.

### M0 — Bare-metal bring-up + toolchain
- Generate init with CubeMX (or hand-write startup for max credit); build a CMake +
  `arm-none-eabi-gcc` project producing a `.elf`/`.bin`; flash via OpenOCD/ST-Link.
- Blink an LED; get `printf` out over UART (or SWO/ITM). Read your linker script and map
  file — know where `.text`/`.data`/`.bss`/stack/heap live.
- **Deliverable:** board blinks + prints; `gdb` over SWD can set a breakpoint.
- **Acceptance:** `cmake --build` produces a flashable image; CI builds the `.elf`.
- **You learn:** ARM toolchain, linker scripts, startup/vector table, flashing & on-chip debug, the memory map.

### M1 — Clock tree + actuator drivers with safe defaults
- Configure **RCC/PLL** to your target system clock; understand the clock domains feeding your peripherals.
- Relay channels via **GPIO**; fan speed via **TIM PWM**. Enforce a **safe default state**
  (pump OFF, fan as configured) at reset and on fault — no glitch pulse at boot.
- **Deliverable:** locally-faked commands toggle relay/fan; boot state is provably safe.
- **Acceptance:** correct PWM frequency/duty on the scope; relay never twitches at reset.
- **You learn:** clock-tree config, timer/PWM internals, GPIO registers, fail-safe defaults.

### M2 — FreeRTOS + task/queue architecture
- Bring up the **FreeRTOS Cortex-M port** (CMSIS-RTOS2 or native). Create the §9.2 tasks:
  `can_rx_task`, `can_tx_task`, `sensor_task`, `actuator_task`, `heartbeat_task`,
  `local_safety_task`, plus `telemetry_queue`/`command_queue`/`result_queue`.
- Signal from ISR → task correctly (`...FromISR`, deferred handling); set NVIC priorities
  below `configMAX_SYSCALL_INTERRUPT_PRIORITY` for RTOS-aware ISRs.
- **Deliverable:** all tasks run; heartbeat tick; an ISR safely wakes a task.
- **Acceptance:** no priority-inversion / config-assert; stack high-water marks healthy.
- **You learn:** RTOS internals on Cortex-M (PendSV/SysTick), NVIC priority grouping, ISR-to-task patterns.

### M3 — bxCAN peripheral bring-up (CAN1) + loopback
- Configure **bxCAN CAN1 from RM0090**: bit-timing for 500 kbps derived from
  **APB1/PCLK1 = 42 MHz** on the F407 (compute BRP/BS1/BS2/SJW for a ~75–87.5% sample point),
  acceptance **filter banks**, the 3 RX FIFOs / 3 TX mailboxes, interrupt-driven RX.
- Verify in **loopback self-test mode** (TX → own RX) — no second node needed.
- **Deliverable:** transmit a frame and receive it back via loopback; peripheral status/error counters logged.
- **Acceptance:** stable at 500 kbps; no error accumulation; filters accept only intended IDs.
- **You learn:** CAN bit-timing math, acceptance filtering, mailbox/FIFO model — deep silicon knowledge.

### M4 — Frame codec (shared portable C) + unit tests
- Implement encode/decode for all §11 frames (register, heartbeat, telemetry, command,
  ack, result, error) including ID compose/parse and scaling — in the **portable C
  library** shared with Dev A (no vendor headers).
- **Host unit tests** (CMake host build + Unity/Ceedling) — pure logic, fast feedback.
- **Deliverable:** a tested `can_codec` usable by both the STM32 and ESP32 builds.
- **Acceptance:** lossless round-trip for every frame; boundary values covered; tests in CI.
- **You learn:** portable C, bit/byte packing, endianness, host-testable firmware design.

### M5 — Real bus: register + heartbeat + telemetry (cross-vendor link)
- Send register (`0x100|node`), periodic heartbeat (`0x200|node`, §11.1), and telemetry
  (`0x300|node`, §11.2). Read a sensor via **ADC + DMA** (circular buffer, zero CPU per sample).
- Bring up the **real multi-vendor CAN bus** (Dev C's SocketCAN Pi + Dev A's ESP32 TWAI node); verify with `candump can0`.
- **Deliverable:** STM32 frames decoded live on the Pi, coexisting with ESP32 TWAI traffic — a genuine **3-vendor (ST + Espressif + Linux) CAN bus**.
- **Acceptance:** correct IDs/layouts on the wire; cadence matches design; verified against Dev C's decoder; no arbitration/error issues sharing the bus with the other two controllers.
- **You learn:** DMA, real-bus debugging with a logic analyzer/oscilloscope, cross-vendor interop.

### M6 — Inbound command path (validate → ack → execute → result)
- Decode `0x400|node` commands → validate → `command_ack` (`0x500`, §11.4) → execute via
  `actuator_task` → `command_result` (`0x600`, §11.5). Handle **`command_sequence`**:
  correlate ack/result, **dedup** repeats, reject stale sequences.
- **Deliverable:** Dev C (or `cansend`) issues a relay command; node acks, actuates, reports result.
- **Acceptance:** exactly one ack + one result per command; duplicates ignored; bad commands → error frame.
- **You learn:** request/response correlation on a connectionless bus, idempotency.

### M7 — Local safety logic (the headline) + CAN error confinement
- `local_safety_task` runs **independent of the gateway** (§9.2, §12.2):
  - **Gateway-loss watchdog:** no command/heartbeat within a timeout → drive actuators to safe state.
  - **Max-runtime guard:** a pump can never run longer than X seconds, regardless of commands.
  - Optional **sensor failsafe** (local threshold ceiling).
  - Wire the **independent watchdog (IWDG)** so a firmware hang itself fails safe.
- **CAN error confinement & bus-off recovery:** track TEC/REC, handle error-active →
  passive → **bus-off**, and auto-recover the peripheral after a bus fault.
- **Deliverable:** cut the CAN link mid-run → pump returns to safe state autonomously;
  inject a bus fault → node recovers and rejoins.
- **Acceptance:** safe state always reached within the timeout; node never wedges after bus-off; IWDG resets on a forced hang.
- **You learn:** autonomous fail-safe state machines, hardware watchdogs, **CAN error states** — the automotive/industrial differentiator.

### M8 — Stretch (pick one; each is a strong résumé line — tuned to the F407)
- **Register-level / LL bxCAN driver** (no HAL): re-implement CAN1 against raw registers
  from RM0090 to *prove* silicon depth — exactly what SoC firmware interviews probe. **(Top pick for the F407.)**
- **Dual-CAN bring-up** (CAN1 **+** CAN2): handle the master/slave clock dependency and the
  shared filter-bank split — a genuinely tricky F4 detail that shows you read the manual.
- **Exploit the M4F FPU + CMSIS-DSP**: run sensor filtering (FIR/IIR) on the hardware FPU/DSP
  instructions — shows you use the core, not just toggle GPIO.
- **Low-power modes** (STOP/Standby) with CAN wake — modem/IoT-relevant for Qualcomm.
- **CAN bootloader / IAP**: update node firmware over the bus — embedded "OTA without a network."
> Note: the F407's bxCAN is **classic CAN only** — CAN FD isn't available on this silicon.
> Naming that line correctly is a common interview gotcha you'll get right.

---

## Cross-cutting (do continuously)
- **Unit tests** (host, Unity/Ceedling) for the codec and the safety state machine (drive it with simulated time).
- **CI**: a GitHub Actions job that runs the CMake + `arm-none-eabi-gcc` build and the host tests on every PR.
- **README** in `firmware/stm32-can-node/`: exact part number, pinout, transceiver wiring + termination, clock config, CAN bit-timing, and the OpenOCD/SWD debug setup.

## Knowledge-share checkpoints (heterogeneous-by-design — learn the other half too)
- After M3: 30-min swap with Dev A. Since **both of you now bring up CAN** (STM32 bxCAN
  vs ESP32 TWAI), compare the two vendors' peripherals directly — bit-timing config, filters,
  mailbox/FIFO models — then they explain **ESP-IDF + Wi-Fi/WebSocket/JSON + BLE provisioning**
  and you explain **ARM Cortex-M bare-metal**. Two CAN vendors, two ISAs — gold for interviews.
- Cross-review the command paths — same state machine, two transports and two MCU vendors.
- With Dev A + Dev C: pair-debug the live **3-vendor CAN bus** on a logic analyzer (M5).
- Stretch swap: build one small piece on the ESP32 so you can speak to *both* MCU stacks.

## Definition of done
STM32 actuator node boots from your own startup/linker setup, runs FreeRTOS, brings up
the CAN peripheral from the reference manual, sends register/heartbeat/telemetry and
executes commands with ack+result + sequence dedup over a **real cross-vendor CAN bus**,
**enforces local safety autonomously** (incl. IWDG) and recovers from bus-off, shares a
portable tested codec with the ESP32 node, and has CI + a documented README.

## Interview talking points (silicon-company-tuned)
- "I brought up an ARM Cortex-M from the reference manual — startup, linker script, clock tree — and configured the CAN peripheral's bit timing, filters, and mailboxes by hand."
- "I handled CAN error confinement up to bus-off recovery, and added a hardware IWDG so a firmware hang still fails safe."
- "I used ADC+DMA for zero-CPU sensor acquisition and set NVIC priorities for RTOS-safe ISRs."
- "I wrote a portable, HAL-abstracted C codec that compiles unchanged on two MCU vendors and two ISAs (ST ARM + Espressif Xtensa)."
- "I debugged a live cross-vendor CAN bus with a logic analyzer and OpenOCD/gdb over SWD."
- "(Stretch) I wrote a register-level CAN driver with no HAL / implemented CAN FD / a CAN bootloader."
