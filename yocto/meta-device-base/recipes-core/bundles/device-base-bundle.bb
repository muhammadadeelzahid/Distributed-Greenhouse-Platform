inherit bundle

RAUC_BUNDLE_COMPATIBLE = "device-base-raspberrypi4-64"
RAUC_BUNDLE_FORMAT = "verity"

RAUC_BUNDLE_SLOTS = "rootfs"
RAUC_SLOT_rootfs = "device-base-image"
RAUC_SLOT_rootfs[fstype] = "ext4"

RAUC_KEY_FILE = "${TOPDIR}/../meta-device-base/files/rauc-keys/development-1.key.pem"
RAUC_CERT_FILE = "${TOPDIR}/../meta-device-base/files/rauc-keys/development-1.cert.pem"
