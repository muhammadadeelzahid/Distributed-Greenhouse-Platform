# health-agent.service

Reports Raspberry Pi and gateway health into SQLite (uploaded by `cloud-sync`,
surfaced by `dashboard-api`).

**Reports:** CPU / RAM / disk usage, board temperature, network and CAN interface
status, gateway software version, RAUC boot slot, systemd service status,
connected Wi-Fi/CAN node counts, and last cloud-sync time.

> Status: design stub. See [docs/architecture.md](../../docs/architecture.md) §6.7.
