#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DTS_SRC="$ROOT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
DTS_DST="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"

NETWORK="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/02_network"
LEDS="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/01_leds"
IMAGE="$OPENWRT_DIR/target/linux/ramips/image/mt7621.mk"

install -D -m 0644 "$DTS_SRC" "$DTS_DST"

python3 - "$NETWORK" "$LEDS" <<'PY'
from pathlib import Path
import sys

network, leds = Path(sys.argv[1]), Path(sys.argv[2])
s = network.read_text()
if "jcg,q20-cr6606)" not in s:
    marker = "case $board in\n"
    insert = "case $board in\n\tjcg,q20-cr6606)\n\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\"\n\t\t;;\n"
    network.write_text(s.replace(marker, insert, 1))

s = leds.read_text()
if "jcg,q20-cr6606)" not in s:
    marker = "case $board in\n"
    insert = "case $board in\n\tjcg,q20-cr6606)\n\t\tucidef_set_led_netdev \"internet\" \"Internet\" \"blue:net\" \"wan\"\n\t\t;;\n"
    leds.write_text(s.replace(marker, insert, 1))
PY

if ! grep -q '^define Device/xiaomi_mi-router-cr6606$' "$IMAGE"; then
	cat >> "$IMAGE" <<'EOF'

define Device/xiaomi_mi-router-cr6606
  $(Device/xiaomi_mi-router-cr660x)
  DEVICE_VENDOR := JCG
  DEVICE_MODEL := Q20
  DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606
  SUPPORTED_DEVICES := jcg,q20-cr6606 xiaomi,mi-router-cr6606
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606
EOF
fi