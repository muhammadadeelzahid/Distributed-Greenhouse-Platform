# Yocto Gateway Image

Self-contained Yocto project for the Distributed Greenhouse Platform gateway.
It builds a secure, OTA-updatable Linux image for Raspberry Pi 4 / 5 using the
custom **`meta-device-base`** layer together with Poky, BSP, and dependency
layers vendored under this directory.

Part of the monorepo: [`../README.md`](../README.md) · Architecture:
[`../docs/architecture.md`](../docs/architecture.md)

---

## Project layout

```
yocto/
├── poky/                    # Yocto Project (scarthgap)
├── meta-openembedded/       # OE layers (oe, python, networking, …)
├── meta-raspberrypi/        # Raspberry Pi BSP
├── meta-rauc/               # RAUC update framework
├── meta-device-base/        # Custom layer (distro, image, OTA, networking)
├── scripts/                 # Helper scripts (e.g. run_qemu.sh template)
├── build-rpi/               # BitBake build directory (local, gitignored)
├── sstate-cache/            # Shared state cache (local, gitignored)
└── downloads/               # Source tarballs (local, gitignored)
```

The **`meta-device-base`** layer produces a flashable image and a signed update
bundle that together form a complete embedded Linux platform with field-update
capability.

---

## Features

- **A/B atomic updates** — two rootfs slots managed by RAUC; U-Boot picks the
  active slot from `BOOT_ORDER` with a three-strike fallback so a bad update
  automatically rolls back.
- **Signed OTA via Eclipse hawkBit** — bundles are signed at build time and
  delivered through a self-hosted hawkBit server using the DDI HTTP API.
- **Immutable rootfs + persistent overlay** — each slot is mounted read-only;
  `/etc`, `/var`, and `/home` are layered on top using OverlayFS backed by a
  dedicated `data` partition, so user state survives updates without
  compromising the rootfs.
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

## Getting started

All dependency layers are already vendored under `yocto/`. The **`build-rpi/`**
directory is your local BitBake build tree. It is **not committed** (excluded
by `build-*/` in the root [`.gitignore`](../.gitignore)).

When setup is complete, the top of `build-rpi/` looks like this:

```
build-rpi/
├── conf/
│   ├── bblayers.conf       # layer paths (edit after init)
│   ├── conf-notes.txt      # Poky help text (auto-generated)
│   ├── conf-summary.txt    # build summary (auto-generated)
│   ├── local.conf          # machine, distro, secrets (edit after init)
│   └── templateconf.cfg    # template pointer (auto-generated)
├── workspace/              # devtool scratch layer (optional)
│   ├── conf/
│   │   └── layer.conf
│   └── README
├── bitbake-cookerdaemon.log  # appears after first bitbake run
└── run_qemu.sh             # optional QEMU helper (copy from scripts/)
```

Additional directories (`tmp/`, `cache/`, `downloads/`, `sstate-cache/`) are
created automatically during builds — see [Build](#build).

### Step 1 — Create `yocto/build-rpi/` and `conf/`

From the repository root, run Yocto's environment initializer. It creates
`yocto/build-rpi/` and populates `conf/` from the Poky templates in
`poky/meta-poky/conf/templates/default/`:

```bash
cd yocto
source poky/oe-init-build-env build-rpi
```

| File | Location | How it is created | Action |
|------|----------|-------------------|--------|
| `bblayers.conf` | `build-rpi/conf/` | Copied from Poky template | Edit — add project layers (step 2) |
| `local.conf` | `build-rpi/conf/` | Copied from Poky template | Edit — set distro, machine, secrets (steps 3–4) |
| `conf-notes.txt` | `build-rpi/conf/` | Copied from Poky template | Leave as-is (informational) |
| `conf-summary.txt` | `build-rpi/conf/` | Copied from Poky template | Leave as-is (informational) |
| `templateconf.cfg` | `build-rpi/conf/` | Written by `oe-init-build-env` | Leave as-is (points at the template used) |

Your shell is now in `yocto/build-rpi/` with BitBake environment variables set.
Run all remaining setup commands from this directory (or re-source the command
above before each build session).

### Step 2 — Register layers in `build-rpi/conf/bblayers.conf`

Add the gateway layers on top of the default Poky entries already in
`bblayers.conf`:

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

This updates `build-rpi/conf/bblayers.conf` in place.

### Step 3 — Configure `build-rpi/conf/local.conf`

Append the following to `build-rpi/conf/local.conf`:

```bitbake
DISTRO  = "device-base"
MACHINE = "raspberrypi4-64"
RPI_USE_U_BOOT = "1"
LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
ENABLE_UART = "1"
```

### Step 4 — Add secrets to `build-rpi/conf/local.conf`

Add Wi-Fi, hawkBit, SSH, and root-password variables to the same file. See
[Secrets](#secrets).

### Before building — RAUC PKI in `meta-device-base/`

The `.pem`, `.srl`, and `system.conf` files under `meta-device-base/files/rauc-keys/`
and `meta-device-base/recipes-core/rauc/files/` must be created once per machine
(or copied from a secure store) before the first image build. See
[RAUC signing PKI](#rauc-signing-pki-pem-srl-systemconf) for generation and
placement instructions.

### Step 5 — Create `build-rpi/workspace/` (optional)

The workspace layer holds temporary recipes while using `devtool`. Create it
when you need to patch or experiment on recipes; it is not required for a
standard image build.

From `build-rpi/` (with the build environment sourced):

```bash
devtool create-workspace
```

| File | Location | How it is created | Action |
|------|----------|-------------------|--------|
| `layer.conf` | `build-rpi/workspace/conf/` | Written by `devtool create-workspace` | Leave as-is unless customizing devtool |
| `README` | `build-rpi/workspace/` | Written by `devtool create-workspace` | Informational |

This also adds `build-rpi/workspace` to `conf/bblayers.conf` automatically.

### Step 6 — Add `build-rpi/run_qemu.sh` (optional)

For QEMU smoke-testing after a build, copy the helper script from this repo:

```bash
cp scripts/run_qemu.sh build-rpi/run_qemu.sh
chmod +x build-rpi/run_qemu.sh
```

Run it from `build-rpi/` after `bitbake device-base-image` completes:

```bash
./run_qemu.sh
```

### Step 7 — `bitbake-cookerdaemon.log`

| File | Location | How it is created | Action |
|------|----------|-------------------|--------|
| `bitbake-cookerdaemon.log` | `build-rpi/` | Created on the first `bitbake` run | Gitignored; safe to delete |

No manual setup is needed — proceed to [Build](#build).

---

## Build

```bash
cd yocto
source poky/oe-init-build-env build-rpi
bitbake device-base-image     # flashable .wic.bz2
bitbake device-base-bundle    # signed .raucb (for OTA delivery)
```

Artifacts:

```
build-rpi/tmp/deploy/images/raspberrypi4-64/
├── device-base-image-raspberrypi4-64.rootfs.wic.bz2
├── device-base-image-raspberrypi4-64.rootfs.wic.bmap
└── device-base-bundle-raspberrypi4-64.raucb
```

**Build artifacts (generated, never commit):** `tmp/`, `downloads/`,
`sstate-cache/`, `cache/`, `workspace/`, and `bitbake-cookerdaemon.log` under
`build-rpi/`. Shared `sstate-cache/` and `downloads/` directories at the
`yocto/` level may also be created and are likewise gitignored.

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

The updater downloads, verifies, installs into the inactive slot, and the
system reboots into the new slot. `rauc-mark-good` runs on first boot to lock
the slot in; if it fails three times, U-Boot rolls back automatically.

`rauc-hawkbit-updater` does not auto-reboot by default. To enable, set in
`config.conf`:

```
post_update_reboot = true
```

---

## Configuration

All build-time configuration lives in `build-rpi/conf/local.conf`:

```bitbake
DISTRO  = "device-base"
MACHINE = "raspberrypi4-64"
RPI_USE_U_BOOT = "1"

# Wi-Fi credentials baked into the image
UOFM_IDENTITY = "user@example.edu"
UOFM_PASSWORD = "your-campus-password"
HOTSPOT_SSID  = "your-hotspot-ssid"
HOTSPOT_PSK   = "your-hotspot-psk"

# hawkBit server
HAWKBIT_SERVER_URL    = "192.168.1.10:8080"
HAWKBIT_GATEWAY_TOKEN = "your-gateway-token"

# Optional: SSH and root password
ROOT_SSH_AUTHORIZED_KEYS = "ssh-ed25519 AAAAC3Nz... user@host"
ROOT_PASSWORD_HASH       = "$6$..."
```

These variables are substituted into
`meta-device-base/recipes-connectivity/wpa-supplicant/files/wpa_supplicant.conf`
at image build time (WPA2-Enterprise campus network plus a personal hotspot
fallback).

---

## Secrets

The files and settings below are **local only** and are **not pushed to the git
remote**. Keep them on each developer machine or build host.

### What git excludes

| Location | Rule | Purpose |
|----------|------|---------|
| Repository root [`.gitignore`](../.gitignore) | `build-*/`, `downloads/`, `sstate-cache/`, `tmp-glibc/` | Yocto build trees and caches |
| [`meta-device-base/.gitignore`](meta-device-base/.gitignore) | `files/rauc-keys/*`, `recipes-core/rauc/files/*` | RAUC signing PKI and keyring |

### Credentials in `build-rpi/conf/local.conf`

| Variable | Used for |
|----------|----------|
| `ROOT_PASSWORD_HASH` | Root password hash baked into the gateway image |
| `ROOT_SSH_AUTHORIZED_KEYS` | SSH public key injected into `/root/.ssh/authorized_keys` |
| `UOFM_IDENTITY`, `UOFM_PASSWORD` | WPA2-Enterprise Wi-Fi (campus network) |
| `HOTSPOT_SSID`, `HOTSPOT_PSK` | Personal hotspot fallback network |
| `HAWKBIT_SERVER_URL` | hawkBit update server address |
| `HAWKBIT_GATEWAY_TOKEN` | hawkBit gateway authentication token |

### RAUC signing PKI (`.pem`, `.srl`, `system.conf`)

These files live under `meta-device-base/` and are **gitignored**. They must
exist on your machine before `bitbake device-base-image` or
`bitbake device-base-bundle` can produce signed, verifiable updates.

Target layout inside the layer:

```
meta-device-base/
├── files/rauc-keys/
│   ├── development-1.key.pem      # bundle signing private key
│   ├── development-1.cert.pem     # bundle signing certificate
│   ├── development-1.csr.pem      # CSR (intermediate artifact)
│   └── development-ca.key.pem     # CA private key (keep secure)
└── recipes-core/rauc/
    ├── rauc-conf.bbappend         # tracked — points rauc-conf at files/ below
    └── files/
        ├── ca.cert.pem            # keyring installed on device (/etc/rauc/)
        ├── ca.cert.srl            # OpenSSL CA serial file
        └── system.conf            # RAUC A/B slot layout for this board
```

The bundle recipe (`recipes-core/bundles/device-base-bundle.bb`) reads the
signing key and cert from `files/rauc-keys/`. The `rauc-conf` bbappend installs
`ca.cert.pem` and `system.conf` into the rootfs so the device can verify bundles.

#### Step 1 — Generate a development PKI

Run the meta-rauc helper from any empty working directory (it creates an
`openssl-ca/` folder in the current directory):

```bash
cd yocto/meta-rauc/scripts
./openssl-ca.sh
```

This produces:

```
openssl-ca/dev/
├── ca.cert.pem
├── ca.csr.pem
├── development-1.cert.pem
├── development-1.csr.pem
├── serial                         # OpenSSL CA serial counter
├── private/
│   ├── ca.key.pem
│   └── development-1.key.pem
└── certs/                         # issued certs (intermediate)
```

#### Step 2 — Copy generated files into `meta-device-base/`

Create the destination directories if they do not exist, then copy from the
script output:

```bash
REPO="$(git rev-parse --show-toplevel)"
LAYER="${REPO}/yocto/meta-device-base"
SRC="${REPO}/yocto/meta-rauc/scripts/openssl-ca/dev"

mkdir -p "${LAYER}/files/rauc-keys"
mkdir -p "${LAYER}/recipes-core/rauc/files"

# Bundle signing key + cert (used by device-base-bundle.bb)
cp "${SRC}/private/development-1.key.pem"  "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.cert.pem"        "${LAYER}/files/rauc-keys/"
cp "${SRC}/development-1.csr.pem"         "${LAYER}/files/rauc-keys/"
cp "${SRC}/private/ca.key.pem"              "${LAYER}/files/rauc-keys/development-ca.key.pem"

# Device keyring + serial (used by rauc-conf.bbappend → /etc/rauc/)
cp "${SRC}/ca.cert.pem"  "${LAYER}/recipes-core/rauc/files/"
cp "${SRC}/serial"       "${LAYER}/recipes-core/rauc/files/ca.cert.srl"
```

| Destination | Source (`openssl-ca/dev/…`) | Used by |
|-------------|----------------------------|---------|
| `files/rauc-keys/development-1.key.pem` | `private/development-1.key.pem` | `device-base-bundle.bb` (`RAUC_KEY_FILE`) |
| `files/rauc-keys/development-1.cert.pem` | `development-1.cert.pem` | `device-base-bundle.bb` (`RAUC_CERT_FILE`) |
| `files/rauc-keys/development-1.csr.pem` | `development-1.csr.pem` | Not used at build time; keep for re-issuing |
| `files/rauc-keys/development-ca.key.pem` | `private/ca.key.pem` | Offline CA key; not baked into images |
| `recipes-core/rauc/files/ca.cert.pem` | `ca.cert.pem` | Installed to `/etc/rauc/ca.cert.pem` on device |
| `recipes-core/rauc/files/ca.cert.srl` | `serial` | OpenSSL serial counter for the CA |

Restrict private keys to owner-read:

```bash
chmod 600 "${LAYER}/files/rauc-keys/"*.key.pem
```

#### Step 3 — Create `recipes-core/rauc/files/system.conf`

This file is **not** generated by `openssl-ca.sh`. It defines the A/B rootfs
slots for the Raspberry Pi 4 image and must be placed at
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

The slot devices match the partition layout in
`meta-device-base/wic/device-base-dual.wks.in`.

#### Step 4 — Verify before building

From `build-rpi/` (build environment sourced), confirm all paths exist:

```bash
LAYER="${YOCTO_DIR}/meta-device-base"
ls -l "${LAYER}/files/rauc-keys/"*.pem
ls -l "${LAYER}/recipes-core/rauc/files/ca.cert.pem" \
         "${LAYER}/recipes-core/rauc/files/ca.cert.srl" \
         "${LAYER}/recipes-core/rauc/files/system.conf"
```

Then build:

```bash
bitbake device-base-image
bitbake device-base-bundle
```

#### Reusing or sharing keys

- **Same team, same update chain:** copy an existing `files/rauc-keys/` and
  `recipes-core/rauc/files/` from a secure store (password manager, encrypted
  drive, secrets vault) instead of regenerating.
- **New PKI:** running `openssl-ca.sh` again creates a new CA; devices flashed
  with the old `ca.cert.pem` will reject bundles signed by the new key.
- **Production:** replace the development PKI with a proper CA and follow the
  same directory layout.

The upstream placeholder at `meta-rauc/recipes-core/rauc/files/ca.cert.pem` is a
dummy keyring from meta-rauc. The `meta-device-base/recipes-core/rauc/rauc-conf.bbappend`
overrides it with the real `ca.cert.pem` from this layer's `files/` directory.

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

- Rootfs is **read-only**; persistent state goes through the OverlayFS on
  `/data`.
- SSH password authentication and empty passwords are **disabled**.
- A root password hash and authorized SSH key can be injected at build time via
  `local.conf` so credentials never appear in source control.

---

## Layer structure (`meta-device-base/`)

```
meta-device-base/
├── conf/distro/device-base.conf            # DISTRO definition
├── files/rauc-keys/                        # RAUC dev PKI (signer + CA, gitignored)
├── recipes-bsp/rpi-u-boot-scr/             # RAUC-aware boot.cmd.in
├── recipes-connectivity/
│   ├── systemd-networkd/                   # 10-wlan0.network + wait-online override
│   └── wpa-supplicant/                     # per-interface config + template unit
├── recipes-core/
│   ├── bundles/device-base-bundle.bb       # signed .raucb recipe
│   ├── images/device-base-image.bb         # main image + postprocess
│   ├── rauc/                               # system.conf, CA cert
│   └── rauc-hawkbit-identity/              # identity service + config template
└── wic/device-base-dual.wks.in             # A/B + data partition layout
```

---

## License

The `meta-device-base` layer is licensed under the MIT License. See
[`meta-device-base/COPYING.MIT`](meta-device-base/COPYING.MIT).

## Acknowledgements

- [Yocto Project](https://www.yoctoproject.org/)
- [meta-raspberrypi](https://github.com/agherzan/meta-raspberrypi)
- [RAUC](https://rauc.io/) and [meta-rauc](https://github.com/rauc/meta-rauc)
- [Eclipse hawkBit](https://www.eclipse.org/hawkbit/)
- The RAUC and hawkBit example deployments that this project is modeled on.
