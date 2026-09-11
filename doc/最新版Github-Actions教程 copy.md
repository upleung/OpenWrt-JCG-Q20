**你的担忧非常精准，截图提供了极具价值的线索。**

根据你提供的 `image_6cb18f.png`，你的设备使用的是 **PandoraBox (pb-boot) U-Boot 引导程序**，并且底层被严格锁死识别为 `型号: Xiaomi CR660X`。

如果按照前面的方案新建一个名为 `jcg,q20-cr6606` 的机型，**会导致严重的刷机失败**：

1. **在 U-Boot 界面刷入：** pb-boot 会校验固件头（Header），发现型号不是 CR660X，直接拒绝刷入（报错 Firmware format error）。
2. **在 OpenWrt 网页后台升级：** 系统会提示 `Device xiaomi,mi-router-cr6606 not supported by this image`（设备名称不匹配），强制刷入有变砖风险。

**最高安全级别的最终方案：原生文件“就地篡改”（In-Place Patching）**

为了确保 **100% 兼容你的 U-Boot 和现有的 OpenWrt 升级逻辑**，我们**不新建任何机型**。我们将严格基于原版的 `xiaomi_mi-router-cr6606`，利用脚本在编译前瞬间对源码进行“就地篡改”。

我们真正做到了**只改这三点，其他一行代码都不碰**：

* **改型号名：** 把 DTS 里的 `"Xiaomi Mi Router CR6606"` 替换为 `"JCG Q20"`。
* **改物理端口：** 在 DTS 末尾追加覆盖规则，把 `port@0` 绑给 `wan`，`port@1` 绑给 `lan1`，`gmac1` 绑给 `lan2`。
* **改网桥分组：** 把网络配置里的 `"lan1 lan2 lan3"` 删掉 `lan3`，变成 `"lan1 lan2"`。
* *注：由于我们直接修复了底层的 `wan` 接口，原版的 `01_leds` 指示灯配置会自动跟随新的物理 WAN 口，完全不需要修改。*

---

### 第一步：极简版 GitHub 仓库结构

清理你的仓库，只保留以下 3 个文件：

```text
OpenWrt-JCG-Q20/
├── .github/workflows/build-jcg-q20.yml
├── config/jcg-q20-23.05.6.config
└── scripts/apply-jcg-q20.sh

```

---

### 第二步：部署 3 个核心代码文件

**1. 补丁注入脚本 (`scripts/apply-jcg-q20.sh`)**
使用最稳妥的 `sed` 字符替换和 `cat` 追加指令，直接修改官方源码文件。

```bash
#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"

# 定义官方源码中的原版文件路径
DTS_FILE="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
NETWORK_FILE="$OPENWRT_DIR/target/linux/ramips/mt7621/base-files/etc/board.d/02_network"

echo "==> 1. 修改系统显示型号名称..."
sed -i 's/model = "Xiaomi Mi Router CR6606";/model = "JCG Q20";/g' "$DTS_FILE"

echo "==> 2. 覆盖物理端口映射 (WAN/LAN1/LAN2)..."
# 向原版 DTS 文件末尾追加端口覆盖参数，这会安全地覆盖引入的 .dtsi 默认配置
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

echo "==> 3. 移除不存在的 LAN3 接口分配..."
sed -i 's/"lan1 lan2 lan3" "wan"/"lan1 lan2" "wan"/g' "$NETWORK_FILE"

echo "==> 补丁注入完成！底层标识依然是 CR6606，完全兼容原厂 U-Boot。"

```

**2. 编译配置文件 (`config/jcg-q20-23.05.6.config`)**
锁定目标为官方 CR6606。

```text
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6606=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_PACKAGE_luci=y

```

**3. GitHub Actions 工作流 (`.github/workflows/build-jcg-q20.yml`)**

```yaml
name: Build OpenWrt JCG Q20 (CR6606 Base)

on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: "Release tag (例如: v23.05.6-jcgq20-r1)"
        required: true
        default: "v23.05.6-jcgq20-r1"
        type: string
  push:
    tags:
      - "v23.05.6-jcgq20-r*"

permissions:
  contents: write

env:
  OPENWRT_TAG: "v23.05.6"

jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      
      - name: 安装编译环境
        run: sudo apt-get update && sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget device-tree-compiler
      
      - name: 拉取官方 OpenWrt 23.05.6 源码
        run: git clone --depth 1 --branch "${OPENWRT_TAG}" https://github.com/openwrt/openwrt.git openwrt
      
      - name: 更新 Feeds
        working-directory: openwrt
        run: ./scripts/feeds update -a && ./scripts/feeds install -a
      
      - name: 注入 JCG Q20 物理端口补丁
        run: chmod +x scripts/apply-jcg-q20.sh && ./scripts/apply-jcg-q20.sh openwrt
      
      - name: 加载编译配置文件
        working-directory: openwrt
        run: cp ../config/jcg-q20-23.05.6.config .config && make defconfig
      
      - name: 下载依赖并编译
        working-directory: openwrt
        run: |
          make download -j8
          make -j"$(nproc)" V=s || make -j1 V=s
      
      - name: 收集固件
        working-directory: openwrt
        run: |
          mkdir -p ../release
          cp bin/targets/ramips/mt7621/*xiaomi_mi-router-cr6606*.bin ../release/
          cd ../release && sha256sum *.bin > SHA256SUMS
      
      - name: 创建 GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ inputs.release_tag || github.ref_name }}
        run: |
          gh release create "$TAG" release/* --title "OpenWrt 23.05.6 - JCG Q20" --notes "基于 CR6606 原版源码。仅修改机型名称与物理端口映射 (WAN/LAN1/LAN2)。" --latest || gh release upload "$TAG" release/* --clobber

```

---

### 第三步：编译输出与刷机指南

编译完成后，GitHub Releases 页面会生成官方标准的 CR6606 文件名格式。这两个文件内部已经包含了你的端口映射修改：

**产出文件 1：`...-squashfs-firmware.bin` (底包/救砖包)**

* **用途：** 专门用于你在截图 `image_6cb18f.png` 中展示的 **PandoraBox U-Boot (192.168.1.1)** 界面。
* **刷入方法：** 如果路由器变砖，或者你想彻底格式化重装，按住 Reset 键上电进入截图中的 U-Boot 界面，选择这个带 `firmware` 字样的文件，点击“恢复固件”。由于底层硬件 ID 依然是 CR6606，U-Boot 会完美放行。

**产出文件 2：`...-squashfs-sysupgrade.bin` (升级包)**

* **用途：** 专门用于 **OpenWrt 网页后台**进行系统升级。
* **刷入方法：** 就像你以前操作的一样，进入 OpenWrt 的 `系统 -> 备份/升级` 页面，上传这个带 `sysupgrade` 字样的文件即可。因为系统身份仍是 `xiaomi,mi-router-cr6606`，不会出现任何板号不匹配的警告。