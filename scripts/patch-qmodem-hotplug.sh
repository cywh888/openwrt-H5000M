#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-openwrt}"
NET_HOTPLUG=""
QMODEM_NETWORK=""

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
  "${SRC_DIR}/package/feeds/qmodem/qmodem/files/etc/init.d/qmodem_network" \
  "${SRC_DIR}/feeds/qmodem/application/qmodem/files/etc/init.d/qmodem_network" \
  "${SRC_DIR}/feeds/qmodem/qmodem/files/etc/init.d/qmodem_network"; do
  if [ -f "${candidate}" ]; then
    QMODEM_NETWORK="${candidate}"
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
  echo "已应用 QModem hotplug 过滤补丁：${NET_HOTPLUG}"
else
  echo "跳过 QModem hotplug 补丁：未找到文件或补丁已存在"
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
  echo "已应用 QModem LED 服务跳过补丁：${QMODEM_NETWORK}"
else
  echo "跳过 QModem LED 服务补丁：未找到文件或补丁已存在"
fi
