#!/bin/sh
# rauc-hawkbit-identity.sh
#
# Reads the Raspberry Pi's unique hardware serial number and primary
# MAC address, then writes them into the rauc-hawkbit-updater config.
#
# Runs once on each boot, before the rauc-hawkbit-updater daemon starts.
# The config file lives on the persistent /data overlay so changes survive
# rootfs updates.

CONFIG_FILE="/etc/rauc-hawkbit-updater/config.conf"
TEMPLATE_FILE="/usr/share/rauc-hawkbit-updater/config.conf.template"

# --- Read hardware identity ---

# RPi serial number from device tree (preferred) or /proc/cpuinfo
if [ -f /sys/firmware/devicetree/base/serial-number ]; then
    SERIAL=$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number)
else
    SERIAL=$(grep -i '^serial' /proc/cpuinfo | awk '{print $3}' | sed 's/^0*//')
fi

# Primary Ethernet MAC address
if [ -d /sys/class/net/eth0 ]; then
    MAC=$(cat /sys/class/net/eth0/address)
elif [ -d /sys/class/net/end0 ]; then
    # Newer kernels use predictable names for RPi ethernet
    MAC=$(cat /sys/class/net/end0/address)
else
    MAC="unknown"
fi

# Build a target name from the serial
if [ -n "$SERIAL" ] && [ "$SERIAL" != "unknown" ]; then
    TARGET_NAME="rpi4-${SERIAL}"
else
    # Fallback: use MAC with colons stripped
    TARGET_NAME="rpi4-$(echo "$MAC" | tr -d ':')"
fi

echo "rauc-hawkbit-identity: serial=${SERIAL} mac=${MAC} target=${TARGET_NAME}"

# --- Generate config from template if it exists ---

if [ -f "$TEMPLATE_FILE" ]; then
    sed \
        -e "s|@@TARGET_NAME@@|${TARGET_NAME}|g" \
        -e "s|@@SERIAL@@|${SERIAL}|g" \
        -e "s|@@MAC@@|${MAC}|g" \
        "$TEMPLATE_FILE" > "$CONFIG_FILE"
    echo "rauc-hawkbit-identity: wrote ${CONFIG_FILE} from template"
else
    # No template — patch the existing config in-place
    if [ -f "$CONFIG_FILE" ]; then
        sed -i \
            -e "s|^target_name\s*=.*|target_name = ${TARGET_NAME}|" \
            "$CONFIG_FILE"

        # Update device attributes
        grep -q '^serial\s*=' "$CONFIG_FILE" && \
            sed -i "s|^serial\s*=.*|serial = ${SERIAL}|" "$CONFIG_FILE" || \
            sed -i "/^\[device\]/a serial = ${SERIAL}" "$CONFIG_FILE"

        grep -q '^mac_address\s*=' "$CONFIG_FILE" && \
            sed -i "s|^mac_address\s*=.*|mac_address = ${MAC}|" "$CONFIG_FILE" || \
            sed -i "/^\[device\]/a mac_address = ${MAC}" "$CONFIG_FILE"

        echo "rauc-hawkbit-identity: patched ${CONFIG_FILE} in-place"
    else
        echo "rauc-hawkbit-identity: ERROR — no config file found at ${CONFIG_FILE}"
        exit 1
    fi
fi
