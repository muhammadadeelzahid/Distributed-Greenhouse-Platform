#!/bin/bash
# Helper script to launch the Raspberry Pi 4 image in QEMU.
# Copy to build-rpi/ after sourcing the build environment:
#   cp scripts/run_qemu.sh build-rpi/run_qemu.sh && chmod +x build-rpi/run_qemu.sh

if ! command -v qemu-system-aarch64 &> /dev/null; then
    echo "Host qemu-system-aarch64 not found. Trying to use Yocto's native QEMU..."
    QEMU_CMD="oe-run-native qemu-system-native qemu-system-aarch64"
else
    QEMU_CMD="qemu-system-aarch64"
fi

KERNEL="tmp/deploy/images/raspberrypi4-64/Image"
DTB="tmp/deploy/images/raspberrypi4-64/bcm2711-rpi-4-b.dtb"

ROOTFS=$(ls -t tmp/deploy/images/raspberrypi4-64/*rootfs*.ext4 | grep -v 'rootfs.ext4$' | head -n 1)

if [ -z "$ROOTFS" ]; then
    ROOTFS="tmp/deploy/images/raspberrypi4-64/device-base-image-raspberrypi4-64.rootfs.ext4"
fi

echo "Using Kernel: $KERNEL"
echo "Using DTB   : $DTB"
echo "Using Rootfs: $ROOTFS"
echo "--------------------------------------------------------"

$QEMU_CMD \
  -M raspi4b -cpu cortex-a72 -m 2G \
  -kernel "$KERNEL" \
  -dtb "$DTB" \
  -drive "file=$ROOTFS,format=raw,if=sd" \
  -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 root=/dev/mmcblk0 rootwait" \
  -serial stdio \
  -nographic
