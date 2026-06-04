# Portfolio & Job Strategy — Distributed Greenhouse Platform

> How to build this project so it lands embedded/firmware interviews at **AMD, Qualcomm,
> NXP, TI, Infineon, Bosch**, etc. — and how to *talk about it* once it's built.
> Pair this with the per-developer plans:
> [Dev A — ESP32 hybrid](plan-dev-a-esp32-hybrid-node.md) ·
> [Dev B — STM32 CAN](plan-dev-b-stm32-can-actuator-node.md) ·
> [Dev C — Pi gateway](plan-dev-c-raspberry-pi-gateway.md) ·
> [Provisioning flow](provisioning-and-onboarding-flow.md).

---

## The one-paragraph pitch
> "A distributed, offline-first greenhouse control system. A heterogeneous edge — an
> **ESP32** (Xtensa, Wi-Fi + CAN, secure BLE provisioning) and an **STM32** (bare-metal
> ARM Cortex-M, CAN) — talks over a **3-vendor CAN bus** and Wi-Fi to a **Raspberry Pi
> embedded-Linux gateway** (SocketCAN, SQLite, systemd), which syncs to a **Go/gRPC cloud
> backend** on Postgres. A **mobile app** onboards devices. It keeps running with no cloud."

That sentence alone covers: multi-vendor CAN, bare-metal ARM, RTOS on two ISAs, embedded
Linux, secure onboarding, gRPC, offline-first distributed design. That's the whole point.

---

## System topology
```
                 Mobile app (BLE provisioning + backend API)
                   |                                  |
           BLE/SoftAP                              HTTPS
                   v                                  v
   ESP32 hybrid (Xtensa)  --Wi-Fi/WebSocket-->   Raspberry Pi  --gRPC/TLS-->  Cloud (Go)
   Wi-Fi + CAN/TWAI  --\                          gateway              \--> PostgreSQL
                        \                       (Linux, SocketCAN,
   ===== CAN bus @500k ==\========================  SQLite, systemd)
            ^             \                          ^
            |              \-- STM32F407 (Cortex-M4F) -/
       3 CAN vendors:   Espressif TWAI + ST bxCAN (F407) + Linux SocketCAN
       (all classic CAN 2.0)  + Flutter mobile app (BLE provisioning)
```

---

## Skills → what AMD/Qualcomm actually screen for
| The skill in this project | Why these companies care |
|---|---|
| **Bare-metal ARM Cortex-M** (startup, linker, clock tree, NVIC) — STM32 | They design/ship ARM-based silicon; they want people who understand the chip, not a framework |
| **Peripheral driver bring-up from the reference manual** (CAN, I²C, ADC, DMA, timers) | Core of any firmware/BSP role |
| **CAN + error confinement/bus-off**, multi-vendor interop | Automotive (Qualcomm Snapdragon Digital Chassis, AMD/Xilinx automotive), industrial |
| **RTOS internals** (FreeRTOS on Cortex-M *and* Xtensa) | Real-time firmware everywhere |
| **Embedded Linux** (SocketCAN, systemd, device tree, Yocto/RAUC) | Linux BSP/kernel is huge at both |
| **Secure onboarding / BLE provisioning** | Connected-product credibility most candidates lack |
| **DMA + interrupts + hard-real-time reasoning** | Performance/driver interviews probe this directly |
| **Portable C across two vendors/ISAs (HAL boundary)** | Shows abstraction + portability judgment |
| **gRPC / protobuf / distributed offline-first** | Modern device↔cloud systems |

---

## Résumé bullets (tighten with real numbers once measured)
- Built a distributed embedded system spanning **bare-metal ARM Cortex-M4F (STM32F407), RTOS on ESP32, and embedded Linux (Raspberry Pi)**, integrated over a **3-vendor CAN bus** and Wi-Fi, with a **Flutter** companion app for BLE provisioning.
- Brought up the **STM32 CAN peripheral from the reference manual** (bit timing, filters, mailboxes) and implemented **bus-off recovery** + an IWDG fail-safe state machine.
- Implemented an **ESP32 Wi-Fi↔CAN bridge** with secure **BLE (sec2) provisioning** and offline-first telemetry buffering.
- Wrote a **portable C protocol codec** shared across two MCU vendors; verified byte-identical CAN frames in host unit tests + CI.
- Built a **Linux gateway** (SocketCAN, SQLite, systemd) syncing to a **Go/gRPC** cloud over TLS with offline backlog + reconnect.

---

## "Walk me through a project" (STAR skeleton)
- **Situation:** offline-capable greenhouse; unreliable Wi-Fi; safety-critical actuators.
- **Task:** reliable distributed control + telemetry that survives network loss, with a clean device-onboarding story.
- **Action:** heterogeneous edge (ESP32 + STM32) on a multi-vendor CAN bus; bare-metal CAN driver + fail-safe logic on the STM32; Wi-Fi↔CAN bridge + BLE provisioning on the ESP32; Linux gateway with SQLite buffering + gRPC sync.
- **Result:** end-to-end telemetry to the cloud; local automation + safety with no cloud; phone-based onboarding. *(Add metrics: bus load %, telemetry rate, reconnect time, soak duration.)*

---

## Proof artifacts to capture (this is what makes it credible)
1. **2–3 min demo video**: provision from the phone → telemetry in the cloud → pull the network → local safety still works → bus-off recovery.
2. **Logic-analyzer / oscilloscope captures** of the CAN bus and an I²C transaction (shows you actually debugged hardware).
3. **`candump` log** showing ESP32 + STM32 frames coexisting (multi-vendor interop, undeniable).
4. **Green CI badge**: matrix building ESP-IDF + `arm-none-eabi-gcc`, running host codec tests.
5. **Architecture diagram** + clean per-component READMEs.
6. **A short "design decisions & tradeoffs" write-up** (CAN vs Wi-Fi, classic CAN vs CAN FD, offline-first reconciliation).

---

## Interview deep-dive prep (be ready to defend every layer)
- CAN bit timing: how you picked BRP/segments for 500 kbps and the sample point; arbitration; error frames; error-active→passive→bus-off.
- Classic CAN vs **CAN FD** — when/why; and why *this* build is all classic (ESP32 TWAI + STM32F407 bxCAN are both classic CAN 2.0).
- FreeRTOS on Cortex-M: PendSV/SysTick, `configMAX_SYSCALL_INTERRUPT_PRIORITY`, ISR-to-task, priority inversion.
- DMA vs interrupt vs polling tradeoffs; cache/coherency on the H7 if used.
- Linker script & memory map; where `.data`/`.bss`/stack live; startup sequence.
- BLE provisioning security (sec2/SRP6a, PoP) and your factory-reset design.
- Offline-first reconciliation: local (app→hub) vs cloud (backend→hub) authorization.

---

## Suggested team build order (de-risks integration)
1. **Dev C M0** test harness (WebSocket endpoint + `vcan0`) — unblocks everyone day one.
2. **Dev A Phase 1** (Wi-Fi telemetry) → first cloud loop = motivating early win.
3. **Dev B** STM32 CAN bring-up → **Dev C** `can-gateway` → multi-vendor bus.
4. **Dev A Phase 2** (ESP32 on the bus + bridge) → 3-vendor interop demo.
5. **Provisioning** (Dev A M7 + Dev C M6 + mobile app) → onboarding story.
6. Robustness, OTA, Yocto/RAUC, security hardening.

> Indicative pace: a strong end-to-end demo (steps 1–4) is achievable in ~6–10 focused
> weeks part-time; provisioning + polish adds a few more. Lock the **§10/§11 contracts and
> the shared codec early** — that's where integration time is won or lost.
