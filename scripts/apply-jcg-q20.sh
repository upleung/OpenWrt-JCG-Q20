#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"

# 定位官方原版文件
DTS_FILE="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
NETWORK_FILE="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/02_network"
CONFIG_GENERATE="$OPENWRT_DIR/package/base-files/files/bin/config_generate"

echo "==> 1. 将后台显示名称篡改为 JCG Q20..."
sed -i 's/model = "Xiaomi Mi Router CR6606";/model = "JCG Q20";/g' "$DTS_FILE"

echo "==> 2. 覆盖物理端口映射 (WAN/LAN1/LAN2)..."
cat >> "$DTS_FILE" <<'EOF'

&gmac1 {
	label = "lan2";
	phy-handle = <&ethphy4>;
};

&switch0 {
	ports {
		port@0 {
			status = "okay";
			label = "wan";
		};
		port@1 {
			status = "okay";
			label = "lan1";
		};
		port@2 {
			status = "disabled";
		};
	};
};
EOF

echo "==> 3. 移除多余的 LAN3 接口..."
sed -i 's/"lan1 lan2 lan3" "wan"/"lan1 lan2" "wan"/g' "$NETWORK_FILE"

echo "==> 4. 修改默认 LAN IP 为 192.168.5.1..."
sed -i 's/192.168.1.1/192.168.5.1/g' "$CONFIG_GENERATE"

echo "==> 补丁注入完成！底层标识依然是 CR6606，完全兼容原厂 U-Boot。"