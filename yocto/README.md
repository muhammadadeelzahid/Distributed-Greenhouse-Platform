# Yocto Gateway Image

Yocto project for the Distributed Greenhouse Platform gateway. Builds a secure,
OTA-updatable Linux image for Raspberry Pi 4 / 5 using **`meta-device-base`** with
Poky, BSP, and dependency layers under this directory.

Project overview: [`../README.md`](../README.md) · Architecture:
[`../docs/architecture.md`](../docs/architecture.md)

## Layout

```
yocto/
├── poky/                 # Yocto Project (scarthgap)
├── meta-openembedded/
├── meta-raspberrypi/
├── meta-rauc/
├── meta-device-base/     # custom layer (distro, image, OTA, Wi-Fi)
├── scripts/              # run_qemu.sh template
└── build-rpi/            # local BitBake dir (gitignored)
```

## Features

- **A/B updates (RAUC)** — dual rootfs slots, U-Boot slot selection, automatic rollback
- **Signed OTA (hawkBit)** — `.raucb` bundles signed at build time, DDI delivery
- **Read-only rootfs + OverlayFS** — persistent `/etc`, `/var`, `/home` on `/data`
- **systemd networking** — `wpa_supplicant@wlan0`, `systemd-networkd`, `systemd-resolved`
- **Per-device hawkBit identity** — target name from hardware serial at boot

Partitions (`meta-device-base/wic/device-base-dual.wks.in`): `boot` (FAT),
`rootfsA` / `rootfsB` (ext4 A/B slots), `data` (OverlayFS + RAUC state).

## Setup `build-rpi/`

The build directory is created locally and **not committed** (`build-*/` in the
root [`.gitignore`](../.gitignore)).

```bash
cd yocto
source poky/oe-init-build-env build-rpi
```

`oe-init-build-env` creates `build-rpi/conf/` (`bblayers.conf`, `local.conf`,
`conf-notes.txt`, `conf-summary.txt`, `templateconf.cfg`). Stay in `build-rpi/`
for the steps below (re-run the `source` line in new shells).

**Add layers:**

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

**Append to `build-rpi/conf/local.conf`:**

```bitbake
DISTRO  = "device-base"
MACHINE = "raspberrypi4-64"
RPI_USE_U_BOOT = "1"
LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
ENABLE_UART = "1"

# Wi-Fi, hawkBit, SSH — see Secrets below
```

**Optional:** `devtool create-workspace` (adds `build-rpi/workspace/` for recipe
experiments). QEMU helper: `cp scripts/run_qemu.sh build-rpi/ && chmod +x build-rpi/run_qemu.sh`.

## Build

```bash
cd yocto && source poky/oe-init-build-env build-rpi
bitbake device-base-image
bitbake device-base-bundle
```

Output: `build-rpi/tmp/deploy/images/raspberrypi4-64/` — `.wic.bz2` image and
`.raucb` bundle. Do not commit `build-rpi/tmp/`, `downloads/`, or `sstate-cache/`.

## Flash

```bash
lsblk -p -o NAME,SIZE,RM,MODEL,MOUNTPOINT
sudo umount /dev/sdX*  2>/dev/null || true
sudo wipefs -af /dev/sdX
sudo bmaptool copy \
  build-rpi/tmp/deploy/images/raspberrypi4-64/device-base-image-raspberrypi4-64.rootfs.wic.bz2 \
  /dev/sdX
sync
```

On the Pi: `rauc status`, `networkctl status wlan0`, `mount | grep /boot`.

## OTA

1. `bitbake device-base-image && bitbake device-base-bundle`
2. hawkBit: upload `.raucb` → distribution set → deploy to target
3. On device: `journalctl -u rauc-hawkbit-updater -f`

Bad updates roll back via U-Boot after three failed boots; `rauc-mark-good` marks
a successful slot. Set `post_update_reboot = true` in hawkBit client `config.conf`
to reboot automatically after install.

## Secrets

**Gitignored:** `build-rpi/`, `meta-device-base/files/rauc-keys/*`,
`meta-device-base/recipes-core/rauc/files/*` (see
[`meta-device-base/.gitignore`](meta-device-base/.gitignore)).

### `build-rpi/conf/local.conf`

| Variable | Purpose |
|----------|---------|
| `UOFM_IDENTITY`, `UOFM_PASSWORD` | WPA2-Enterprise Wi-Fi |
| `HOTSPOT_SSID`, `HOTSPOT_PSK` | Hotspot fallback |
| `HAWKBIT_SERVER_URL`, `HAWKBIT_GATEWAY_TOKEN` | OTA server |
| `ROOT_PASSWORD_HASH`, `ROOT_SSH_AUTHORIZED_KEYS` | Root access |

### RAUC PKI (`meta-device-base/`)

Required before the first signed build. Generate with
[`meta-rauc/scripts/openssl-ca.sh`](meta-rauc/scripts/openssl-ca.sh), then copy:

```bash
REPO="$(git rev-parse --show-toplevel)"
LAYER="${REPO}/yocto/meta-device-base"
SRC="${REPO}/yocto/meta-rauc/scripts/openssl-ca/dev"

mkdir -p "${LAYER}/files/rauc-keys" "${LAYER}/recipes-core/rauc/files"

cp "${SRC}/private/development-1.key.pem" "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.cert.pem" "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.csr.pem"  "${LAYER}/files/rauc-keys/"
cp "${SRC}/private/ca.key.pem"     "${LAYER}/files/rauc-keys/development-ca.key.pem"
cp "${SRC}/ca.cert.pem"            "${LAYER}/recipes-core/rauc/files/"
cp "${SRC}/serial"                 "${LAYER}/recipes-core/rauc/files/ca.cert.srl"
chmod 600 "${LAYER}/files/rauc-keys/"*.key.pem
```

#### `recipes-core/rauc/files/system.conf`

This file is **not** produced by `openssl-ca.sh`. It is RAUC’s board-specific
runtime configuration: the `rauc-conf` recipe (via
`recipes-core/rauc/rauc-conf.bbappend`) installs it on the gateway as
`/etc/rauc/system.conf`. RAUC reads it to know which rootfs slots exist, which
block devices back them, and where to store update state.

It must stay aligned with the SD card layout from
`meta-device-base/wic/device-base-dual.wks.in` — slot A on partition 2, slot B
on partition 3, RAUC metadata under `/data/rauc` on the `data` partition.

| Section | Purpose |
|---------|---------|
| `[system]` | `compatible` string (must match bundle metadata), U-Boot bootloader, dm-verity bundles, state directory |
| `[keyring]` | Path to `ca.cert.pem` on the device (trust anchor for signed bundles) |
| `[slot.rootfs.0]` / `[slot.rootfs.1]` | A/B ext4 rootfs partitions and U-Boot `bootname` values (`A` / `B`) |

Create or restore the file at
`meta-device-base/recipes-core/rauc/files/system.conf`:

```ini
[system]
compatible=device-base-raspberrypi4-64
bootloader=uboot
data-directory=/data/rauc
bundle-formats=verity

[keyring]
path=/etc/rauc/ca.cert.pem

[slot.rootfs.0]
device=/dev/mmcblk0p2
type=ext4
bootname=A

[slot.rootfs.1]
device=/dev/mmcblk0p3
type=ext4
bootname=B
```

If you change partition numbering or the `compatible` string in the WIC image or
bundle recipe, update `system.conf` to match or RAUC installs and slot switches
will fail.

Reusing keys: keep the same `files/rauc-keys/` and `recipes-core/rauc/files/`
across builds; regenerating the CA invalidates updates on already-flashed devices.

## License

`meta-device-base` is MIT — [`meta-device-base/COPYING.MIT`](meta-device-base/COPYING.MIT).
Vendored layers (Poky, meta-openembedded, etc.) have their own upstream licenses.
