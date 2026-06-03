#!/bin/bash
# Checks which partition we booted from and resets its boot counter to 3

# Figure out the active slot from the kernel cmdline
CMDLINE=$(cat /proc/cmdline)

if [[ "$CMDLINE" == *root=/dev/mmcblk0p2* ]]; then
    ACTIVE_SLOT="A"
    COUNTER_VAR="boot_a_left"
elif [[ "$CMDLINE" == *root=/dev/mmcblk0p3* ]]; then
    ACTIVE_SLOT="B"
    COUNTER_VAR="boot_b_left"
else
    echo "Could not determine active slot from cmdline: $CMDLINE"
    exit 1
fi

echo "Active slot is ${ACTIVE_SLOT}. Marking slot as good (setting ${COUNTER_VAR}=3)"
fw_setenv ${COUNTER_VAR} 3

if [ $? -eq 0 ]; then
    echo "Mark-good successful."
    exit 0
else
    echo "fw_setenv failed!"
    exit 1
fi
