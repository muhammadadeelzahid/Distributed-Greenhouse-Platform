-- Greenhouse gateway — local SQLite schema
-- Path: /var/lib/greenhouse/gateway.db (or /data/greenhouse/gateway.db)
-- See docs/architecture.md §8. Tables below marked "draft" are sketched for
-- scaffolding and finalized during implementation.

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

-- §8.1 Device registry (transport-neutral) -----------------------------------
CREATE TABLE IF NOT EXISTS devices (
    device_id         TEXT PRIMARY KEY,
    device_type       TEXT NOT NULL,
    transport         TEXT NOT NULL,            -- 'websocket' | 'can'
    node_id           INTEGER,                  -- CAN node id, when transport='can'
    firmware_version  TEXT,
    status            TEXT NOT NULL,            -- 'online' | 'offline' | ...
    last_seen_ms      INTEGER,
    capabilities_json TEXT,
    created_at_ms     INTEGER,
    updated_at_ms     INTEGER,
    synced            INTEGER DEFAULT 0
);

-- §8.2 Telemetry --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS telemetry (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id     TEXT NOT NULL,
    transport     TEXT,
    timestamp_ms  INTEGER NOT NULL,
    payload_json  TEXT NOT NULL,
    synced        INTEGER DEFAULT 0,
    sync_attempts INTEGER DEFAULT 0,
    created_at_ms INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_telemetry_unsynced ON telemetry(synced, id);
CREATE INDEX IF NOT EXISTS idx_telemetry_device   ON telemetry(device_id, timestamp_ms);

-- §8.3 Commands (status + result embedded) ------------------------------------
CREATE TABLE IF NOT EXISTS commands (
    command_id       TEXT PRIMARY KEY,
    target_device_id TEXT NOT NULL,
    target_transport TEXT,                      -- 'websocket' | 'can'
    source           TEXT NOT NULL,             -- 'local_ui' | 'local_rule' | 'cloud'
    payload_json     TEXT NOT NULL,
    status           TEXT NOT NULL,             -- pending|sent|acked|completed|failed|expired|cancelled|waiting_for_device
    created_at_ms    INTEGER,
    sent_at_ms       INTEGER,
    acked_at_ms      INTEGER,
    completed_at_ms  INTEGER,
    result_json      TEXT,
    synced           INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_commands_pending ON commands(status, target_transport);

-- §8.4 Optional CAN frame debug log (apply a retention limit in production) ----
CREATE TABLE IF NOT EXISTS can_frames (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_ms INTEGER NOT NULL,
    direction    TEXT NOT NULL,                 -- 'rx' | 'tx'
    can_id       INTEGER NOT NULL,
    dlc          INTEGER NOT NULL,
    data_hex     TEXT NOT NULL,
    decoded_type TEXT,
    device_id    TEXT
);

-- Draft tables (named in §8; columns to be finalized) -------------------------
CREATE TABLE IF NOT EXISTS alerts (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    device_id     TEXT,
    severity      TEXT NOT NULL,                -- 'info' | 'warning' | 'critical'
    kind          TEXT NOT NULL,                -- e.g. 'device_offline', 'sensor_stale'
    message       TEXT,
    raised_at_ms  INTEGER NOT NULL,
    acked_at_ms   INTEGER,
    synced        INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS health_reports (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_ms  INTEGER NOT NULL,
    payload_json  TEXT NOT NULL,                -- cpu/ram/disk/temp/services/etc.
    synced        INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ota_status (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp_ms  INTEGER NOT NULL,
    state         TEXT NOT NULL,                -- 'idle'|'downloading'|'installing'|'reboot_required'|'failed'
    current_slot  TEXT,
    version       TEXT,
    detail_json   TEXT,
    synced        INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sync_state (
    key           TEXT PRIMARY KEY,             -- e.g. 'cloud_connected', 'last_sync_ms'
    value         TEXT,
    updated_at_ms INTEGER
);

CREATE TABLE IF NOT EXISTS local_rules (
    rule_id       TEXT PRIMARY KEY,
    name          TEXT,
    enabled       INTEGER DEFAULT 1,
    definition_json TEXT NOT NULL,              -- thresholds / actions
    updated_at_ms INTEGER
);

CREATE TABLE IF NOT EXISTS ui_settings (
    key           TEXT PRIMARY KEY,
    value         TEXT
);
