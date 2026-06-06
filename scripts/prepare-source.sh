#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/openwrt"

SOURCE_TREE="${SOURCE_TREE:-${1:-openwrt}}"
REF="${2:-${SOURCE_REF:-${OPENWRT_REF:-v25.12.4}}}"

if [ "$#" -eq 1 ]; then
  case "${SOURCE_TREE}" in
    openwrt|immortalwrt)
      ;;
    *)
      REF="${SOURCE_TREE}"
      SOURCE_TREE="${SOURCE_TREE_DEFAULT:-openwrt}"
      ;;
  esac
fi

case "${SOURCE_TREE}" in
  openwrt)
    REPO_URL="${OPENWRT_REPO:-https://github.com/openwrt/openwrt.git}"
    TREE_NAME="OpenWrt"
    ;;
  immortalwrt)
    REPO_URL="${IMMORTALWRT_REPO:-https://github.com/immortalwrt/immortalwrt.git}"
    TREE_NAME="ImmortalWrt"
    ;;
  *)
    echo "未知主源码：${SOURCE_TREE}，可选值：openwrt / immortalwrt"
    exit 1
    ;;
esac

INCLUDE_QMODEM="${INCLUDE_QMODEM:-false}"
INCLUDE_PASSWALL="${INCLUDE_PASSWALL:-false}"
INCLUDE_MOSDNS="${INCLUDE_MOSDNS:-false}"
INCLUDE_MOSDNS_LUCI="${INCLUDE_MOSDNS_LUCI:-false}"
INCLUDE_UPNP="${INCLUDE_UPNP:-false}"
INCLUDE_HOMEPROXY="${INCLUDE_HOMEPROXY:-false}"
INCLUDE_SMALL_PACKAGE="${INCLUDE_SMALL_PACKAGE:-false}"

if [ -d "${SRC_DIR}/.git" ]; then
  echo "更新已有 ${TREE_NAME} 源码：${REF}"
  git -C "${SRC_DIR}" remote set-url origin "${REPO_URL}"
  git -C "${SRC_DIR}" fetch --tags --depth=1 origin "${REF}"
  git -C "${SRC_DIR}" checkout --detach FETCH_HEAD
else
  echo "克隆 ${TREE_NAME} 源码：${REF}"
  git clone --depth=1 --branch "${REF}" "${REPO_URL}" "${SRC_DIR}"
fi

echo "应用 H5000M 设备适配"
python3 "${ROOT_DIR}/scripts/apply-h5000m.py" "${SRC_DIR}"

for patch in "${ROOT_DIR}"/patches/optional/*.patch; do
  [ -e "${patch}" ] || continue
  if git -C "${SRC_DIR}" apply --check "${patch}" >/dev/null 2>&1; then
    git -C "${SRC_DIR}" apply "${patch}"
    echo "已应用可选补丁：$(basename "${patch}")"
  else
    echo "跳过不兼容的可选补丁：$(basename "${patch}")"
  fi
done

cp "${ROOT_DIR}/configs/h5000m.seed" "${SRC_DIR}/.config"

append_feed_once() {
  local feed_line="$1"
  local feed_name
  feed_name="$(printf '%s\n' "${feed_line}" | awk '{print $2}')"
  if ! grep -Eq "^src-git[[:space:]]+${feed_name}[[:space:]]" "${SRC_DIR}/feeds.conf.default"; then
    printf '%s\n' "${feed_line}" >> "${SRC_DIR}/feeds.conf.default"
  fi
}

if [ "${INCLUDE_QMODEM}" = "true" ]; then
  echo "添加 QModem 第三方 feed"
  append_feed_once "src-git qmodem https://github.com/FUjr/QModem.git"
fi

if [ "${INCLUDE_PASSWALL}" = "true" ]; then
  echo "添加 PassWall 第三方 feed"
  append_feed_once "src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
  append_feed_once "src-git passwall https://github.com/Openwrt-Passwall/openwrt-passwall.git"
fi

if [ "${INCLUDE_HOMEPROXY}" = "true" ]; then
  echo "添加 HomeProxy 第三方 feed"
  append_feed_once "src-git homeproxy https://github.com/VIKINGYFY/homeproxy.git"
fi

if [ "${INCLUDE_SMALL_PACKAGE}" = "true" ]; then
  echo "添加 kenzok8 small-package 额外插件 feed"
  append_feed_once "src-git small_package https://github.com/kenzok8/small-package.git"
fi

if [ "${INCLUDE_MOSDNS_LUCI}" = "true" ]; then
  echo "添加第三方 MosDNS LuCI 页面，本体仍优先使用主源码 feeds 中的 mosdns"
  MOSDNS_LUCI_CACHE="${ROOT_DIR}/build-cache/sbwml-luci-app-mosdns"
  MOSDNS_LUCI_PACKAGE_DIR="${SRC_DIR}/package/h5000m-mosdns-luci"

  if [ -d "${MOSDNS_LUCI_CACHE}/.git" ]; then
    git -C "${MOSDNS_LUCI_CACHE}" fetch --depth=1 origin HEAD
    git -C "${MOSDNS_LUCI_CACHE}" reset --hard FETCH_HEAD
  else
    git clone --depth=1 https://github.com/sbwml/luci-app-mosdns.git "${MOSDNS_LUCI_CACHE}"
  fi

  rm -rf "${MOSDNS_LUCI_PACKAGE_DIR}"
  mkdir -p "${MOSDNS_LUCI_PACKAGE_DIR}"
  cp -a "${MOSDNS_LUCI_CACHE}/luci-app-mosdns" "${MOSDNS_LUCI_PACKAGE_DIR}/luci-app-mosdns"
  cp -a "${MOSDNS_LUCI_CACHE}/v2dat" "${MOSDNS_LUCI_PACKAGE_DIR}/v2dat"
fi

echo "写入默认 LAN IP、root 密码、WAN 优先级和软件源清理脚本"
mkdir -p "${SRC_DIR}/files"
cp -a "${ROOT_DIR}/files/." "${SRC_DIR}/files/"

echo "写入 H5000M 自定义软件包"
rm -rf "${SRC_DIR}/package/h5000m-custom"
mkdir -p "${SRC_DIR}/package/h5000m-custom"
cp -a "${ROOT_DIR}/packages/." "${SRC_DIR}/package/h5000m-custom/"

echo "${TREE_NAME} 源码已准备完成：${SRC_DIR}"
echo "当前主源码：${SOURCE_TREE}"
echo "当前源码版本：${REF}"
echo "后续本地编译步骤："
echo "  cd ${SRC_DIR}"
echo "  ./scripts/feeds update -a"
echo "  ./scripts/feeds install -a"
echo "  INCLUDE_QMODEM=${INCLUDE_QMODEM} INCLUDE_PASSWALL=${INCLUDE_PASSWALL} INCLUDE_MOSDNS=${INCLUDE_MOSDNS} INCLUDE_MOSDNS_LUCI=${INCLUDE_MOSDNS_LUCI} INCLUDE_UPNP=${INCLUDE_UPNP} INCLUDE_HOMEPROXY=${INCLUDE_HOMEPROXY} bash ${ROOT_DIR}/scripts/apply-package-options.sh"
echo "  make defconfig"
echo "  make download -j\$(nproc)"
echo "  make -j\$(nproc)"
