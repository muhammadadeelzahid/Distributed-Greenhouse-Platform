FULL PRODUCTION-STYLE ARCHITECTURE WITH QT HMI, WIFI, WEBSOCKET, AND CAN

Project goal:
Build an offline-capable distributed embedded system using ESP32 nodes, a Raspberry Pi embedded Linux gateway, a front-facing Qt HMI application, local WebSocket communication, optional CAN bus communication, gRPC communication to the cloud, local SQLite storage, Render cloud hosting, and PostgreSQL on the server.

Updated one-line architecture:

ESP32 nodes
   | 
   | Wi-Fi WebSocket or CAN bus
   v
Raspberry Pi Gateway + Qt HMI + SQLite
   |
   | gRPC over TLS
   v
Render Cloud Backend + PostgreSQL


============================================================
1. HIGH-LEVEL ARCHITECTURE
============================================================

+--------------------------------------------------+
|                  ESP32 Nodes                     |
|--------------------------------------------------|
| Soil sensor node                                 |
| Climate sensor node                              |
| Relay / pump / fan actuator node                 |
| Local safety logic                               |
| Wi-Fi WebSocket client, optional                 |
| CAN interface, optional                          |
| ESP32 TWAI driver if using CAN                   |
+-------------------------+------------------------+
                          |
                          |
          +---------------+---------------+
          |                               |
          | Wi-Fi WebSocket              | CAN bus
          |                               |
          v                               v
+--------------------------------------------------+
|     Raspberry Pi Embedded Linux Gateway + HMI    |
|--------------------------------------------------|
| Yocto Linux                                      |
| systemd services                                 |
| Qt front-facing HMI application                  |
| SQLite local database                            |
| WebSocket gateway service                        |
| CAN gateway service                              |
| Dashboard API service                            |
| Cloud sync service                               |
| Local rules engine                               |
| OTA agent                                        |
| Health agent                                     |
+-------------------------+------------------------+
                          |
                          | gRPC over TLS
                          v
+--------------------------------------------------+
|                 Render Cloud Backend             |
|--------------------------------------------------|
| gRPC gateway API                                 |
| Dashboard/API backend                            |
| PostgreSQL cloud database                        |
| Device management                                |
| OTA campaign management                          |
| Remote command/control                           |
+--------------------------------------------------+


============================================================
2. UPDATED MAIN DESIGN IDEA
============================================================

The Raspberry Pi is not just a bridge.

It is a local-first embedded gateway and local HMI device.

The ESP32 nodes can communicate with the Raspberry Pi in two possible ways:

1. Wi-Fi using WebSocket
2. Wired CAN bus using ESP32 TWAI and Raspberry Pi SocketCAN

This gives two deployment options.

Wi-Fi/WebSocket is useful when:
    ESP32 nodes are physically separated
    wireless installation is easier
    higher-level JSON messages are preferred
    debugging through logs is important
    firmware updates or richer messages may be needed

CAN is useful when:
    reliability is more important than bandwidth
    nodes are close enough for wired communication
    actuator control needs deterministic local communication
    the system should work even if Wi-Fi is unstable
    the design should look more industrial or automotive-style

Recommended practical design:
    Use Wi-Fi/WebSocket for sensor nodes that are far away or easy to deploy wirelessly.
    Use CAN for critical actuator nodes such as pump, fan, relay, valve, and safety-related devices.
    Allow the Raspberry Pi gateway to support both transports at the same time.

Important:
    Qt HMI should not care whether a device came from Wi-Fi or CAN.
    Qt talks only to dashboard-api.service.
    dashboard-api.service reads and writes SQLite.
    websocket-gateway.service and can-gateway.service are responsible for device communication.
    SQLite is the common integration point.


============================================================
3. FINAL SYSTEM OVERVIEW
============================================================

+-----------------------------+
| ESP32 Sensor/Actuator Nodes |
|-----------------------------|
| sensor_task                 |
| actuator_task               |
| heartbeat_task              |
| local safety logic          |
| Wi-Fi WebSocket client      |
| CAN interface, optional     |
+--------------+--------------+
               |
               | Wi-Fi WebSocket or CAN
               v
+--------------------------------------------------+
| Raspberry Pi Yocto Gateway + HMI                 |
|--------------------------------------------------|
| Qt HMI Application                               |
|   - overview screen                              |
|   - device status screen                         |
|   - telemetry graphs                             |
|   - manual control screen                        |
|   - local rules screen                           |
|   - alerts screen                                |
|   - OTA/update screen                            |
|   - cloud status screen                          |
|                                                  |
| dashboard-api.service                            |
|   - local REST API for Qt                        |
|   - local WebSocket event stream for Qt          |
|   - reads/writes SQLite                          |
|                                                  |
| websocket-gateway.service                        |
|   - ESP32 Wi-Fi/WebSocket sessions               |
|   - telemetry receive                            |
|   - command delivery                             |
|   - heartbeat tracking                           |
|                                                  |
| can-gateway.service                              |
|   - CAN frame receive                            |
|   - CAN frame decode/encode                      |
|   - CAN device registration/status               |
|   - CAN command delivery                         |
|   - CAN command acknowledgement tracking         |
|                                                  |
| SQLite local-first database                      |
|   - devices                                      |
|   - telemetry                                    |
|   - commands                                     |
|   - command_results                              |
|   - alerts                                       |
|   - health                                       |
|   - OTA status                                   |
|   - sync state                                   |
|   - local UI settings                            |
|                                                  |
| local-rules.service                              |
|   - offline automation                           |
|   - local command generation                     |
|                                                  |
| cloud-sync.service                               |
|   - gRPC client                                  |
|   - upload backlog                               |
|   - download commands/config                     |
|                                                  |
| health-agent.service                             |
|   - system health                                |
|   - service health                               |
|                                                  |
| ota-agent.service                                |
|   - RAUC OTA                                     |
|   - update status                                |
+----------------+---------------------------------+
                 |
                 | gRPC over TLS
                 v
+--------------------------------------------------+
| Render Cloud Backend                             |
|--------------------------------------------------|
| gRPC Gateway API                                 |
| Dashboard API                                    |
| PostgreSQL                                       |
| Device management                                |
| Remote commands                                  |
| OTA campaign metadata                            |
| Long-term telemetry                              |
+--------------------------------------------------+


============================================================
4. UPDATED RASPBERRY PI MULTI-PROCESS SETUP
============================================================

The Raspberry Pi runs a small number of systemd services.

Services:

1. websocket-gateway.service
2. can-gateway.service
3. dashboard-api.service
4. cloud-sync.service
5. local-rules.service
6. ota-agent.service
7. health-agent.service
8. qt-hmi.service, optional if Qt runs as a managed service

Local database:

/var/lib/greenhouse/gateway.db

If using an immutable root filesystem with a persistent data partition, store it in:

/data/greenhouse/gateway.db

and optionally bind/mount it to:

/var/lib/greenhouse/gateway.db


============================================================
5. UPDATED RASPBERRY PI INTERNAL ARCHITECTURE
============================================================

+--------------------------------------------------+
| Raspberry Pi Gateway + HMI                       |
|--------------------------------------------------|
|                                                  |
|  +-------------------------+                     |
|  | Qt HMI Application      |                     |
|  +-----------+-------------+                     |
|              |                                   |
|              | REST for queries/actions          |
|              | WebSocket for live UI updates     |
|              v                                   |
|  +----------------------------+                  |
|  | dashboard-api.service      |                  |
|  +-------------+--------------+                  |
|                |                                 |
|                | read/write                      |
|                v                                 |
|  +----------------------------+                  |
|  | SQLite local database      |                  |
|  +-------------+--------------+                  |
|                ^                                 |
|                | read/write                      |
|  +-------------+--------------+                  |
|  | websocket-gateway.service  |                  |
|  +-------------+--------------+                  |
|                ^                                 |
|                | Wi-Fi WebSocket                 |
|                |                                 |
|          ESP32 Wi-Fi Nodes                       |
|                                                  |
|  +-------------+--------------+                  |
|  | can-gateway.service        |                  |
|  +-------------+--------------+                  |
|                ^                                 |
|                | SocketCAN / CAN bus             |
|                |                                 |
|          ESP32 CAN Nodes                         |
|                                                  |
|  Other services using SQLite:                    |
|      cloud-sync.service                          |
|      local-rules.service                         |
|      ota-agent.service                           |
|      health-agent.service                        |
|                                                  |
|  cloud-sync.service                              |
|        |                                         |
|        | gRPC over TLS                           |
|        v                                         |
|     Render Cloud                                 |
|                                                  |
+--------------------------------------------------+


============================================================
6. UPDATED SERVICE RESPONSIBILITIES
============================================================

------------------------------------------------------------
6.1 websocket-gateway.service
------------------------------------------------------------

Purpose:
Handles local ESP32 communication over Wi-Fi using WebSocket.

Responsibilities:
    Accept ESP32 WebSocket connections
    Register ESP32 Wi-Fi devices
    Authenticate ESP32 devices using device tokens
    Receive telemetry
    Receive heartbeat messages
    Send commands to ESP32 devices
    Receive command acknowledgements
    Receive command results
    Track online/offline state
    Write all important device data to SQLite
    Read pending commands from SQLite and deliver them to connected ESP32 nodes

Runtime state:
    Maintains an in-memory map:

    device_id -> active WebSocket connection

Example:
    soil-node-001  -> WebSocket connection 1
    climate-node-1 -> WebSocket connection 2

Important:
    The in-memory connection map is only for live WebSocket connections.
    Persistent device state is stored in SQLite.
    Qt should not talk directly to ESP32 nodes.
    Qt creates commands through dashboard-api.service.
    websocket-gateway.service delivers commands to Wi-Fi ESP32 nodes.


------------------------------------------------------------
6.2 can-gateway.service
------------------------------------------------------------

Purpose:
Handles local ESP32 communication over CAN bus using Linux SocketCAN.

Responsibilities:
    Bring up or monitor CAN interface, for example can0
    Receive CAN frames from ESP32 CAN nodes
    Decode CAN frames into internal gateway messages
    Encode gateway commands into CAN frames
    Register CAN devices
    Track CAN device heartbeat/status
    Receive telemetry over CAN
    Send commands over CAN
    Receive command acknowledgements over CAN
    Receive command results over CAN
    Write telemetry, device status, and command results to SQLite
    Read pending commands from SQLite and deliver them to CAN-connected ESP32 nodes

Runtime state:
    Maintains an in-memory map:

    device_id -> CAN node_id
    node_id   -> device status

Example:
    relay-node-001 -> CAN node 0x21
    pump-node-001  -> CAN node 0x22
    fan-node-001   -> CAN node 0x23

Important:
    CAN is message-based, not connection-based.
    There is no persistent socket connection per ESP32 like WebSocket.
    Online/offline status is inferred using heartbeat timeout.
    Persistent device state is stored in SQLite.
    Qt does not directly access CAN.
    Qt creates commands through dashboard-api.service.
    can-gateway.service delivers commands to CAN ESP32 nodes.


------------------------------------------------------------
6.3 dashboard-api.service
------------------------------------------------------------

Purpose:
Acts as the local backend for the Qt HMI.

Responsibilities:
    Expose local REST API for Qt queries and actions
    Expose local WebSocket event stream for live UI updates
    Read latest device state from SQLite
    Read telemetry history from SQLite
    Read alerts, health, OTA status, and cloud status from SQLite
    Write manual control commands into SQLite
    Write local rule changes into SQLite
    Acknowledge alerts
    Hide transport details from Qt

Important:
    dashboard-api.service should expose devices in a transport-neutral way.
    Qt should not need to know whether a device uses Wi-Fi/WebSocket or CAN.
    Device transport can be shown as metadata, but Qt should not directly use the transport.


------------------------------------------------------------
6.4 cloud-sync.service
------------------------------------------------------------

Purpose:
Handles cloud communication with the Render backend using gRPC.

Responsibilities:
    Open secure gRPC connection to Render cloud backend
    Upload unsynced telemetry
    Upload command results
    Upload health reports
    Upload OTA status
    Download cloud commands
    Download cloud configuration updates
    Download OTA metadata
    Handle retry and reconnect logic
    Mark local records as synced after successful upload
    Update cloud connection status in SQLite for Qt HMI visibility

Important:
    This service does not directly talk to ESP32 nodes.
    It does not care whether local devices are Wi-Fi or CAN.
    It communicates through SQLite.


------------------------------------------------------------
6.5 local-rules.service
------------------------------------------------------------

Purpose:
Runs local automation so the system works even without cloud.

Responsibilities:
    Read latest sensor values from SQLite
    Apply local automation rules
    Create local commands
    Write local commands into SQLite
    Let websocket-gateway.service or can-gateway.service deliver those commands
    Store rule evaluation results and alerts in SQLite

Example rules:
    If soil moisture < 30 percent:
        turn pump on for 10 seconds

    If temperature > 30 C:
        turn fan on

    If sensor data is stale:
        raise alert

Important:
    local-rules.service should not send CAN or WebSocket messages directly.
    It should create commands in SQLite.
    The correct transport gateway service should deliver the command.


------------------------------------------------------------
6.6 ota-agent.service
------------------------------------------------------------

Purpose:
Handles Raspberry Pi system OTA updates.

Responsibilities:
    Check for available gateway updates
    Download RAUC bundle
    Verify RAUC bundle signature
    Install update to inactive rootfs slot
    Report update status
    Reboot when required
    Write OTA progress and results to SQLite for Qt HMI visibility

Important:
    This service should be separate because OTA may require elevated permissions.
    Do not put RAUC update logic inside WebSocket or CAN services.
    Qt should not run RAUC directly.
    Qt should request OTA actions through dashboard-api.service.


------------------------------------------------------------
6.7 health-agent.service
------------------------------------------------------------

Purpose:
Reports Raspberry Pi and gateway health.

Responsibilities:
    CPU usage
    RAM usage
    disk usage
    board temperature
    network status
    CAN interface status
    current gateway software version
    RAUC boot slot status
    systemd service status
    number of connected WebSocket ESP32 nodes
    number of active CAN ESP32 nodes
    last cloud sync time
    Qt HMI process health, if managed by systemd

Output:
    Writes health reports to SQLite.
    cloud-sync.service uploads them to Render.
    dashboard-api.service exposes them to Qt.


------------------------------------------------------------
6.8 qt-hmi.service, optional
------------------------------------------------------------

Purpose:
Runs the front-facing Qt application as a managed systemd service.

Responsibilities:
    Start Qt application at boot
    Restart Qt application if it crashes
    Launch full-screen/kiosk HMI
    Connect to local dashboard-api.service
    Display device state, telemetry, alerts, OTA, CAN status, Wi-Fi status, and cloud status
    Send user actions to dashboard-api.service

Example endpoints:
    http://127.0.0.1:8080/api
    ws://127.0.0.1:8080/events


============================================================
7. TRANSPORT SELECTION DESIGN
============================================================

Each device should have a transport type.

Recommended transport types:
    websocket
    can

Add this field to the devices table:

    transport TEXT NOT NULL

Example:

soil-node-001:
    device_type = esp32_sensor
    transport = websocket

relay-node-001:
    device_type = esp32_actuator
    transport = can

climate-node-001:
    device_type = esp32_sensor
    transport = websocket

pump-node-001:
    device_type = esp32_actuator
    transport = can

Design principle:
    The device registry tells the gateway which service should deliver commands.

Command delivery rule:
    If target device transport = websocket:
        websocket-gateway.service sends the command.

    If target device transport = can:
        can-gateway.service sends the command.


============================================================
8. UPDATED SQLITE DATABASE
============================================================

Database path:

/var/lib/greenhouse/gateway.db

or, for persistent data partition:

/data/greenhouse/gateway.db

Purpose:
    Local operational state
    Offline buffering
    Crash recovery
    Command persistence
    Device registry
    OTA status
    Sync status
    Qt HMI data source
    Transport-neutral state for Wi-Fi and CAN devices

SQLite stores:
    devices
    telemetry
    commands
    command_results
    alerts
    health_reports
    ota_status
    sync_state
    local_rules
    ui_settings
    can_frames, optional debug table


------------------------------------------------------------
8.1 updated devices table
------------------------------------------------------------

CREATE TABLE devices (
    device_id TEXT PRIMARY KEY,
    device_type TEXT NOT NULL,
    transport TEXT NOT NULL,
    node_id INTEGER,
    firmware_version TEXT,
    status TEXT NOT NULL,
    last_seen_ms INTEGER,
    capabilities_json TEXT,
    created_at_ms INTEGER,
    updated_at_ms INTEGER,
    synced INTEGER DEFAULT 0
);

Purpose:
    Know which ESP32 devices exist
    Track whether device uses WebSocket or CAN
    Track CAN node ID if using CAN
    Track online/offline state
    Track firmware version
    Track capabilities

Example Wi-Fi device:
{
  "device_id": "soil-node-001",
  "device_type": "esp32_sensor",
  "transport": "websocket",
  "firmware_version": "1.0.0",
  "capabilities": ["temperature", "humidity", "soil_moisture"]
}

Example CAN device:
{
  "device_id": "relay-node-001",
  "device_type": "esp32_actuator",
  "transport": "can",
  "node_id": 33,
  "firmware_version": "1.0.0",
  "capabilities": ["pump_relay", "fan_relay"]
}


------------------------------------------------------------
8.2 telemetry table
------------------------------------------------------------

CREATE TABLE telemetry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id TEXT NOT NULL,
    transport TEXT,
    timestamp_ms INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    synced INTEGER DEFAULT 0,
    sync_attempts INTEGER DEFAULT 0,
    created_at_ms INTEGER NOT NULL
);

Purpose:
    Store sensor readings locally
    Keep data during cloud outage
    Upload later to cloud
    Provide recent values and history to Qt HMI
    Support telemetry from both WebSocket and CAN devices


------------------------------------------------------------
8.3 commands table
------------------------------------------------------------

CREATE TABLE commands (
    command_id TEXT PRIMARY KEY,
    target_device_id TEXT NOT NULL,
    target_transport TEXT,
    source TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at_ms INTEGER,
    sent_at_ms INTEGER,
    acked_at_ms INTEGER,
    completed_at_ms INTEGER,
    result_json TEXT,
    synced INTEGER DEFAULT 0
);

Command statuses:
    pending
    sent
    acked
    completed
    failed
    expired
    cancelled
    waiting_for_device

Command sources:
    local_ui
    local_rule
    cloud

Purpose:
    Store commands from cloud, local UI, or local rules
    Survive reboot before command is delivered
    Track whether ESP32 received and executed command
    Report results to cloud
    Show command state in Qt HMI
    Support both WebSocket and CAN command delivery


------------------------------------------------------------
8.4 optional can_frames debug table
------------------------------------------------------------

CREATE TABLE can_frames (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_ms INTEGER NOT NULL,
    direction TEXT NOT NULL,
    can_id INTEGER NOT NULL,
    dlc INTEGER NOT NULL,
    data_hex TEXT NOT NULL,
    decoded_type TEXT,
    device_id TEXT
);

Purpose:
    Debug CAN traffic
    Keep recent CAN frames for diagnostics
    Help test CAN communication from Qt or logs

Important:
    This table is optional.
    Do not keep unlimited CAN debug logs forever.
    Use a retention limit or disable it in production.


============================================================
9. ESP32 ARCHITECTURE WITH WIFI AND CAN OPTIONS
============================================================

Each ESP32 can be built in one of these modes:

1. Wi-Fi/WebSocket mode
2. CAN mode
3. Hybrid mode, optional advanced version

Recommended first version:
    Use either Wi-Fi/WebSocket or CAN per device.
    Avoid hybrid mode until the basic system works.


------------------------------------------------------------
9.1 ESP32 Wi-Fi/WebSocket node
------------------------------------------------------------

Startup flow:
    1. Boot
    2. Connect to Wi-Fi
    3. Open WebSocket connection to Raspberry Pi
    4. Send register message
    5. Send telemetry periodically
    6. Send heartbeat periodically
    7. Receive commands
    8. Execute actuator commands
    9. Send command acknowledgements and results
    10. Reconnect automatically if disconnected

Recommended FreeRTOS tasks:
    wifi_task
    websocket_task
    sensor_task
    actuator_task
    heartbeat_task
    optional ota_task

Internal queues:
    sensor_task -> telemetry_queue -> websocket_task
    websocket_task -> command_queue -> actuator_task
    actuator_task -> result_queue -> websocket_task


------------------------------------------------------------
9.2 ESP32 CAN node
------------------------------------------------------------

Startup flow:
    1. Boot
    2. Initialize TWAI/CAN driver
    3. Send CAN boot/register frame
    4. Send heartbeat periodically
    5. Send telemetry periodically
    6. Receive command frames from Raspberry Pi
    7. Execute actuator commands
    8. Send command acknowledgements and results
    9. Continue local safety logic even if gateway is offline

Recommended FreeRTOS tasks:
    can_rx_task
    can_tx_task
    sensor_task
    actuator_task
    heartbeat_task
    local_safety_task

Internal queues:
    sensor_task -> telemetry_queue -> can_tx_task
    can_rx_task -> command_queue -> actuator_task
    actuator_task -> result_queue -> can_tx_task

Hardware requirement:
    ESP32 has an internal TWAI controller, but it still needs an external CAN transceiver.

Example transceivers:
    SN65HVD230
    MCP2551
    TJA1050

Raspberry Pi CAN options:
    MCP2515 SPI CAN module
    USB-CAN adapter
    CAN HAT

Linux side:
    Use SocketCAN interface such as can0.


============================================================
10. WEBSOCKET MESSAGE TYPES BETWEEN ESP32 AND RASPBERRY PI
============================================================

Start with JSON messages because they are easy to debug.

Later upgrade:
    protobuf over WebSocket binary frames

Message types:
    register
    register_ack
    telemetry
    heartbeat
    command
    command_ack
    command_result
    config_update
    error


Example register message:

{
  "type": "register",
  "device_id": "soil-node-001",
  "device_type": "esp32_sensor",
  "transport": "websocket",
  "firmware_version": "1.0.0",
  "capabilities": ["temperature", "humidity", "soil_moisture"]
}


Example telemetry message:

{
  "type": "telemetry",
  "device_id": "soil-node-001",
  "timestamp_ms": 1710000000000,
  "payload": {
    "temperature_c": 24.6,
    "humidity_percent": 61.2,
    "soil_moisture_percent": 41.0
  }
}


Example command message:

{
  "type": "command",
  "command_id": "cmd-1001",
  "action": "set_relay",
  "target": "pump",
  "enabled": true,
  "duration_sec": 10
}


============================================================
11. CAN MESSAGE DESIGN
============================================================

CAN frames are small, so do not send large JSON payloads directly over classic CAN.

Recommended first version:
    Use compact binary CAN frames.
    Decode them inside can-gateway.service.
    Convert decoded frames into normal SQLite records.

CAN bus speed:
    Start with 500 kbps.

CAN ID design:

Use 11-bit standard CAN IDs for the first version.

Example CAN ID layout:

Bits:
    10..8 = message class
    7..0  = node_id

Message classes:
    0x100 = register / boot
    0x200 = heartbeat
    0x300 = telemetry
    0x400 = command
    0x500 = command_ack
    0x600 = command_result
    0x700 = error

Examples:
    0x121 = register from node 0x21
    0x221 = heartbeat from node 0x21
    0x321 = telemetry from node 0x21
    0x421 = command to node 0x21
    0x521 = command_ack from node 0x21
    0x621 = command_result from node 0x21


------------------------------------------------------------
11.1 CAN heartbeat frame
------------------------------------------------------------

CAN ID:
    0x200 | node_id

Data bytes:
    byte 0: firmware major
    byte 1: firmware minor
    byte 2: status flags
    byte 3: error flags
    byte 4: uptime low byte
    byte 5: uptime high byte
    byte 6: reserved
    byte 7: reserved

Gateway action:
    update devices.last_seen_ms
    update devices.status = online
    update health/status payload if needed


------------------------------------------------------------
11.2 CAN telemetry frame
------------------------------------------------------------

CAN ID:
    0x300 | node_id

Example for soil sensor:

Data bytes:
    byte 0: telemetry_type
    byte 1: temperature_c scaled
    byte 2: humidity_percent scaled
    byte 3: soil_moisture_percent scaled
    byte 4: battery_percent
    byte 5: status flags
    byte 6: reserved
    byte 7: reserved

Example:
    telemetry_type = 1 means soil/climate telemetry

Gateway action:
    decode frame
    map node_id to device_id
    create telemetry row in SQLite
    set synced = 0
    update devices.last_seen_ms


------------------------------------------------------------
11.3 CAN command frame
------------------------------------------------------------

CAN ID:
    0x400 | node_id

Example command for relay control:

Data bytes:
    byte 0: command_type
    byte 1: command_sequence
    byte 2: target
    byte 3: value
    byte 4: duration low byte
    byte 5: duration high byte
    byte 6: flags
    byte 7: reserved

Example values:
    command_type = 1 means set_relay
    target = 1 means pump
    target = 2 means fan
    value = 0 means off
    value = 1 means on

ESP32 action:
    receive command
    validate command
    send command_ack
    execute command
    send command_result


------------------------------------------------------------
11.4 CAN command acknowledgement frame
------------------------------------------------------------

CAN ID:
    0x500 | node_id

Data bytes:
    byte 0: command_sequence
    byte 1: accepted
    byte 2: error_code
    byte 3 to 7: reserved

Gateway action:
    match command_sequence to command_id
    mark command status = acked or failed


------------------------------------------------------------
11.5 CAN command result frame
------------------------------------------------------------

CAN ID:
    0x600 | node_id

Data bytes:
    byte 0: command_sequence
    byte 1: success
    byte 2: result_code
    byte 3 to 7: optional result data

Gateway action:
    match command_sequence to command_id
    mark command status = completed or failed
    write result_json
    set synced = 0
    dashboard-api.service can push command result event to Qt


============================================================
12. OFFLINE BEHAVIOR WITH WIFI AND CAN
============================================================

------------------------------------------------------------
12.1 Cloud offline
------------------------------------------------------------

If cloud is unavailable:
    Wi-Fi ESP32 nodes continue sending data to Raspberry Pi over WebSocket
    CAN ESP32 nodes continue sending data to Raspberry Pi over CAN
    websocket-gateway.service stores WebSocket telemetry in SQLite
    can-gateway.service stores CAN telemetry in SQLite
    local-rules.service continues automation
    dashboard-api.service continues serving Qt HMI
    Qt HMI shows cloud disconnected status
    cloud-sync.service retries cloud connection
    unsynced telemetry remains in SQLite
    local commands still work
    local dashboard still works

When cloud returns:
    cloud-sync.service reconnects
    uploads unsynced telemetry
    uploads command results
    uploads health reports
    uploads OTA status
    marks records synced
    downloads missed cloud commands/config
    updates sync_state
    dashboard-api.service pushes cloud restored event to Qt


------------------------------------------------------------
12.2 Wi-Fi unavailable but CAN still works
------------------------------------------------------------

If Wi-Fi is unstable:
    WebSocket ESP32 nodes may disconnect
    CAN ESP32 nodes continue working
    Critical actuator nodes on CAN can still receive local commands
    local-rules.service can still control CAN actuators
    Qt HMI shows Wi-Fi node offline status
    Qt HMI can still show CAN node telemetry/status


------------------------------------------------------------
12.3 CAN bus issue but Wi-Fi still works
------------------------------------------------------------

If CAN bus has a problem:
    can-gateway.service detects missing heartbeats
    CAN devices are marked offline after timeout
    WebSocket devices continue working
    Qt HMI shows CAN interface or CAN node fault
    health-agent.service records CAN status
    cloud-sync.service uploads CAN fault when cloud is available


------------------------------------------------------------
12.4 Raspberry Pi reboot
------------------------------------------------------------

If Raspberry Pi reboots:
    systemd restarts services
    SocketCAN interface can0 is brought up
    SQLite still has telemetry, commands, device registry, and sync state
    Qt HMI restarts if configured as qt-hmi.service
    WebSocket ESP32 nodes reconnect
    CAN ESP32 nodes continue sending heartbeats
    cloud-sync.service resumes upload from last unsynced records
    dashboard-api.service resumes local API for Qt


============================================================
13. LOCAL COMMAND DELIVERY LOGIC WITH TWO TRANSPORTS
============================================================

dashboard-api.service or local-rules.service creates a command in SQLite.

commands row includes:

    target_device_id
    target_transport
    status = pending

websocket-gateway.service command loop:

loop:
    read commands where status = pending and target_transport = websocket
    for each command:
        check if target_device_id is connected
        if connected:
            send command over WebSocket
            mark status = sent
            set sent_at_ms
        else:
            keep pending or mark waiting_for_device

can-gateway.service command loop:

loop:
    read commands where status = pending and target_transport = can
    for each command:
        find node_id for target_device_id
        encode command into CAN frame
        send CAN frame on can0
        mark status = sent
        set sent_at_ms

When command_ack arrives:
    mark command status = acked
    set acked_at_ms
    dashboard-api.service can push command ack event to Qt

When command_result arrives:
    mark command status = completed or failed
    store result_json
    set completed_at_ms
    set synced = 0
    dashboard-api.service can push command result event to Qt

Then:
    cloud-sync.service uploads the command result to Render.


============================================================
14. QT HMI APPLICATION DESIGN
============================================================

The Qt application is the user-facing interface.

It should not:
    directly talk to ESP32 nodes
    directly access CAN bus
    directly run RAUC commands
    directly manage cloud gRPC
    directly modify low-level gateway service state
    directly depend on database schema in the production-style version

It should:
    talk to dashboard-api.service
    display local system state
    show transport type for each device
    show Wi-Fi node status
    show CAN node status
    show CAN interface status
    send user actions to dashboard-api.service
    receive live events from dashboard-api.service
    keep working when cloud is offline


Recommended Qt screens:

1. Overview screen
    system status
    cloud connected/disconnected
    CAN interface status
    number of online Wi-Fi ESP32 nodes
    number of online CAN ESP32 nodes
    latest temperature
    latest humidity
    latest soil moisture
    pump/fan/light state
    active alerts

2. Device screen
    device_id
    device type
    transport type
    CAN node_id if applicable
    online/offline
    last seen
    firmware version
    RSSI for Wi-Fi devices
    free heap
    capabilities

3. Telemetry screen
    latest sensor values
    recent history
    simple graphs
    min/max values

4. Manual control screen
    pump on/off
    fan on/off
    light on/off
    valve open/close
    duration-based commands
    command transport shown as Wi-Fi or CAN

5. Rules screen
    soil moisture threshold
    temperature threshold
    fan control rule
    watering duration
    enable/disable automation

6. Alerts screen
    device offline
    sensor stale
    pump command failed
    cloud disconnected
    Wi-Fi node disconnected
    CAN node offline
    CAN interface down
    disk low
    OTA failed

7. OTA/update screen
    current gateway version
    current RAUC slot
    available update
    download status
    install status
    reboot required
    last update result

8. Cloud status screen
    cloud connection state
    last sync time
    unsynced telemetry count
    last upload error
    Render backend status
    gateway registration state

9. Settings screen
    local network info
    CAN bitrate
    CAN interface name
    gateway identity
    display preferences
    local thresholds
    maintenance actions


============================================================
15. YOCTO INTEGRATION
============================================================

In your Yocto layer, add recipes for:

    websocket-gateway
    can-gateway
    dashboard-api
    cloud-sync
    local-rules
    ota-agent
    health-agent
    qt-hmi
    SQLite
    Qt runtime dependencies
    CAN tools
    systemd service files
    configuration files

Useful packages:
    sqlite
    can-utils
    iproute2
    systemd
    qtbase
    qtdeclarative, if using QML
    qtwayland or eglfs support depending on display stack

Example layer structure:

meta-device-base/
  recipes-greenhouse/
    websocket-gateway/
      websocket-gateway_1.0.bb
      files/websocket-gateway.service

    can-gateway/
      can-gateway_1.0.bb
      files/can-gateway.service
      files/20-can0.network

    dashboard-api/
      dashboard-api_1.0.bb
      files/dashboard-api.service

    cloud-sync/
      cloud-sync_1.0.bb
      files/cloud-sync.service

    local-rules/
      local-rules_1.0.bb
      files/local-rules.service

    ota-agent/
      ota-agent_1.0.bb
      files/ota-agent.service

    health-agent/
      health-agent_1.0.bb
      files/health-agent.service

    qt-hmi/
      qt-hmi_1.0.bb
      files/qt-hmi.service

Runtime paths:

    /etc/greenhouse/gateway.conf
    /var/lib/greenhouse/gateway.db
    /var/log/greenhouse/
    /data/greenhouse/gateway.db

For immutable rootfs:
    put persistent database under /data
    optionally bind/mount it to /var/lib/greenhouse


============================================================
16. systemd SERVICE MODEL
============================================================

Service relationship:

network-online.target
        |
        +--> websocket-gateway.service
        +--> can-gateway.service
        +--> dashboard-api.service
        +--> cloud-sync.service
        +--> local-rules.service
        +--> health-agent.service
        +--> ota-agent.service
        +--> qt-hmi.service

Important service behavior:
    Restart=always
    RestartSec=5
    After=network-online.target
    Wants=network-online.target
    RequiresMountsFor=/data

CAN interface setup:
    can0 should be configured before can-gateway.service starts.

Example command manually:

    ip link set can0 up type can bitrate 500000

Production setup:
    Configure can0 through systemd-networkd or a dedicated systemd service.


Example can-gateway.service:

[Unit]
Description=Greenhouse CAN Gateway
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/data

[Service]
ExecStart=/usr/bin/can-gateway --config /etc/greenhouse/gateway.conf --interface can0
Restart=always
RestartSec=5
User=greenhouse
Group=greenhouse

[Install]
WantedBy=multi-user.target


Example websocket-gateway.service:

[Unit]
Description=Greenhouse WebSocket Gateway
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/data

[Service]
ExecStart=/usr/bin/websocket-gateway --config /etc/greenhouse/gateway.conf
Restart=always
RestartSec=5
User=greenhouse
Group=greenhouse

[Install]
WantedBy=multi-user.target


Example dashboard-api.service:

[Unit]
Description=Greenhouse Local Dashboard API
After=network-online.target
Wants=network-online.target
RequiresMountsFor=/data

[Service]
ExecStart=/usr/bin/dashboard-api --config /etc/greenhouse/gateway.conf
Restart=always
RestartSec=5
User=greenhouse
Group=greenhouse

[Install]
WantedBy=multi-user.target


Example qt-hmi.service:

[Unit]
Description=Greenhouse Qt HMI
After=dashboard-api.service
Wants=dashboard-api.service

[Service]
ExecStart=/usr/bin/greenhouse-hmi
Restart=always
RestartSec=5
User=greenhouse
Group=greenhouse
Environment=QT_QPA_PLATFORM=eglfs

[Install]
WantedBy=multi-user.target


============================================================
17. UPDATED DATA FLOWS
============================================================

------------------------------------------------------------
17.1 Wi-Fi telemetry flow
------------------------------------------------------------

ESP32 sensor reads data
        |
        v
ESP32 sends WebSocket telemetry
        |
        v
websocket-gateway.service receives it
        |
        v
SQLite telemetry row created with synced = 0
        |
        v
dashboard-api.service pushes live telemetry update to Qt HMI
        |
        v
cloud-sync.service reads unsynced telemetry
        |
        v
cloud-sync.service sends UploadTelemetry() over gRPC
        |
        v
Render backend stores in PostgreSQL
        |
        v
cloud-sync.service marks local rows synced = 1


------------------------------------------------------------
17.2 CAN telemetry flow
------------------------------------------------------------

ESP32 sensor reads data
        |
        v
ESP32 sends CAN telemetry frame
        |
        v
can-gateway.service receives frame from can0
        |
        v
can-gateway.service decodes frame
        |
        v
SQLite telemetry row created with synced = 0
        |
        v
dashboard-api.service pushes live telemetry update to Qt HMI
        |
        v
cloud-sync.service uploads telemetry to Render using gRPC
        |
        v
Render backend stores in PostgreSQL


------------------------------------------------------------
17.3 Qt manual command flow
------------------------------------------------------------

User taps "turn pump on" in Qt
        |
        v
Qt sends POST /api/commands to dashboard-api.service
        |
        v
dashboard-api.service validates and creates command in SQLite
        |
        v
Command target device transport is checked
        |
        +--> If target_transport = websocket:
        |       websocket-gateway.service sends command to ESP32
        |
        +--> If target_transport = can:
                can-gateway.service sends CAN command frame to ESP32
        |
        v
ESP32 executes command
        |
        v
ESP32 sends command result using its transport
        |
        v
SQLite stores result
        |
        v
dashboard-api.service updates Qt
        |
        v
cloud-sync.service uploads command result to Render


------------------------------------------------------------
17.4 Local automation flow
------------------------------------------------------------

ESP32 sends soil moisture = 20 percent
        |
        v
SQLite stores telemetry
        |
        v
dashboard-api.service updates Qt HMI
        |
        v
local-rules.service detects low moisture
        |
        v
local-rules.service writes pump command into commands table
        |
        v
Target pump device uses CAN
        |
        v
can-gateway.service sends CAN command to pump-node-001
        |
        v
ESP32 turns pump on
        |
        v
ESP32 reports command result
        |
        v
SQLite stores result
        |
        v
dashboard-api.service pushes command result to Qt
        |
        v
cloud-sync.service uploads result later


============================================================
18. UPDATED SECURITY DESIGN
============================================================

------------------------------------------------------------
18.1 ESP32 Wi-Fi/WebSocket to Raspberry Pi
------------------------------------------------------------

First version:
    WebSocket with device token

Later version:
    WebSocket over TLS
    per-device credentials
    message authentication

Recommended first version:
    Use per-device token in register message.
    Bind WebSocket service to the local LAN interface only.
    Reject unknown device IDs.


------------------------------------------------------------
18.2 ESP32 CAN to Raspberry Pi
------------------------------------------------------------

CAN does not provide built-in authentication.

First version:
    Use fixed known CAN node IDs.
    Reject unknown node IDs.
    Keep CAN bus physically protected.
    Use heartbeat timeout.
    Use command sequence numbers.

Later version:
    Add lightweight message authentication if needed.
    Add per-node shared keys if payload space allows.
    Use CAN FD if larger authenticated payloads are needed.


------------------------------------------------------------
18.3 Qt to dashboard-api.service
------------------------------------------------------------

If Qt runs locally on the same Raspberry Pi:
    bind dashboard-api.service to 127.0.0.1
    Qt connects to localhost only

Recommended first version:
    Qt and dashboard-api.service both run locally
    dashboard-api.service listens on 127.0.0.1


------------------------------------------------------------
18.4 Raspberry Pi to Render
------------------------------------------------------------

Use:
    gRPC over TLS
    gateway token or certificate

Later production-style:
    mTLS

Production concept:
    each gateway has a unique identity
    each gateway authenticates to cloud
    cloud rejects unknown gateways


============================================================
19. UPDATED IMPLEMENTATION STAGES
============================================================

------------------------------------------------------------
Stage 1: Minimal Wi-Fi end-to-end system
------------------------------------------------------------

Build:
    ESP32 WebSocket client
    Raspberry Pi websocket-gateway.service
    SQLite database
    Render gRPC backend
    PostgreSQL database

Goal:
    ESP32 telemetry reaches cloud database.

Flow:
    ESP32 -> WebSocket -> Pi -> SQLite -> gRPC -> Render -> PostgreSQL


------------------------------------------------------------
Stage 2: Add CAN path
------------------------------------------------------------

Build:
    ESP32 CAN node using TWAI
    Raspberry Pi CAN interface using SocketCAN
    can-gateway.service
    CAN frame decoder/encoder
    CAN telemetry storage in SQLite
    CAN command delivery

Goal:
    CAN ESP32 nodes can send telemetry and receive commands.

Flow:
    ESP32 -> CAN -> can-gateway.service -> SQLite


------------------------------------------------------------
Stage 3: Add Qt HMI with local dashboard backend
------------------------------------------------------------

Build:
    dashboard-api.service
    Qt HMI application
    REST API for Qt
    WebSocket event stream for Qt

Goal:
    Local HMI displays gateway state and sends manual commands.

Flow:
    Qt -> dashboard-api.service -> SQLite -> websocket-gateway.service or can-gateway.service -> ESP32


------------------------------------------------------------
Stage 4: Split Raspberry Pi into production-style services
------------------------------------------------------------

Split into:
    websocket-gateway.service
    can-gateway.service
    dashboard-api.service
    cloud-sync.service
    local-rules.service
    health-agent.service

Goal:
    Multi-process production-style gateway with Qt HMI.


------------------------------------------------------------
Stage 5: Add offline and sync robustness
------------------------------------------------------------

Add:
    sync retry
    sync attempts
    batch uploads
    command status tracking
    WebSocket offline detection
    CAN heartbeat timeout
    local rules
    local dashboard offline mode
    cloud disconnected UI state

Goal:
    Gateway and Qt HMI work without cloud.


------------------------------------------------------------
Stage 6: Add OTA
------------------------------------------------------------

Add:
    ota-agent.service
    RAUC integration
    cloud update metadata
    OTA status reporting
    rollback reporting
    Qt OTA status screen

Goal:
    Production-style update system.


------------------------------------------------------------
Stage 7: Improve security
------------------------------------------------------------

Add:
    WebSocket device tokens
    CAN known-node validation
    gateway identity
    TLS
    mTLS later
    secure credential storage
    localhost-only dashboard API for Qt
    authentication if dashboard API is exposed over LAN


============================================================
20. WHY THE UPDATED ARCHITECTURE IS STRONG
============================================================

This design demonstrates:

    distributed system design
    embedded Linux services
    WebSocket device communication
    CAN bus device communication
    SocketCAN integration
    ESP32 TWAI usage
    offline-first local storage
    multi-process systemd architecture
    gRPC cloud communication
    cloud backend deployment
    PostgreSQL server-side storage
    Qt front-facing HMI design
    local UI backend design
    OTA readiness
    fault isolation
    production-style reliability

Key design choices:

    ESP32 uses WebSocket when wireless communication and flexible messages are useful.
    ESP32 uses CAN when reliable wired control is more important.
    Raspberry Pi uses SQLite because it needs local persistence and offline buffering.
    Raspberry Pi uses separate WebSocket and CAN gateway services for clean transport separation.
    Qt HMI uses dashboard-api.service instead of directly accessing ESP32, CAN, WebSocket, or SQLite.
    Dashboard API uses REST for queries/actions and WebSocket for live UI updates.
    Raspberry Pi uses gRPC to cloud because it gives typed service-to-service communication.
    Render hosts the backend because it is simple for deployment.
    PostgreSQL stores long-term server-side data.
    RAUC handles robust A/B OTA updates on the gateway.


============================================================
21. FINAL UPDATED SUMMARY
============================================================

Final architecture:

ESP32 nodes
   |
   +-- Wi-Fi/WebSocket
   |       |
   |       v
   |   websocket-gateway.service
   |
   +-- CAN bus
           |
           v
       can-gateway.service

Both gateway services write into:

SQLite local-first database

Then local services use SQLite:

    dashboard-api.service
    local-rules.service
    cloud-sync.service
    health-agent.service
    ota-agent.service

Qt HMI talks only to:

    dashboard-api.service

Cloud communication:

    cloud-sync.service -> gRPC over TLS -> Render Backend -> PostgreSQL

Main Wi-Fi telemetry flow:

    ESP32 -> WebSocket -> websocket-gateway.service -> SQLite -> dashboard-api.service -> Qt HMI
    ESP32 -> WebSocket -> websocket-gateway.service -> SQLite -> cloud-sync.service -> gRPC -> Render -> PostgreSQL

Main CAN telemetry flow:

    ESP32 -> CAN -> can-gateway.service -> SQLite -> dashboard-api.service -> Qt HMI
    ESP32 -> CAN -> can-gateway.service -> SQLite -> cloud-sync.service -> gRPC -> Render -> PostgreSQL

Main local UI command flow:

    Qt HMI -> dashboard-api.service -> SQLite
        -> websocket-gateway.service -> WebSocket -> ESP32

    or

    Qt HMI -> dashboard-api.service -> SQLite
        -> can-gateway.service -> CAN -> ESP32

Main cloud command flow:

    Dashboard -> Render -> PostgreSQL -> gRPC -> cloud-sync.service -> SQLite
        -> websocket-gateway.service or can-gateway.service -> ESP32

Offline mode:

    Cloud offline:
        ESP32 nodes still communicate with Raspberry Pi.
        Wi-Fi nodes use WebSocket.
        CAN nodes use CAN.
        SQLite stores all local data.
        Qt HMI continues working locally.
        local-rules.service continues automation.
        cloud-sync.service uploads backlog later.

This is a realistic production-style embedded Linux distributed system with a local Qt HMI, Wi-Fi/WebSocket support, CAN bus support, offline capability, and cloud synchronization.