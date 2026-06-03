# Deployment scripts

Helper scripts for provisioning and operating the gateway.

| Script | Purpose |
|---|---|
| [`can0-up.sh`](can0-up.sh) | Bring up the SocketCAN `can0` interface at 500 kbps (manual / dev use; production uses `can0-up.service`). |

> More provisioning, backup, and database-init scripts are added during
> implementation. See [docs/architecture.md](../../docs/architecture.md) §15–§16.
