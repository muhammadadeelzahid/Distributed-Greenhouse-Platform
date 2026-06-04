FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://wpa_supplicant.conf"

SYSTEMD_SERVICE:${PN} = "wpa_supplicant@wlan0.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

UOFM_IDENTITY ?= "CHANGE_ME@myumanitoba.ca"
UOFM_PASSWORD ?= "CHANGE_ME"
HOTSPOT_SSID ?= "CHANGE_ME"
HOTSPOT_PSK ?= "CHANGE_ME"

do_install:append() {
    install -d ${D}${sysconfdir}/wpa_supplicant
    install -m 0600 ${WORKDIR}/wpa_supplicant.conf ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf
    sed -i \
        -e 's|@UOFM_IDENTITY@|${UOFM_IDENTITY}|g' \
        -e 's|@UOFM_PASSWORD@|${UOFM_PASSWORD}|g' \
        -e 's|@HOTSPOT_SSID@|${HOTSPOT_SSID}|g' \
        -e 's|@HOTSPOT_PSK@|${HOTSPOT_PSK}|g' \
        ${D}${sysconfdir}/wpa_supplicant/wpa_supplicant-wlan0.conf
}
