# Firmware (ESP32 nodes)

ESP-IDF firmware for the greenhouse ESP32 nodes.

**This area is self-contained.** Building it uses only the ESP-IDF toolchain
(`idf.py`) — it does not require, install, or touch the Go cloud backend
(`cloud/`) or the Yocto / Raspberry Pi layer (`yocto/`). You can work entirely
inside `firmware/` and ignore the rest of the repo.

## Layout
- `esp32-websocket-node/` — Wi-Fi node (WebSocket transport)
- `esp32-can-node/` — CAN-bus node (ESP32 TWAI transport)

Each folder is empty for now — drop an ESP-IDF project into it. Typical workflow:

```bash
cd firmware/esp32-websocket-node
idf.py set-target esp32
idf.py build
idf.py -p <PORT> flash monitor
```

Build artifacts (`build/`, `managed_components/`, `sdkconfig`, …) are ignored by
[`.gitignore`](.gitignore) and will never be committed.

Node design and message formats: [docs/architecture.md](../docs/architecture.md) §9–§11.
