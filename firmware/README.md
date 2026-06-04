# Firmware (edge nodes)

Firmware for the greenhouse edge MCUs. Two different vendors/architectures on purpose:

- **`esp32-hybrid-node/`** — Espressif **ESP32** (Xtensa), **ESP-IDF + FreeRTOS**,
  **dual-transport** node: Wi-Fi **WebSocket/JSON** + **CAN/TWAI** with a Wi-Fi↔CAN
  bridge, plus BLE mobile-app provisioning. → [plan](../docs/plan-dev-a-esp32-hybrid-node.md)
- **`stm32-can-node/`** — ST **STM32** (ARM Cortex-M), bare-metal + **FreeRTOS**,
  actuator node (**STM32F407**, bxCAN classic CAN 2.0). → [plan](../docs/plan-dev-b-stm32-can-actuator-node.md)

**This area is self-contained.** It does not require, install, or touch the Go cloud
backend (`cloud/`) or the Yocto / Raspberry Pi layer (`yocto/`). The two nodes share a
small **portable, vendor-neutral C core** (data model + message codec + command state
machine); each MCU adds only a thin platform adapter.

## Build — ESP32 node (ESP-IDF)
```bash
cd firmware/esp32-hybrid-node
idf.py set-target esp32
idf.py build
idf.py -p <PORT> flash monitor
```

## Build — STM32 node (ARM cross-toolchain)
Init/clock/pin config generated with **STM32CubeMX**, but built headlessly (CI-friendly)
with **CMake + `arm-none-eabi-gcc`**, flashed/debugged with **OpenOCD + ST-Link** over SWD:
```bash
cd firmware/stm32-can-node
cmake -B build -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi.cmake
cmake --build build
openocd -f interface/stlink.cfg -f target/stm32<family>.cfg \
  -c "program build/stm32-can-node.elf verify reset exit"
```

Build artifacts (`build/`, `managed_components/`, `sdkconfig`, CubeIDE `Debug/`, `*.elf`,
`*.map`, …) are ignored by [`.gitignore`](.gitignore) and will never be committed.

Node design and message formats: [docs/architecture.md](../docs/architecture.md) §9–§11
(the CAN protocol in §11 is vendor-neutral — it applies to the STM32 node unchanged).
