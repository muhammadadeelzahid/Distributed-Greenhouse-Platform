CREATE TABLE IF NOT EXISTS gateways (
    gateway_id TEXT PRIMARY KEY,
    software_version TEXT,
    last_seen TIMESTAMP DEFAULT now(),
    status TEXT DEFAULT 'online',
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    gateway_id TEXT REFERENCES gateways(gateway_id),
    device_type TEXT,
    firmware_version TEXT,
    status TEXT,
    last_seen TIMESTAMP,
    capabilities JSONB,
    created_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS telemetry (
    id BIGSERIAL PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    local_id BIGINT NOT NULL,
    timestamp_ms BIGINT NOT NULL,
    payload JSONB NOT NULL,
    received_at TIMESTAMP DEFAULT now(),
    UNIQUE(gateway_id, local_id)
);

CREATE TABLE IF NOT EXISTS commands (
    command_id TEXT PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    target_device_id TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT now(),
    delivered_at TIMESTAMP,
    completed_at TIMESTAMP,
    result JSONB
);

CREATE TABLE IF NOT EXISTS health_reports (
    id BIGSERIAL PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    payload JSONB NOT NULL,
    received_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ota_results (
    id BIGSERIAL PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    update_id TEXT,
    target_version TEXT,
    status TEXT NOT NULL,
    detail TEXT,
    received_at TIMESTAMP DEFAULT now()
);
