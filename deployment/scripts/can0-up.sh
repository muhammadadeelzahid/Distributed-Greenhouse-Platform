#!/bin/sh
# Bring up the SocketCAN can0 interface at 500 kbps.
# Production deployments use can0-up.service instead.
set -eu

IFACE="${1:-can0}"
BITRATE="${2:-500000}"

ip link set "$IFACE" down 2>/dev/null || true
ip link set "$IFACE" up type can bitrate "$BITRATE"
ip -details link show "$IFACE"
