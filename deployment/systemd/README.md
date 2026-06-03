# systemd units

Reference unit files for the Raspberry Pi gateway services. On a Yocto build
these are installed by the recipes in
[yocto/meta-greenhouse](../../yocto/meta-greenhouse/); on a plain Linux dev box
copy them to `/etc/systemd/system/` for testing.

All services start after `network-online.target`, use `Restart=always`,
`RestartSec=5`, and `RequiresMountsFor=/data`, and run as the `greenhouse` user.

| Unit | Notes |
|---|---|
| `websocket-gateway.service` | Wi-Fi/WebSocket transport |
| `can-gateway.service` | CAN transport; requires `can0-up.service` |
| `can0-up.service` | brings up `can0` at 500 kbps before the CAN gateway |
| `dashboard-api.service` | local REST/WebSocket backend for the HMI |
| `cloud-sync.service` | gRPC client to the cloud |
| `local-rules.service` | offline automation |
| `health-agent.service` | system/service health |
| `qt-hmi.service` | kiosk HMI (`eglfs`), starts after `dashboard-api` |

Gateway OS OTA is handled separately by RAUC + hawkBit (Yocto layer).

```bash
sudo cp *.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now can0-up websocket-gateway can-gateway \
    dashboard-api cloud-sync local-rules health-agent qt-hmi
```

See [docs/architecture.md](../../docs/architecture.md) §16.
