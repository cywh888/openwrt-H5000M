#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-openwrt}"
NET_HOTPLUG=""
USB_HOTPLUG=""
QMODEM_NETWORK=""
QMODEM_LED=""

for candidate in \
  "${SRC_DIR}/package/feeds/qmodem/qmodem/files/etc/hotplug.d/net/20-modem-net" \
  "${SRC_DIR}/feeds/qmodem/application/qmodem/files/etc/hotplug.d/net/20-modem-net" \
  "${SRC_DIR}/feeds/qmodem/qmodem/files/etc/hotplug.d/net/20-modem-net"; do
  if [ -f "${candidate}" ]; then
    NET_HOTPLUG="${candidate}"
    break
  fi
done

for candidate in \
  "${SRC_DIR}/package/feeds/qmodem/qmodem/files/etc/hotplug.d/usb/20-modem-usb" \
  "${SRC_DIR}/feeds/qmodem/application/qmodem/files/etc/hotplug.d/usb/20-modem-usb" \
  "${SRC_DIR}/feeds/qmodem/qmodem/files/etc/hotplug.d/usb/20-modem-usb"; do
  if [ -f "${candidate}" ]; then
    USB_HOTPLUG="${candidate}"
    break
  fi
done

for candidate in \
  "${SRC_DIR}/package/feeds/qmodem/qmodem/files/etc/init.d/qmodem_network" \
  "${SRC_DIR}/feeds/qmodem/application/qmodem/files/etc/init.d/qmodem_network" \
  "${SRC_DIR}/feeds/qmodem/qmodem/files/etc/init.d/qmodem_network"; do
  if [ -f "${candidate}" ]; then
    QMODEM_NETWORK="${candidate}"
    break
  fi
done

for candidate in \
  "${SRC_DIR}/package/feeds/qmodem/qmodem/files/etc/init.d/qmodem_led" \
  "${SRC_DIR}/feeds/qmodem/application/qmodem/files/etc/init.d/qmodem_led" \
  "${SRC_DIR}/feeds/qmodem/qmodem/files/etc/init.d/qmodem_led"; do
  if [ -f "${candidate}" ]; then
    QMODEM_LED="${candidate}"
    break
  fi
done

if [ -n "${NET_HOTPLUG}" ] && ! grep -q "H5000M_QMODEM_HOTPLUG_FILTER" "${NET_HOTPLUG}"; then
  python3 - "${NET_HOTPLUG}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

anchor = '[ -z "${DEVPATH}" ] && exit\n'
insert = r'''

# H5000M_QMODEM_HOTPLUG_FILTER
# H5000M uses the USB NCM modem at slot 2-1.  WiFi AP interfaces and normal
# Ethernet devices also trigger net hotplug events; do not let QModem scan them
# as PCIe modems.
case "${INTERFACE}" in
    br-lan|lan|wan|wan6|eth0|eth1|hnat|phy*-ap*|phy*.*-ap*|wlan*)
        exit
        ;;
esac

case "${DEVPATH}" in
    */net/br-lan|*/net/eth0|*/net/eth1|*/net/hnat|*/net/phy*-ap*|*/net/phy*.*-ap*|*/net/wlan*)
        exit
        ;;
esac
'''

if anchor not in text:
    raise SystemExit(f"missing hotplug anchor in {path}")

text = text.replace(anchor, anchor + insert, 1)

anchor = '''logger -t modem_hotplug "net slot: ${slot} action: ${ACTION} slot_type: ${slot_type}"
'''
insert = r'''if [ "${slot_type}" = "pcie" ] && [ "$(uci -q get qmodem.main.enable_pcie_scan || echo 0)" != "1" ]; then
    exit
fi

'''

if anchor not in text:
    raise SystemExit(f"missing slot_type anchor in {path}")

text = text.replace(anchor, insert + anchor, 1)
path.write_text(text, encoding="utf-8")
PY
  echo "Applied QModem net hotplug filter: ${NET_HOTPLUG}"
else
  echo "Skipped QModem net hotplug filter: file missing or already patched."
fi

if [ -n "${USB_HOTPLUG}" ] && ! grep -q "H5000M_QMODEM_USB_SLOT_FILTER" "${USB_HOTPLUG}"; then
  python3 - "${USB_HOTPLUG}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

anchor = 'slot=$(basename "${DEVPATH}")\n'
insert = r'''# H5000M_QMODEM_USB_SLOT_FILTER
# Only the built-in 5G module at USB slot 2-1 should be auto-scanned.
case "$(basename "${DEVPATH}")" in
    2-1)
        ;;
    *)
        exit
        ;;
esac

'''

if anchor not in text:
    raise SystemExit(f"missing USB hotplug anchor in {path}")

text = text.replace(anchor, insert + anchor, 1)
path.write_text(text, encoding="utf-8")
PY
  echo "Applied QModem USB slot filter: ${USB_HOTPLUG}"
else
  echo "Skipped QModem USB slot filter: file missing or already patched."
fi

if [ -n "${QMODEM_NETWORK}" ] && ! grep -q "H5000M_QMODEM_SKIP_LED_SERVICE" "${QMODEM_NETWORK}"; then
  python3 - "${QMODEM_NETWORK}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace(
'''start_led_service()
{
    /etc/init.d/qmodem_led start_instance "$1"
    logger -t qmodem_network "Forward start LED event for modem $1"
}
''',
'''start_led_service()
{
    # H5000M_QMODEM_SKIP_LED_SERVICE
    [ -x /etc/init.d/qmodem_led ] || return 0
    [ "$(uci -q get qmodem.main.enable_led_service || echo 0)" = "1" ] || return 0
    /etc/init.d/qmodem_led start_instance "$1" || true
    logger -t qmodem_network "Forward start LED event for modem $1"
}
''',
1,
)

text = text.replace(
'''stop_led_service(){
    /etc/init.d/qmodem_led stop_instance "$1"
    logger -t qmodem_network "Forward stop LED event for modem $1"
}
''',
'''stop_led_service(){
    # H5000M_QMODEM_SKIP_LED_SERVICE
    [ -x /etc/init.d/qmodem_led ] || return 0
    [ "$(uci -q get qmodem.main.enable_led_service || echo 0)" = "1" ] || return 0
    /etc/init.d/qmodem_led stop_instance "$1" || true
    logger -t qmodem_network "Forward stop LED event for modem $1"
}
''',
1,
)

if "H5000M_QMODEM_SKIP_LED_SERVICE" not in text:
    raise SystemExit(f"missing qmodem_network LED anchor in {path}")

path.write_text(text, encoding="utf-8")
PY
  echo "Applied QModem LED service guard: ${QMODEM_NETWORK}"
else
  echo "Skipped QModem LED service guard: file missing or already patched."
fi

if [ -n "${QMODEM_LED}" ] && ! grep -q "H5000M_QMODEM_LED_EMPTY_GUARD" "${QMODEM_LED}"; then
  python3 - "${QMODEM_LED}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace(
'''start_instance()
{
    [ -n "$1" ] || return 1
    config_load qmodem
    procd_kill "$service" "led_$1"
    rc_procd _start_instance "$1"
}
''',
'''start_instance()
{
    # H5000M_QMODEM_LED_EMPTY_GUARD
    local led_script
    [ -n "$1" ] || return 1
    config_load qmodem
    config_get led_script "$1" led_script
    [ -n "$led_script" ] || return 0
    [ -x "/usr/share/qmodem/led_scripts/${led_script}.sh" ] || return 0
    procd_kill "$service" "led_$1"
    rc_procd _start_instance "$1"
}
''',
1,
)

if "H5000M_QMODEM_LED_EMPTY_GUARD" not in text:
    raise SystemExit(f"missing qmodem_led start_instance anchor in {path}")

path.write_text(text, encoding="utf-8")
PY
  echo "Applied QModem LED empty-instance guard: ${QMODEM_LED}"
else
  echo "Skipped QModem LED empty-instance guard: file missing or already patched."
fi
