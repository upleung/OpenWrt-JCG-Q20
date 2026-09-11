#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DTS_SRC="$ROOT_DIR/target/linux/ramips/dts/mt7621_jcg_q20_cr6606.dts"
DTS_DST="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_jcg_q20_cr6606.dts"
NETWORK="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/02_network"
LEDS="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/01_leds"
IMAGE="$OPENWRT_DIR/target/linux/ramips/image/mt7621.mk"

install -D -m 0644 "$DTS_SRC" "$DTS_DST"

python3 - "$NETWORK" "$LEDS" <<'PYCODE'
from pathlib import Path
import sys

network = Path(sys.argv[1])
leds = Path(sys.argv[2])

for path, body in [
    (network, "\tjcg,q20-cr6606)\n\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\"\n\t\t;;\n"),
    (leds, "\tjcg,q20-cr6606)\n\t\tucidef_set_led_netdev \"internet\" \"Internet\" \"blue:net\" \"wan\"\n\t\t;;\n"),
]:
    s = path.read_text()
    if "jcg,q20-cr6606)" not in s:
        marker = "case $board in\n"
        if marker not in s:
            raise SystemExit(f"{path}: expected 'case $board in' marker not found")
        s = s.replace(marker, marker + body, 1)
        path.write_text(s)
PYCODE

if ! grep -q '^define Device/jcg_q20_cr6606$' "$IMAGE"; then
    cat >> "$IMAGE" <<'MKCODE'

define Device/jcg_q20_cr6606
  $(Device/xiaomi_mi-router-cr660x)
  DEVICE_VENDOR := JCG
  DEVICE_MODEL := Q20
  DEVICE_DTS := mt7621_jcg_q20_cr6606
  SUPPORTED_DEVICES := jcg,q20-cr6606 xiaomi,mi-router-cr6606
endef
TARGET_DEVICES += jcg_q20_cr6606
MKCODE
fi

grep -q 'jcg,q20-cr6606' "$DTS_DST"
grep -q 'jcg,q20-cr6606)' "$NETWORK"
grep -q 'jcg,q20-cr6606)' "$LEDS"
grep -q '^define Device/jcg_q20_cr6606$' "$IMAGE"
grep -q 'DEVICE_DTS := mt7621_jcg_q20_cr6606' "$IMAGE"

echo "JCG Q20 CR6606-based customization applied successfully."
