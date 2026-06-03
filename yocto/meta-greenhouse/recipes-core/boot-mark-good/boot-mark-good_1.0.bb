SUMMARY = "Automatically mark U-Boot A/B slot as good"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = "\
    file://boot-mark-good.sh \
    file://boot-mark-good.service \
    file://boot-mark-good.timer \
"

# We depend on libubootenv (provides fw_printenv and fw_setenv) and bash
RDEPENDS:${PN} = "libubootenv-bin bash"

inherit systemd

SYSTEMD_SERVICE:${PN} = "boot-mark-good.timer"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += "${systemd_system_unitdir}/boot-mark-good.service"

do_install() {
    # Install the script
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/boot-mark-good.sh ${D}${bindir}/boot-mark-good.sh
    
    # Install systemd timers and services
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/boot-mark-good.service ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/boot-mark-good.timer ${D}${systemd_system_unitdir}
}
