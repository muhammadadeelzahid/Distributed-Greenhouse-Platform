# Portfolio & Job Strategy — Distributed Greenhouse Platform

> How to build this project so it lands embedded/firmware interviews at **AMD and Intel**
> (and other silicon/firmware/IoT teams: NXP, TI, Infineon, Bosch, networking & edge shops)
> — and how to *talk about it* once it's built.
> Pair this with the per-developer plans:
> [Dev A — ESP32-S3 hybrid](plan-dev-a-esp32-hybrid-node.md) ·
> [Dev B — ESP32-S3 CAN/safety](plan-dev-b-esp32-can-actuator-node.md) ·
> [Dev C — Pi gateway](plan-dev-c-raspberry-pi-gateway.md) ·
> [Provisioning flow](provisioning-and-onboarding-flow.md).

---

## The one-paragraph pitch
> "A distributed, offline-first greenhouse control system on a **heterogeneous edge of two
> ESP32-S3 nodes** — one a **connectivity/sensing + Wi-Fi↔CAN bridge** (Wi-Fi/WebSocket, secure
> BLE provisioning), the other a **deterministic real-time controller** with register-level
> peripheral bring-up, a **dual-core safety partition**, and an **always-on safety monitor
> running bare-metal on its RISC-V ULP coprocessor**. They talk over a **multi-controller CAN
> bus** (two TWAI controllers + Linux SocketCAN) to a **Raspberry Pi embedded-Linux gateway**
> (SocketCAN, SQLite, systemd, Yocto) that syncs to a **Go/gRPC cloud backend** on Postgres. A
> **Flutter mobile app** onboards devices. It keeps running with no cloud."

That sentence covers: **heterogeneous compute (two ISAs on one chip), bare-metal RISC-V,
register-level driver bring-up, hard-real-time determinism, CAN + multi-controller interop,
RTOS (SMP) + embedded Linux + Yocto, secure onboarding, gRPC, and offline-first distributed
design** — exactly the surface AMD and Intel screen for.

---

## System topology
```
                 Mobile app (Flutter — BLE provisioning + backend API)
                   |                                  |
           BLE 5.0 / SoftAP                        HTTPS
                   v                                  v
  ESP32-S3 hybrid node (A)  --Wi-Fi/WebSocket-->  Raspberry Pi  --gRPC/TLS-->  Cloud (Go)
  sensing + Wi-Fi↔CAN bridge --\                     gateway             \--> PostgreSQL
  (dual Xtensa LX7)             \                  (Linux, SocketCAN,
                                 \                  SQLite, systemd, Yocto)
   ==== CAN bus @500k classic ===\=======================  ^
            ^                      \                        |
            |                       \-- ESP32-S3 node (B) --/
            |                          real-time control + safety
   3 CAN controllers:                  • register-level MCPWM/TWAI (from the TRM)
   TWAI (A) + TWAI (B)                 • dual-core: safety task pinned to its own core
   + Linux SocketCAN (MCP2515)         • ULP-RISC-V always-on safety monitor (2nd ISA)
   (all classic CAN 2.0)               • CAN bus-off recovery + RTC-WDT fail-safe
```

---

## Skills → what AMD / Intel actually screen for
| The skill in this project | Why these companies care |
|---|---|
| **Heterogeneous compute on one SoC** — dual Xtensa LX7 cores + a **RISC-V ULP** coprocessor; core affinity, offload, two ISAs | Heterogeneous/accelerated compute is the center of gravity at both (AMD adaptive SoCs/AI engines; Intel CPU+FPGA+accelerators) |
| **Bare-metal RISC-V** (the ULP-RISC-V always-on safety core) | RISC-V is an active program at both AMD and Intel; few candidates can say they wrote bare-metal RISC-V |
| **Register-level peripheral bring-up from the TRM** (MCPWM, TWAI/CAN, GPIO matrix, interrupt matrix, ADC) | Core of any firmware/BSP/driver role — proves you understand the chip, not a framework |
| **Hard-real-time determinism + performance** (IRAM vs flash-cache, cycle-counter latency measurement, cross-core contention) | Performance/driver interviews probe this directly |
| **RTOS internals on a dual-core SMP target** (core affinity, `portMUX` spinlocks, ISR-to-task) | Real-time firmware everywhere; SMP scheduling is a step up from single-core |
| **CAN + error confinement/bus-off**, multi-controller + cross-stack (RTOS↔Linux) interop | Automotive/industrial (AMD/Xilinx industrial; Intel IoT/edge) |
| **Embedded Linux + Yocto/RAUC** (SocketCAN, systemd, A/B OTA) | Linux BSP is huge at both — Intel is a top Yocto contributor; AMD ships Zynq Linux |
| **Edge AI / SIMD** (S3 vector "AI" ISA: on-device anomaly detection / DSP filtering) | Edge inference is a major thrust (Intel OpenVINO/edge; AMD AI engines) |
| **Secure onboarding / BLE provisioning** (sec2/SRP6a/PoP) | Connected-product credibility most candidates lack |
| **Portable C across two ISAs (HAL boundary)** — same codec on Xtensa and (stretch) RISC-V | Shows abstraction + portability judgment |
| **gRPC / protobuf / distributed offline-first** | Modern device↔cloud systems |

---

## Résumé bullets (tighten with real numbers once measured)
- Built a distributed embedded system on a **heterogeneous edge of two ESP32-S3 nodes** (dual-core
  Xtensa LX7 + a **RISC-V ULP** coprocessor) plus an **embedded-Linux Raspberry Pi gateway**,
  integrated over a **multi-controller CAN bus** and Wi-Fi, with a **Flutter** app for BLE provisioning.
- Brought up **MCPWM and the TWAI CAN controller at the register level from the Technical Reference
  Manual** (bit timing, filters, dead-time, hardware brake input) and implemented **bus-off recovery**
  + an **RTC-watchdog fail-safe** state machine.
- Offloaded an **always-on safety monitor to the RISC-V ULP coprocessor** (bare-metal C/asm, RTC ADC)
  that holds actuators safe while the main cores deep-sleep — heterogeneous compute + ultra-low-power.
- Achieved **hard-real-time determinism** by isolating the safety task on its own core and placing its
  ISRs in IRAM; **measured the latency win with the cycle counter**.
- Implemented an **ESP32-S3 Wi-Fi↔CAN bridge** with secure **BLE (sec2) provisioning** and offline-first telemetry buffering.
- Wrote a **portable C protocol codec** shared across both nodes (stretch: the RISC-V ULP too); verified **byte-identical CAN frames** in host unit tests + CI.
- Built a **Linux gateway** (SocketCAN, SQLite, systemd, Yocto) syncing to a **Go/gRPC** cloud over TLS with offline backlog + reconnect.
- *(Stretch)* Ran **on-device anomaly detection on the S3 vector/SIMD ISA** — edge inference at the sensor.

---

## "Walk me through a project" (STAR skeleton)
- **Situation:** offline-capable greenhouse; unreliable Wi-Fi; safety-critical actuators.
- **Task:** reliable distributed control + telemetry that survives network loss, with a clean device-onboarding story.
- **Action:** heterogeneous edge (two ESP32-S3) split by role — connectivity/bridge + BLE provisioning on Node A;
  register-level CAN/MCPWM drivers, a dual-core safety partition, a **RISC-V ULP always-on monitor**, and
  bus-off/RTC-WDT fail-safes on Node B; a Linux gateway with SQLite buffering + gRPC sync.
- **Result:** end-to-end telemetry to the cloud; local automation + safety with no cloud; phone-based onboarding.
  *(Add metrics: bus load %, telemetry rate, ISR latency with/without IRAM, deep-sleep current, reconnect time, soak duration.)*

---

## Proof artifacts to capture (this is what makes it credible)
1. **2–3 min demo video**: provision from the phone → telemetry in the cloud → pull the network → local safety still works → bus-off recovery → deep-sleep with the ULP-RISC-V still guarding.
2. **Logic-analyzer / oscilloscope captures** of the CAN bus, an I²C transaction, and the MCPWM dead-time (shows you actually debugged hardware).
3. **`candump` log** showing both nodes' frames coexisting on the bus (multi-controller interop, undeniable).
4. **Latency table** (ISR with vs without IRAM placement) and a **deep-sleep current capture** (ULP-RISC-V duty cycle).
5. **Green CI badge**: matrix building both ESP32-S3 nodes + running host codec tests.
6. **Architecture diagram** + clean per-component READMEs.
7. **A short "design decisions & tradeoffs" write-up** (CAN vs Wi-Fi; classic CAN vs CAN FD; why the ULP-RISC-V for safety; IRAM/flash-cache determinism; offline-first reconciliation).

---

## Interview deep-dive prep (be ready to defend every layer)
- CAN bit timing: how you picked BRP/segments for 500 kbps and the sample point; arbitration; error frames; error-active→passive→bus-off recovery.
- Classic CAN vs **CAN FD** — when/why; and why *this* build is all classic (both ESP32-S3 TWAI controllers are classic CAN 2.0).
- **Heterogeneous compute / the ULP-RISC-V**: why offload always-on safety to a separate RISC-V core; what RTC peripherals it can reach; how it wakes the SoC; the two-toolchain (Xtensa + `riscv32-esp-elf`) build.
- **FreeRTOS SMP**: core affinity for real-time isolation, `portMUX` spinlocks, cross-core ISR-to-task, priority inversion.
- **Determinism**: IRAM vs flash-cache (XIP) jitter, how you measured it with the cycle counter, cache effects.
- Register-level bring-up: MCPWM (dead-time/brake), the GPIO matrix / IO-MUX, the interrupt matrix, the boot/partition/memory map.
- BLE provisioning security (sec2/SRP6a, PoP) and your factory-reset design.
- Offline-first reconciliation: local (app→hub) vs cloud (backend→hub) authorization.
- *(If you do the stretch)* edge AI on the S3 vector ISA: what the model does, quantization, latency/footprint.

---

## Suggested team build order (de-risks integration)
1. **Dev C M0** test harness (WebSocket endpoint + `vcan0`) — unblocks everyone day one.
2. **Dev A Phase 1** (Wi-Fi telemetry) → first cloud loop = motivating early win.
3. **Dev B** ESP32-S3 CAN bring-up → **Dev C** `can-gateway` → live bus.
4. **Dev A Phase 2** (second node on the bus + Wi-Fi↔CAN bridge) → multi-controller interop demo.
5. **Dev B** safety + ULP-RISC-V (M8–M9) → the autonomous-safety + heterogeneous-compute headline.
6. **Provisioning** (Dev A M7 + Dev C M6 + mobile app) → onboarding story.
7. Robustness, OTA, Yocto/RAUC, edge-AI stretch, security hardening.

> Indicative pace: a strong end-to-end demo (steps 1–4) is achievable in ~6–10 focused
> weeks part-time; safety + ULP + provisioning + polish adds a few more. Lock the **§10/§11
> contracts and the shared codec early** — that's where integration time is won or lost.
