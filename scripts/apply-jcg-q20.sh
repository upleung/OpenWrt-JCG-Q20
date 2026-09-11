#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DTS_SRC="$ROOT_DIR/target/linux/ramips/dts/mt7621_jcg_q20_cr6606.dts"
DTS_DST="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_jcg_q20_cr6606.dts"

NETWORK="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/02_network"
LEDS="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/01_leds"
IMAGE="$OPENWRT_DIR/target/linux/ramips/image/mt7621.mk"

echo "==> Install custom DTS"
install -D -m 0644 \
	"$DTS_SRC" \
	"$DTS_DST"

echo "==> Patch board network configuration"

python3 - "$NETWORK" "$LEDS" <<'PY'
from pathlib import Path
import sys

network = Path(sys.argv[1])
leds = Path(sys.argv[2])

# ------------------------------------------------------------
# 02_network
# ------------------------------------------------------------

s = network.read_text()

if "jcg,q20-cr6606)" not in s:
    marker = "case $board in\n"

    insert = (
        "case $board in\n"
        "\tjcg,q20-cr6606)\n"
        "\t\tucidef_set_interfaces_lan_wan \"lan1 lan2\" \"wan\"\n"
        "\t\t;;\n"
    )

    if marker not in s:
        raise SystemExit(
            "ERROR: 02_network does not contain expected case marker"
        )

    s = s.replace(marker, insert, 1)
    network.write_text(s)

# ------------------------------------------------------------
# 01_leds
# ------------------------------------------------------------

s = leds.read_text()

if "jcg,q20-cr6606)" not in s:
    marker = "case $board in\n"

    insert = (
        "case $board in\n"
        "\tjcg,q20-cr6606)\n"
        "\t\tucidef_set_led_netdev "
        "\"internet\" \"Internet\" \"blue:net\" \"wan\"\n"
        "\t\t;;\n"
    )

    if marker not in s:
        raise SystemExit(
            "ERROR: 01_leds does not contain expected case marker"
        )

    s = s.replace(marker, insert, 1)
    leds.write_text(s)
PY

echo "==> Add JCG Q20 image profile"

if ! grep -q '^define Device/jcg_q20_cr6606$' "$IMAGE"; then
	cat >> "$IMAGE" <<'EOF'

define Device/jcg_q20_cr6606
  $(Device/xiaomi_mi-router-cr660x)
  DEVICE_VENDOR := JCG
  DEVICE_MODEL := Q20
  DEVICE_DTS := mt7621_jcg_q20_cr6606
  SUPPORTED_DEVICES := jcg,q20-cr6606 xiaomi,mi-router-cr6606
endef
TARGET_DEVICES += jcg_q20_cr6606
EOF
fi

echo "==> Verify customization"

grep -q 'jcg,q20-cr6606' "$DTS_DST"
grep -q 'label = "wan"' "$DTS_DST"
grep -q 'label = "lan1"' "$DTS_DST"
grep -q 'label = "lan2"' "$DTS_DST"
grep -q 'status = "disabled"' "$DTS_DST"

grep -q 'jcg,q20-cr6606)' "$NETWORK"
grep -q 'jcg,q20-cr6606)' "$LEDS"

grep -q '^define Device/jcg_q20_cr6606$' "$IMAGE"
grep -q 'DEVICE_DTS := mt7621_jcg_q20_cr6606' "$IMAGE"

echo
echo "=============================================="
echo "JCG Q20 customization applied successfully."
echo "=============================================="
echo
echo "Physical mapping:"
echo "  WAN  -> switch port@0 -> wan"
echo "  LAN1 -> switch port@1 -> lan1"
echo "  LAN2 -> gmac1 / PHY4 -> lan2"
echo