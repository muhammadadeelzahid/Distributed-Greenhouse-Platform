# Firmware (ESP32 nodes)

ESP32 sensor/actuator firmware for the greenhouse platform. The firmware is
maintained in a **separate repository** and is intentionally not vendored here:

- **ESP32-Industrial-IoT-Edge-Node** — https://github.com/ryanamjad/ESP32-Industrial-IoT-Edge-Node

Two node variants match the two local transports in the
[architecture](../docs/architecture.md):

## esp32-websocket-node
Wi-Fi node that connects to the gateway over a WebSocket and exchanges JSON
messages (`register`, `telemetry`, `heartbeat`, `command`, `command_ack`,
`command_result`). FreeRTOS tasks: `wifi_task`, `websocket_task`, `sensor_task`,
`actuator_task`, `heartbeat_task`.

## esp32-can-node
Wired node that talks to the gateway over CAN using the ESP32 TWAI controller
plus an external transceiver (e.g. SN65HVD230). Compact binary frames, 500 kbps,
11-bit IDs (`0x100` register … `0x600` command_result). FreeRTOS tasks:
`can_rx_task`, `can_tx_task`, `sensor_task`, `actuator_task`, `heartbeat_task`,
`local_safety_task`.

See [docs/architecture.md](../docs/architecture.md) §9–§11 for message formats.
