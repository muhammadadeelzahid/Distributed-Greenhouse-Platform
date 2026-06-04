# Device Base Platform

Yocto project for the Distributed Greenhouse Platform gateway (full `yocto/` tree:
Poky, BSP layers, and **`meta-device-base`**). The custom layer produces a flashable
image and a signed update bundle that together form a secure, OTA-updatable Linux
platform for Raspberry Pi 4 / 5 with field-update capability.

Project overview: [`../README.md`](../README.md) · Architecture:
[`../docs/architecture.md`](../docs/architecture.md)

---

## Layout

```
yocto/
├── poky/                    # Yocto Project (scarthgap)
├── meta-openembedded/       # OE layers (oe, python, networking, …)
├── meta-raspberrypi/        # Raspberry Pi BSP
├── meta-rauc/               # RAUC update framework
├── meta-device-base/        # custom layer (distro, image, OTA, Wi-Fi)
├── scripts/                 # run_qemu.sh template
├── build-rpi/               # local BitBake dir (gitignored)
├── sstate-cache/            # optional shared cache (gitignored)
└── downloads/               # optional source cache (gitignored)
```

All dependency layers are vendored here — no separate clone step for Poky or meta-oe.

---

## Features

- **A/B atomic updates** — two rootfs slots managed by RAUC; U-Boot picks the
  active slot from `BOOT_ORDER` with a three-strike fallback so a bad update
  automatically rolls back.
- **Signed OTA via Eclipse hawkBit** — bundles are signed at build time and
  delivered through a self-hosted hawkBit server using the DDI HTTP API.
- **Immutable rootfs + persistent overlay** — each slot is mounted read-only;
  `/etc`, `/var`, and `/home` are layered on top using OverlayFS backed by a
  dedicated `data` partition, so user state survives updates without compromising
  the rootfs.
- **systemd-native networking** — `wpa_supplicant@wlan0.service` for Wi-Fi,
  `systemd-networkd` for DHCP/IP, `systemd-resolved` for DNS, and
  `systemd-networkd-wait-online` scoped to `wlan0` so `network-online.target`
  reflects real connectivity.
- **Per-device identity** — each device automatically derives a unique hawkBit
  target name from its hardware serial number on every boot.

---

## Tech stack

| Layer               | Components                                       |
| ------------------- | ------------------------------------------------ |
| Build system        | Yocto Project (Poky, scarthgap)                  |
| Image               | WIC, ext4, vfat, OverlayFS                       |
| Bootloader          | U-Boot, libubootenv                              |
| Update engine       | RAUC, meta-rauc, dm-verity                       |
| OTA server / client | Eclipse hawkBit, rauc-hawkbit-updater            |
| Init / services     | systemd 255+, systemd-networkd, systemd-resolved |
| Wi-Fi               | wpa_supplicant (template unit)                   |
| Remote access       | OpenSSH (key-only)                               |
| Hardware            | Raspberry Pi 4 / 5                               |

---

## Partition layout

Image layout (`meta-device-base/wic/device-base-dual.wks.in`):

| #   | Label     | Type | Mountpoint | Purpose                                      |
| --- | --------- | ---- | ---------- | -------------------------------------------- |
| 1   | `boot`    | FAT  | `/boot`    | Pi firmware, kernel, `boot.scr`, `uboot.env` |
| 2   | `rootfsA` | ext4 | `/`        | RAUC slot A                                  |
| 3   | —         | ext4 | (inactive) | RAUC slot B                                  |
| 4   | `data`    | ext4 | `/data`    | OverlayFS upper dirs + RAUC state            |

`/boot` is auto-mounted at runtime so RAUC can read and update `uboot.env` via
`fw_printenv` / `fw_setenv`.

---

## Setup `build-rpi/`

The build directory is created locally and **not committed** (`build-*/` in the
root [`.gitignore`](../.gitignore)).

From the repository root:

```bash
cd yocto
source poky/oe-init-build-env build-rpi
```

`oe-init-build-env` creates `build-rpi/conf/` (`bblayers.conf`, `local.conf`,
`conf-notes.txt`, `conf-summary.txt`, `templateconf.cfg`). Stay in `build-rpi/`
for the steps below (re-run the `source` line in new shells).

**Register layers** (Poky entries are already in the generated `bblayers.conf`):

```bash
YOCTO_DIR="$(git rev-parse --show-toplevel)/yocto"

bitbake-layers add-layer \
  "${YOCTO_DIR}/meta-raspberrypi" \
  "${YOCTO_DIR}/meta-openembedded/meta-oe" \
  "${YOCTO_DIR}/meta-openembedded/meta-python" \
  "${YOCTO_DIR}/meta-openembedded/meta-networking" \
  "${YOCTO_DIR}/meta-device-base" \
  "${YOCTO_DIR}/meta-rauc"
```

**Optional:** `devtool create-workspace` (scratch layer under `build-rpi/workspace/`).
QEMU smoke test after a build:

```bash
cp scripts/run_qemu.sh build-rpi/ && chmod +x build-rpi/run_qemu.sh
```

See [Configuration](#configuration) and [Secrets](#secrets) before the first `bitbake`.

---

## Build

```bash
cd yocto
source poky/oe-init-build-env build-rpi
bitbake device-base-image     # flashable .wic.bz2
bitbake device-base-bundle    # signed .raucb (OTA delivery)
```

Artifacts:

```
build-rpi/tmp/deploy/images/raspberrypi4-64/
├── device-base-image-raspberrypi4-64.rootfs.wic.bz2
├── device-base-image-raspberrypi4-64.rootfs.wic.bmap
└── device-base-bundle-raspberrypi4-64.raucb
```

Do not commit `build-rpi/tmp/`, `downloads/`, `sstate-cache/`, or `cache/`.

---

## Flash

```bash
lsblk -p -o NAME,SIZE,RM,MODEL,MOUNTPOINT     # find the SD card
sudo umount /dev/sdX*  2>/dev/null || true
sudo wipefs -af /dev/sdX
sudo bmaptool copy \
  build-rpi/tmp/deploy/images/raspberrypi4-64/device-base-image-raspberrypi4-64.rootfs.wic.bz2 \
  /dev/sdX
sync
```

After boot, verify on the Pi:

```bash
cat /etc/issue                       # Device Base Platform <version>
networkctl status wlan0              # routable, online
rauc status                          # slot states
mount | grep /boot                   # /boot must be mounted
```

---

## OTA updates

1. Build a new bundle: `bitbake device-base-image && bitbake device-base-bundle`.
2. In hawkBit:
   - **Upload** → create a Software Module, attach the `.raucb`.
   - **Distributions** → create a Distribution Set referencing the module.
   - **Deployment** → drag the Distribution Set onto the target.
3. Watch on the Pi: `journalctl -u rauc-hawkbit-updater -f`.

The updater downloads, verifies, installs into the inactive slot, and reboots into
the new slot. `rauc-mark-good` runs on first boot to lock the slot in; if it fails
three times, U-Boot rolls back automatically.

`rauc-hawkbit-updater` does not auto-reboot by default. To enable, set in
`config.conf`:

```
post_update_reboot = true
```

---

## Configuration

All build-time settings live in `build-rpi/conf/local.conf`:

```bitbake
DISTRO  = "device-base"
MACHINE = "raspberrypi4-64"
RPI_USE_U_BOOT = "1"
LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
ENABLE_UART = "1"

# Wi-Fi (substituted into wpa_supplicant-wlan0.conf at build time)
UOFM_IDENTITY = "user@example.edu"
UOFM_PASSWORD = "your-campus-password"
HOTSPOT_SSID  = "your-hotspot-ssid"
HOTSPOT_PSK   = "your-hotspot-psk"

# hawkBit
HAWKBIT_SERVER_URL    = "192.168.1.10:8080"
HAWKBIT_GATEWAY_TOKEN = "your-gateway-token"

# Optional: SSH and root password
ROOT_SSH_AUTHORIZED_KEYS = "ssh-ed25519 AAAAC3Nz... user@host"
ROOT_PASSWORD_HASH       = "$6$..."
```

These Wi-Fi variables map to
`meta-device-base/recipes-connectivity/wpa-supplicant/files/wpa_supplicant.conf`
(WPA2-Enterprise plus a personal hotspot fallback). Keep credentials in
`local.conf` only — not in recipes.

---

## Security

### Update integrity

- Every `.raucb` bundle is signed at build time with a development signer key.
- The matching CA certificate is installed at `/etc/rauc/ca.cert.pem` in every
  rootfs slot. RAUC verifies that the bundle’s signer chains to this CA before
  installing.
- Bundles use the **verity** format, so the rootfs image inside the bundle is
  integrity-protected by dm-verity at install time.
- Authentication to the hawkBit server uses a **gateway token** (tenant-wide),
  not a per-target token.

### Hardening

- Rootfs is **read-only**; persistent state goes through the OverlayFS on `/data`.
- SSH password authentication and empty passwords are **disabled**.
- Root password hash and authorized SSH keys are injected at build time via
  `local.conf` so credentials never appear in source control.

---

## Secrets

Local-only files and settings are **not pushed to the git remote**.

| What | Gitignore rule |
|------|----------------|
| `build-rpi/` | Root `.gitignore` (`build-*/`) |
| `meta-device-base/files/rauc-keys/*` | Layer `.gitignore` |
| `meta-device-base/recipes-core/rauc/files/*.pem`, `*.srl` | Layer `.gitignore` |

[`meta-device-base/recipes-core/rauc/files/system.conf`](meta-device-base/recipes-core/rauc/files/system.conf)
is **tracked** in git (RAUC slot layout, not a secret).

### RAUC PKI

Generate once per machine (or copy from a secure store) before
`bitbake device-base-bundle`:

```bash
cd yocto/meta-rauc/scripts && ./openssl-ca.sh

REPO="$(git rev-parse --show-toplevel)"
LAYER="${REPO}/yocto/meta-device-base"
SRC="${REPO}/yocto/meta-rauc/scripts/openssl-ca/dev"

mkdir -p "${LAYER}/files/rauc-keys" "${LAYER}/recipes-core/rauc/files"

cp "${SRC}/private/development-1.key.pem" "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.cert.pem"        "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.csr.pem"         "${LAYER}/files/rauc-keys/"
cp "${SRC}/private/ca.key.pem"            "${LAYER}/files/rauc-keys/development-ca.key.pem"
cp "${SRC}/ca.cert.pem"                   "${LAYER}/recipes-core/rauc/files/"
cp "${SRC}/serial"                        "${LAYER}/recipes-core/rauc/files/ca.cert.srl"
chmod 600 "${LAYER}/files/rauc-keys/"*.key.pem
```

| Path under `meta-device-base/` | Role |
|--------------------------------|------|
| `files/rauc-keys/development-1.key.pem` | Bundle signing key |
| `files/rauc-keys/development-1.cert.pem` | Bundle signing cert |
| `files/rauc-keys/development-ca.key.pem` | CA private key (offline) |
| `recipes-core/rauc/files/ca.cert.pem` | Device keyring → `/etc/rauc/ca.cert.pem` |
| `recipes-core/rauc/files/ca.cert.srl` | OpenSSL CA serial file |

See [`meta-rauc/scripts/README`](meta-rauc/scripts/README) for PKI details.

### `system.conf` (in git)

Shipped at
[`meta-device-base/recipes-core/rauc/files/system.conf`](meta-device-base/recipes-core/rauc/files/system.conf).
Installed on the gateway as `/etc/rauc/system.conf` via `rauc-conf.bbappend`. Defines
A/B slots (`/dev/mmcblk0p2` / `p3`, U-Boot names `A` / `B`), dm-verity bundles, and
`/data/rauc` for update state — must stay aligned with `wic/device-base-dual.wks.in`.
Edit and commit when you change partition layout or the `compatible` string.

Regenerating the CA invalidates OTA on devices already flashed with the old keyring.

---

## meta-device-base layer

```
meta-device-base/
├── conf/distro/device-base.conf            # DISTRO definition
├── files/rauc-keys/                        # RAUC dev PKI (gitignored)
├── recipes-bsp/rpi-u-boot-scr/             # RAUC-aware boot.cmd.in
├── recipes-connectivity/
│   ├── systemd-networkd/                   # 10-wlan0.network + wait-online override
│   └── wpa-supplicant/                     # per-interface config + template unit
├── recipes-core/
│   ├── bundles/device-base-bundle.bb       # signed .raucb recipe
│   ├── images/device-base-image.bb         # main image + postprocess
│   ├── rauc/                               # system.conf (tracked), CA cert (local)
│   └── rauc-hawkbit-identity/              # identity service + config template
└── wic/device-base-dual.wks.in             # A/B + data partition layout
```

Layer-only pointer: [`meta-device-base/README.md`](meta-device-base/README.md).

---

## License

The `meta-device-base` layer is licensed under the MIT License. See
[`meta-device-base/COPYING.MIT`](meta-device-base/COPYING.MIT).

Vendored layers under `yocto/` (Poky, meta-openembedded, meta-raspberrypi,
meta-rauc, and others) carry their own upstream licenses.

## Acknowledgements

- [Yocto Project](https://www.yoctoproject.org/)
- [meta-raspberrypi](https://github.com/agherzan/meta-raspberrypi)
- [RAUC](https://rauc.io/) and [meta-rauc](https://github.com/rauc/meta-rauc)
- [Eclipse hawkBit](https://www.eclipse.org/hawkbit/)
- RAUC and hawkBit example deployments this project is modeled on.
