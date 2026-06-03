# can-gateway.service

Handles local ESP32 communication over CAN bus using Linux SocketCAN (e.g. `can0`).

**Responsibilities**
- Bring up / monitor the CAN interface
- Receive and decode CAN frames; encode gateway commands into frames
- Register CAN devices; infer online/offline via heartbeat timeout
- Write telemetry / status / command results to SQLite
- Deliver `pending` commands with `target_transport = can`

**Runtime state:** `device_id -> CAN node_id`, `node_id -> status`.

CAN is message-based (no persistent socket per node). 500 kbps, 11-bit IDs
(`0x100` register … `0x600` command_result).

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.2, §11.
