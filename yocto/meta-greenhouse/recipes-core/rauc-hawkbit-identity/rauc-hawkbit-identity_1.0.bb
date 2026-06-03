SUMMARY = "Generate rauc-hawkbit-updater device identity from hardware"
DESCRIPTION = "Reads the Raspberry Pi serial number and MAC address on \
each boot and writes them into the rauc-hawkbit-updater configuration. \
This ensures each device registers with hawkBit using a unique, \
hardware-derived identity without manual per-device configuration."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = "\
    file://rauc-hawkbit-identity.sh \
    file://rauc-hawkbit-identity.service \
    file://config.conf.template \
"

# hawkBit connection settings — set these in your build-rpi/conf/local.conf:
#   HAWKBIT_SERVER_URL = "192.168.1.100:8080"
#   HAWKBIT_GATEWAY_TOKEN = "your-gateway-token-here"
HAWKBIT_SERVER_URL ?= "localhost:8080"
HAWKBIT_GATEWAY_TOKEN ?= "REPLACE_ME"

inherit systemd

SYSTEMD_SERVICE:${PN} = "rauc-hawkbit-identity.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    # Install the identity script
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/rauc-hawkbit-identity.sh ${D}${bindir}/rauc-hawkbit-identity.sh

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/rauc-hawkbit-identity.service ${D}${systemd_system_unitdir}

    # Install the config template with server/token baked in at build time.
    # The @@TARGET_NAME@@, @@SERIAL@@, @@MAC@@ placeholders remain and are
    # resolved at boot time by the identity script.
    install -d ${D}${datadir}/rauc-hawkbit-updater
    sed -e 's|@@HAWKBIT_SERVER@@|${HAWKBIT_SERVER_URL}|g' \
        -e 's|@@GATEWAY_TOKEN@@|${HAWKBIT_GATEWAY_TOKEN}|g' \
        ${WORKDIR}/config.conf.template \
        > ${D}${datadir}/rauc-hawkbit-updater/config.conf.template
    chmod 0644 ${D}${datadir}/rauc-hawkbit-updater/config.conf.template
}

FILES:${PN} += "${datadir}/rauc-hawkbit-updater"
