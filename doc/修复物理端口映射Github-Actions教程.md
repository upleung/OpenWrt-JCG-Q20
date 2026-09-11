可以修改，而且这次建议**同时把“设备名称、底层端口映射、GitHub Actions 构建 Profile、Release 标签”一次性规范好**。

先修正上一版方案里的一个关键点：**你的硬件已经有非常明确的实测映射，不需要猜。**你当前刷 CR6606 固件后的实际关系是：

```text
物理 WAN  → 当前 lan1
物理 LAN1 → 当前 lan2
物理 LAN2 → 当前 wan
```

你上传的命令行也证明当前系统实际上创建了 `wan`、`lan1`、`lan2`、`lan3`，而 `br-lan` 默认桥接 `lan1 lan2 lan3`。 

而 OpenWrt 23.05.6 的 CR660x DTS 正好定义：

```text
gmac1       → wan，PHY4
switch port0 → lan1
switch port1 → lan2
switch port2 → lan3
```



因此你的三口 PCB 实际接线可以确定为：

```text
CR6606 默认定义                你的 PCB 实际物理接口

switch port@0  = lan1   ───→   物理 WAN
switch port@1  = lan2   ───→   物理 LAN1
gmac1 / PHY4   = wan    ───→   物理 LAN2
switch port@2  = lan3   ───→   没有物理接口
```

因此目标修改就是：

```text
switch port@0 → wan
switch port@1 → lan1
gmac1 / PHY4  → lan2
port@2        → disabled
```

这比仅改 `/etc/config/network` 更底层，也正好符合你要求的“刷入新设备后天然对应”。

---

# 一、设备名称当然可以改成 `JCG Q20`

但这里要分清楚 **3 个名字**。

| 项目               | 作用                                    | 本方案              |
| ---------------- | ------------------------------------- | ---------------- |
| DTS `model`      | LuCI / `ubus call system board` 显示的型号 | `JCG Q20`        |
| DTS `compatible` | OpenWrt 的 board identity              | `jcg,q20-cr6606` |
| `DEVICE_MODEL`   | 编译 Profile / 固件元数据                    | `Q20`            |

因此刷入后：

```sh
ubus call system board
```

会看到：

```json
"model": "JCG Q20"
```

而不是：

```text
Xiaomi Mi Router CR6606
```

**单独修改 `model` 不会改变 Flash 分区，也不会改变 NAND 布局。**

真正需要谨慎的是 `compatible` / `board_name`。因为它会参与 `02_network`、`01_leds` 等 board-specific 初始化以及 sysupgrade 兼容判断。

所以我不建议简单粗暴地把：

```dts
compatible = "xiaomi,mi-router-cr6606";
```

直接换成：

```dts
compatible = "jcg,q20";
```

虽然 OpenWrt 23.05.6 本身已经有原生 `jcg,q20` 支持，而且它的 `02_network` 也正好是 `lan1 lan2` + `wan`，但**原生 JCG Q20 DTS 的 NAND 分区布局与 CR660x 不同**。原生 JCG Q20 DTS 使用自己的 partition/UBI 结构。

你的目标是：

> **保留 CR6606 的硬件/Flash/image 体系，只修正成 JCG Q20 三口设备。**

因此最干净的做法是建立：

```text
compatible = "jcg,q20-cr6606"
model = "JCG Q20"
```

也就是：

```text
CR6606 硬件基础
+
JCG Q20 身份
+
你的三口物理映射
```

---

# 二、你的 GitHub 仓库现在需要调整

我已经检查了你现在的仓库：

[OpenWrt-JCG-Q20 仓库](https://github.com/upleung/OpenWrt-JCG-Q20?utm_source=chatgpt.com)

目前仓库已经存在多个 workflow，包括：

```text
openwrt-builder.yml
openwrt-builder-jcg-q20.yml
openwrt-builder-jcg-q20-bak.yml
openwrt-builder-onecloud.yml
update-checker.yml
```

([GitHub][1])

尤其目前的 `openwrt-builder.yml` 还是：

```text
coolsnowwolf/lede
master
```

并且使用日期自动生成 Release tag。

这和你现在要求的：

> **官方 OpenWrt 23.05.6 + 固定版本 + JCG Q20 + 正规 Release 标签**

不是同一套逻辑。

## 建议

把旧的 JCG 构建 workflow 停掉，只保留一套新的：

```text
.github/workflows/build-jcg-q20.yml
```

OneCloud 那个可以保留，但不要让它和 JCG Q20 构建混在一起。

---

# 三、最终仓库结构

建议改成：

```text
OpenWrt-JCG-Q20/
│
├── .github/
│   └── workflows/
│       └── build-jcg-q20.yml
│
├── config/
│   └── jcg-q20-23.05.6.config
│
├── scripts/
│   └── apply-jcg-q20.sh
│
├── target/
│   └── linux/
│       └── ramips/
│           └── dts/
│               └── mt7621_xiaomi_mi-router-cr6606.dts
│
├── README.md
└── LICENSE
```

这套结构的优势是：

```text
你的仓库
    ↓
只保存“修改”
    ↓
GitHub Actions 每次重新拉
OpenWrt v23.05.6
    ↓
应用修改
    ↓
编译
    ↓
生成固件
    ↓
Release
```

而不是把完整几 GB 的 OpenWrt 源码塞进你的仓库。

---

# 四、第一份代码：底层 DTS

新建：

```text
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts
```

完整内容：

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

#include "mt7621_xiaomi_mi-router-cr660x.dtsi"

/ {
	/*
	 * JCG Q20 three-port hardware using the CR6606/CR660x
	 * NAND and MT7621 hardware description.
	 *
	 * Verified physical mapping:
	 *
	 * Physical WAN
	 *     -> CR660x switch port@0
	 *     -> OpenWrt wan
	 *
	 * Physical LAN1
	 *     -> CR660x switch port@1
	 *     -> OpenWrt lan1
	 *
	 * Physical LAN2
	 *     -> CR660x gmac1 / PHY4
	 *     -> OpenWrt lan2
	 *
	 * switch port@2 does not exist as a physical RJ45 port
	 * on this three-port PCB.
	 */

	compatible = "jcg,q20-cr6606", "mediatek,mt7621-soc";
	model = "JCG Q20";
};

&gmac1 {
	status = "okay";
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
```

这里非常关键：

### 我保留了

```dts
#include "mt7621_xiaomi_mi-router-cr660x.dtsi"
```

所以 CR660x 原版：

```text
NAND
Factory
MAC
Wi-Fi EEPROM
PCIe
gmac
PHY
```

等硬件定义全部继续复用。CR660x 的原始 DTS 正是通过这个 dtsi 定义这些内容，包括 Factory MAC 的读取和 `gmac1 → PHY4`。

我们只改：

```text
model
compatible
port label
port@2 status
gmac1 label
```

---

# 五、为什么 `gmac1` 必须继续用 PHY4

原版 CR660x DTS 中：

```dts
&gmac1 {
	status = "okay";
	label = "wan";
	phy-handle = <&ethphy4>;
};
```

而你当前物理 LAN2 正好识别成：

```text
wan
```

因此可以确定：

```text
物理 LAN2
    ↓
CR660x gmac1
    ↓
PHY4
```

这正是你这台三口板子的实际情况。

所以不能把 `phy-handle` 改掉。

我们只把：

```dts
label = "wan";
```

变成：

```dts
label = "lan2";
```

---

# 六、第二份代码：board 网络映射

文件：

```text
target/linux/ramips/mt7621/base-files/etc/board.d/02_network
```

不需要你把整个文件复制进仓库。

我们让脚本自动给官方 23.05.6 源码加入：

```sh
jcg,q20-cr6606)
	ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"
	;;
```

因此最终：

```text
LAN = lan1 + lan2
WAN = wan
```

这与 OpenWrt 23.05.6 本身对原生 `jcg,q20` 使用的网络分组也是一致的。([GitHub][2])

但我们不修改原版：

```text
jcg,q20
```

也不修改：

```text
xiaomi,mi-router-cr6606
```

只加入：

```text
jcg,q20-cr6606
```

这样不会污染其他设备。

---

# 七、第三份代码：LED

文件：

```text
target/linux/ramips/mt7621/base-files/etc/board.d/01_leds
```

加入：

```sh
jcg,q20-cr6606)
	ucidef_set_led_netdev "internet" "Internet" "blue:net" "wan"
	;;
```

原因是我们 DTS 继续继承 CR660x 的：

```text
blue:net
```

LED GPIO。

CR6606 原版 `01_leds` 本来就是让 `Internet` LED 跟随 `wan`。

这样修改之后：

```text
物理 WAN
   ↓
wan
   ↓
Internet LED
```

---

# 八、第四份代码：创建新的 OpenWrt Image Profile

这一点很重要。

OpenWrt 23.05.6 原版：

```make
define Device/xiaomi_mi-router-cr6606
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
endef
```

CR660x image recipe 使用：

```make
$(Device/nand)
$(Device/uimage-lzma-loader)
IMAGE_SIZE := 128512k
IMAGES += firmware.bin
```



我们不修改原来的 CR6606 Profile。

在：

```text
target/linux/ramips/image/mt7621.mk
```

末尾加入：

```make
define Device/xiaomi_mi-router-cr6606
  $(Device/xiaomi_mi-router-cr660x)
  DEVICE_VENDOR := JCG
  DEVICE_MODEL := Q20
  DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606
  SUPPORTED_DEVICES := jcg,q20-cr6606 xiaomi,mi-router-cr6606
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606
```

这里有三个关键点。

### 1. 仍然继承 CR660x

```make
$(Device/xiaomi_mi-router-cr660x)
```

所以不会重新发明 NAND 镜像格式。

### 2. 使用自己的 DTS

```make
DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606
```

### 3. 支持从现有 CR6606 固件迁移

```make
SUPPORTED_DEVICES := jcg,q20-cr6606 xiaomi,mi-router-cr6606
```

你的当前系统是：

```text
board_name = xiaomi,mi-router-cr6606
```

所以这个设置允许你从当前 CR6606 OpenWrt 转换到这个自定义固件。

---

# 九、第五份代码：自动应用上述修改的脚本

新建：

```text
scripts/apply-jcg-q20.sh
```

完整代码：

```bash
#!/usr/bin/env bash
set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DTS_SRC="$ROOT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"
DTS_DST="$OPENWRT_DIR/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts"

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

echo "==> Verify customization"

grep -q 'jcg,q20-cr6606' "$DTS_DST"
grep -q 'label = "wan"' "$DTS_DST"
grep -q 'label = "lan1"' "$DTS_DST"
grep -q 'label = "lan2"' "$DTS_DST"
grep -q 'status = "disabled"' "$DTS_DST"

grep -q 'jcg,q20-cr6606)' "$NETWORK"
grep -q 'jcg,q20-cr6606)' "$LEDS"

grep -q '^define Device/xiaomi_mi-router-cr6606$' "$IMAGE"
grep -q 'DEVICE_DTS := mt7621_xiaomi_mi-router-cr6606' "$IMAGE"

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
```

---

# 十、配置文件

新建：

```text
config/jcg-q20-23.05.6.config
```

内容：

```text
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6606=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_PACKAGE_luci=y
```

这只选择：

```text
ramips
└── mt7621
    └── xiaomi_mi-router-cr6606
```

---

# 十一、GitHub Actions：完整 Workflow

你现在最重要的就是把旧的构建 Workflow 换掉。

建立：

```text
.github/workflows/build-jcg-q20.yml
```

完整代码如下：

```yaml
name: Build OpenWrt JCG Q20

on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: "Release tag, e.g. v23.05.6-jcgq20-r1"
        required: true
        default: "v23.05.6-jcgq20-r1"
        type: string

      publish_release:
        description: "Create or update GitHub Release"
        required: true
        default: true
        type: boolean

  push:
    tags:
      - "v23.05.6-jcgq20-r*"

permissions:
  contents: write

env:
  OPENWRT_VERSION: "23.05.6"
  OPENWRT_TAG: "v23.05.6"

  PROFILE: "xiaomi_mi-router-cr6606"

  TZ: "Asia/Shanghai"
  DEBIAN_FRONTEND: "noninteractive"

concurrency:
  group: openwrt-jcg-q20-${{ github.ref }}
  cancel-in-progress: true

jobs:

  build:

    runs-on: ubuntu-22.04

    steps:

      # ======================================================
      # 1. Checkout your customization repository
      # ======================================================

      - name: Checkout customization repository
        uses: actions/checkout@v4

        with:
          fetch-depth: 0


      # ======================================================
      # 2. Build dependencies
      # ======================================================

      - name: Install build dependencies
        run: |

          sudo apt-get update

          sudo apt-get install -y \
            build-essential \
            clang \
            flex \
            bison \
            g++ \
            gawk \
            gcc-multilib \
            gettext \
            git \
            libncurses5-dev \
            libncursesw5-dev \
            libssl-dev \
            libelf-dev \
            libpython3-dev \
            python3 \
            python3-distutils \
            python3-setuptools \
            rsync \
            unzip \
            zlib1g-dev \
            file \
            wget \
            curl \
            device-tree-compiler \
            ccache \
            time


      # ======================================================
      # 3. Clone EXACT OpenWrt 23.05.6
      # ======================================================

      - name: Clone exact OpenWrt 23.05.6
        run: |

          git clone \
            --depth 1 \
            --branch "${OPENWRT_TAG}" \
            https://github.com/openwrt/openwrt.git \
            openwrt

          cd openwrt

          echo "OpenWrt tag:"
          git describe --tags --exact-match

          echo "OpenWrt commit:"
          git rev-parse HEAD


      # ======================================================
      # 4. Official OpenWrt feeds
      # ======================================================

      - name: Update official OpenWrt feeds
        working-directory: openwrt
        run: |

          ./scripts/feeds update -a

          ./scripts/feeds install -a


      # ======================================================
      # 5. Apply JCG Q20 modifications
      # ======================================================

      - name: Apply JCG Q20 hardware customization
        run: |

          chmod +x scripts/apply-jcg-q20.sh

          ./scripts/apply-jcg-q20.sh openwrt


      # ======================================================
      # 6. Load config
      # ======================================================

      - name: Load JCG Q20 configuration
        working-directory: openwrt
        run: |

          cp \
            ../config/jcg-q20-23.05.6.config \
            .config

          make defconfig


      # ======================================================
      # 7. Verify configuration
      # ======================================================

      - name: Verify target and DTS
        working-directory: openwrt
        run: |

          echo
          echo "============================================"
          echo "TARGET PROFILE"
          echo "============================================"

          grep \
            '^CONFIG_TARGET_.*DEVICE.*=y' \
            .config

          echo
          echo "============================================"
          echo "IMAGE PROFILE"
          echo "============================================"

          grep -n \
            -A8 \
            -B2 \
            'define Device/xiaomi_mi-router-cr6606' \
            target/linux/ramips/image/mt7621.mk

          echo
          echo "============================================"
          echo "DTS"
          echo "============================================"

          sed -n \
            '1,220p' \
            target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts

          echo
          echo "============================================"
          echo "NETWORK BOARD"
          echo "============================================"

          grep -n \
            -A4 \
            -B2 \
            'jcg,q20-cr6606)' \
            target/linux/ramips/mt7621/base-files/etc/board.d/02_network


      # ======================================================
      # 8. Download sources first
      # ======================================================

      - name: Download package sources
        working-directory: openwrt
        run: |

          make download -j8

          find dl \
            -type f \
            -size -1024c \
            -print \
            -delete


      # ======================================================
      # 9. Build
      # ======================================================

      - name: Build OpenWrt
        working-directory: openwrt
        run: |

          echo "CPU threads:"
          nproc

          make \
            -j"$(nproc)" \
            V=s \
            || make \
            -j1 \
            V=s


      # ======================================================
      # 10. Verify firmware
      # ======================================================

      - name: Collect generated firmware
        working-directory: openwrt
        run: |

          OUTDIR="bin/targets/ramips/mt7621"

          test -d "$OUTDIR"

          echo
          echo "============================================"
          echo "TARGET OUTPUT"
          echo "============================================"

          ls -lah "$OUTDIR"

          mapfile -t FILES < <(
            find "$OUTDIR" \
              -maxdepth 1 \
              -type f \
              \( \
                -name '*xiaomi_mi-router-cr6606*.bin' \
                -o \
                -name '*xiaomi_mi-router-cr6606*.json' \
              \) \
              -print
          )

          test "${#FILES[@]}" -gt 0

          mkdir -p ../release

          cp \
            "${FILES[@]}" \
            ../release/

          # Build metadata
          for f in \
            profiles.json \
            config.buildinfo \
            feeds.buildinfo \
            version.buildinfo
          do

            if [ -f "$OUTDIR/$f" ]; then
              cp \
                "$OUTDIR/$f" \
                ../release/
            fi

          done

          cd ../release

          sha256sum \
            *.bin \
            > SHA256SUMS


      # ======================================================
      # 11. Release metadata
      # ======================================================

      - name: Prepare release metadata
        id: release_meta

        env:

          MANUAL_TAG: ${{ inputs.release_tag }}
          EVENT_NAME: ${{ github.event_name }}
          EVENT_TAG: ${{ github.ref_name }}

          PUBLISH: ${{ inputs.publish_release }}

        run: |

          if [ "$EVENT_NAME" = "push" ]; then

            RELEASE_TAG="$EVENT_TAG"
            SHOULD_PUBLISH=true

          else

            RELEASE_TAG="$MANUAL_TAG"
            SHOULD_PUBLISH="$PUBLISH"

          fi


          case "$RELEASE_TAG" in

            v23.05.6-jcgq20-r*)
              ;;

            *)
              echo "Invalid release tag:"
              echo "$RELEASE_TAG"
              exit 1
              ;;

          esac


          echo \
            "release_tag=$RELEASE_TAG" \
            >> "$GITHUB_OUTPUT"

          echo \
            "should_publish=$SHOULD_PUBLISH" \
            >> "$GITHUB_OUTPUT"


          cat > release/BUILD_INFO.txt <<EOF

Project: upleung/OpenWrt-JCG-Q20

OpenWrt version:
${OPENWRT_VERSION}

OpenWrt tag:
${OPENWRT_TAG}

Profile:
${PROFILE}

Runtime model:
JCG Q20

Runtime board:
jcg,q20-cr6606

Physical port mapping:

WAN:
switch port@0 -> wan

LAN1:
switch port@1 -> lan1

LAN2:
gmac1 / PHY4 -> lan2

Unused:
switch port@2

Build commit:
${GITHUB_SHA}

Build time UTC:
$(date -u '+%Y-%m-%d %H:%M:%S')

EOF


      # ======================================================
      # 12. Actions artifact
      # ======================================================

      - name: Upload Actions artifact
        uses: actions/upload-artifact@v4

        with:

          name: >
            OpenWrt-${{ env.OPENWRT_VERSION }}-JCG-Q20

          path: |
            release/

          if-no-files-found: error

          retention-days: 30


      # ======================================================
      # 13. Create / update GitHub Release
      # ======================================================

      - name: Create or update GitHub Release

        if:
          steps.release_meta.outputs.should_publish == 'true'

        env:

          GH_TOKEN: ${{ github.token }}

          RELEASE_TAG:
            ${{ steps.release_meta.outputs.release_tag }}

        run: |

          if gh release view "$RELEASE_TAG" \
            >/dev/null 2>&1
          then

            echo "Release exists:"
            echo "$RELEASE_TAG"

            gh release upload \
              "$RELEASE_TAG" \
              release/* \
              --clobber

          else

            echo "Create release:"
            echo "$RELEASE_TAG"

            gh release create \
              "$RELEASE_TAG" \
              release/* \
              --target "$GITHUB_SHA" \
              --title \
                "OpenWrt ${OPENWRT_VERSION} - JCG Q20 ${RELEASE_TAG#v}" \
              --notes \
                "Official OpenWrt ${OPENWRT_VERSION} source.

Physical port mapping:

WAN -> wan
LAN1 -> lan1
LAN2 -> lan2

This firmware keeps the CR660x NAND/image architecture,
factory MAC/EEPROM handling, and other CR660x hardware
definitions. Only the JCG Q20 identity and verified
three-port mapping are adapted.

See BUILD_INFO.txt and SHA256SUMS." \
              --latest

          fi
```

---

# 十二、这里为什么我坚持 `v23.05.6`

你原来 workflow 用：

```yaml
git clone ... -b openwrt-23.05 --depth 1
```

这实际上是在拉一个**移动中的分支**。

而你的目标其实是：

> 我以后重新构建同一个版本，结果应该可重复。

因此：

```yaml
OPENWRT_TAG: "v23.05.6"
```

然后：

```bash
git clone --branch v23.05.6
```

才是正确做法。

OpenWrt 官方文档明确显示 23.05.6 是该系列最后的 23.05 版本；同时当前官方状态已经把 23.05 标成 EOL。([OpenWrt][3])

所以：

### 当前开发/验证

```text
23.05.6
```

完全可以。

### 长期正式使用

以后端口修复验证成功，再考虑迁移到较新的 OpenWrt 系列。

现在不要一边解决硬件端口问题，一边同时升级大版本。

---

# 十三、Release 标签怎么管理

我建议以后永远采用：

```text
v<OpenWrt版本>-jcgq20-r<修订号>
```

例如：

```text
v23.05.6-jcgq20-r1
v23.05.6-jcgq20-r2
v23.05.6-jcgq20-r3
```

含义：

```text
v23.05.6
    ↓
OpenWrt 上游版本

jcgq20
    ↓
你的硬件版本

r1
    ↓
你的适配修订版本
```

例如：

### 第一次端口映射成功

```text
v23.05.6-jcgq20-r1
```

### 以后只改 LED

```text
v23.05.6-jcgq20-r2
```

### 以后修 Wi-Fi

```text
v23.05.6-jcgq20-r3
```

### OpenWrt 升级到 24.10.4

则重新开始：

```text
v24.10.4-jcgq20-r1
```

不要继续：

```text
v23.05.6-jcgq20-r4
```

去代表一个 24.10.4 固件。

---

# 十四、第一次构建怎么操作

## 1. 删除/停用旧 JCG workflow

至少停用：

```text
.github/workflows/openwrt-builder-jcg-q20.yml
.github/workflows/openwrt-builder-jcg-q20-bak.yml
.github/workflows/openwrt-builder.yml
```

否则可能出现：

```text
Workflow A
    ↓
23.05 branch

Workflow B
    ↓
lede

Workflow C
    ↓
你的 JCG Q20
```

最终 Release 和 Artifact 混在一起。

---

# 十五、把四个文件上传到仓库

你最终需要：

```text
.github/workflows/build-jcg-q20.yml
config/jcg-q20-23.05.6.config
scripts/apply-jcg-q20.sh
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts
```

我已经把这一套整理成可直接放入仓库的压缩包：

[下载 JCG Q20 GitHub Actions 构建套件](sandbox:/mnt/data/OpenWrt-JCG-Q20-GHA-setup.zip)

压缩包内包含：

```text
.github/workflows/build-jcg-q20.yml
config/jcg-q20-23.05.6.config
scripts/apply-jcg-q20.sh
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts
README.md
```

---

# 十六、Commit

建议第一次：

```text
feat: add JCG Q20 CR6606-based hardware support
```

不要直接叫：

```text
fix
```

因为这是新增硬件 Profile。

---

# 十七、第一次建议不要直接 Release

你的第一次运行建议：

GitHub：

```text
Actions
→ Build OpenWrt JCG Q20
→ Run workflow
```

填写：

```text
release_tag

v23.05.6-jcgq20-r1
```

然后：

```text
publish_release = false
```

第一次先让它：

```text
编译
↓
Actions Artifact
```

而不是立即发布 Release。

因为第一次真正应该检查的是：

```text
DTS 能否编译
Profile 能否识别
固件能否生成
```

---

# 十八、必须检查 Actions 日志里的这几项

### ① Profile

应该：

```text
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt7621=y
CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6606=y
```

---

### ② DTS

应该看到：

```text
compatible = "jcg,q20-cr6606", "mediatek,mt7621-soc";
model = "JCG Q20";
```

以及：

```text
port@0
    label = "wan"

port@1
    label = "lan1"

port@2
    status = "disabled"
```

以及：

```text
&gmac1
    label = "lan2"
    phy-handle = <&ethphy4>
```

---

# 十九、最终生成的文件

官方 CR6606 在 23.05.6 本来就有：

```text
initramfs-kernel.bin
squashfs-firmware.bin
squashfs-sysupgrade.bin
```

例如官方 CR6606 的 23.05.6 文件列表就是：

```text
xiaomi_mi-router-cr6606-initramfs-kernel.bin
xiaomi_mi-router-cr6606-squashfs-firmware.bin
xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
```

([OpenWrt 下载][4])

你的最终文件会类似：

```text
openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-initramfs-kernel.bin

openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-firmware.bin

openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
```

---

# 二十、三个固件不要混用

这非常重要。

| 文件                        | 用途                   |
| ------------------------- | -------------------- |
| `initramfs-kernel.bin`    | 临时启动/救援/测试           |
| `squashfs-firmware.bin`   | CR6606 这类厂商/底层固件刷写场景 |
| `squashfs-sysupgrade.bin` | 已经运行 OpenWrt 时升级     |

你现在已经在：

```text
OpenWrt 24.10.4
```

里面，而且 `ubus` 显示：

```text
model = Xiaomi Mi Router CR6606
board_name = xiaomi,mi-router-cr6606
```



所以**从你现在这个 OpenWrt 环境第一次迁移到自定义版本，优先使用 `squashfs-sysupgrade.bin`，并建议 `-n` 不保留旧配置。**

例如上传：

```bash
scp openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin root@192.168.50.1:/tmp/
```

然后：

```bash
sysupgrade -n \
/tmp/openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-squashfs-sysupgrade.bin
```

**第一次不要保留 24.10.4 的配置。**

因为你是在：

```text
24.10.4
↓
23.05.6
```

做版本回退，同时又改变了 board identity。

---

# 二十一、刷成功以后最关键的检查

### 1. 型号

```bash
ubus call system board
```

应该出现：

```json
{
    "model": "JCG Q20",
    "board_name": "jcg,q20-cr6606"
}
```

---

### 2. 网络设备

```bash
ip link
```

应该只看到：

```text
wan
lan1
lan2
```

不应该再作为有效物理 RJ45 使用：

```text
lan3
```

---

### 3. `/etc/config/network`

```bash
uci show network
```

应该类似：

```text
network.@device[0].ports='lan1' 'lan2'

network.wan.device='wan'
network.wan.proto='dhcp'
```

也就是：

```text
LAN = lan1 + lan2
WAN = wan
```

---

# 二十二、最后做物理口验证

这一步不能省。

### 插 WAN

```bash
ip link show wan
```

应该：

```text
LOWER_UP
```

---

### 插 LAN1

```bash
ip link show lan1
```

应该：

```text
LOWER_UP
```

---

### 插 LAN2

```bash
ip link show lan2
```

应该：

```text
LOWER_UP
```

最终就是：

```text
┌─────────────┬──────────────────────┐
│ 物理接口    │ Linux / OpenWrt      │
├─────────────┼──────────────────────┤
│ WAN         │ wan                  │
│ LAN1        │ lan1                 │
│ LAN2        │ lan2                 │
└─────────────┴──────────────────────┘
```

---

# 二十三、为什么这个方案比直接修改 `/etc/config/network` 更合适

你现在的配置：

```text
wan  → wan
lan  → br-lan
       ├── lan1
       ├── lan2
       └── lan3
```

从系统配置层面看其实没有语法错误。

真正的问题在更下面：

```text
物理 WAN
   ↓
switch port@0
   ↓
CR6606 DTS label = lan1
```

所以你仅仅改：

```text
/etc/config/network
```

解决的是：

```text
哪个接口负责 WAN
```

而不是：

```text
哪个物理口叫 WAN
```

你要的是后者。

所以 DTS：

```dts
port@0 {
	label = "wan";
};
```

才是关键。

---

# 二十四、最终的软件架构

你最后这个项目实际上会形成：

```text
                    GitHub
                       │
                       │
           upleung/OpenWrt-JCG-Q20
                       │
                       ▼
              GitHub Actions
                       │
                       ▼
             OpenWrt v23.05.6
                       │
                       ▼
        ┌─────────────────────────┐
        │ CR660x base DTS         │
        │                         │
        │ NAND                    │
        │ Factory                 │
        │ MAC                     │
        │ Wi-Fi EEPROM            │
        │ PCIe                    │
        │ MT7621                  │
        └────────────┬────────────┘
                     │
                     ▼
             JCG Q20 custom DTS
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       port@0      port@1      gmac1
          │          │          │
          ▼          ▼          ▼
         WAN        LAN1       LAN2
```

然后：

```text
GitHub Actions
      ↓
Compile
      ↓
SHA256SUMS
      ↓
BUILD_INFO.txt
      ↓
Artifact
      ↓
GitHub Release
```

---

# 二十五、你现有仓库还有一个地方建议调整

你当前仓库 README 已经写成：

> “适用于JCG Q20的官方原版OpenWrt固件，仅修复物理端口映射和设备名称，其它均保持原生未修改”

([GitHub][5])

这个定位其实是正确的。

但是现在实际 workflow 里还有：

```text
coolsnowwolf/lede
```

以及：

```text
openwrt-23.05 branch
```

之类的旧逻辑。

因此新的版本应该明确写成：

```text
Official OpenWrt 23.05.6
+
CR6606 hardware base
+
JCG Q20 identity
+
3-port physical mapping fix
+
No third-party feed
+
No extra application modification
```

这样这个仓库以后会非常清晰。

---

# 二十六、一个重要的现实问题

**23.05.6 现在已经 EOL。** OpenWrt 官方明确标注 23.05 不再获得安全更新。([OpenWrt][6])

但你当前阶段仍然使用 23.05.6 是合理的，因为你的目标首先是：

```text
确认硬件移植
↓
确认端口
↓
确认 JCG Q20 身份
↓
确认稳定刷机
```

不要把“硬件适配”和“OpenWrt 大版本升级”同时做。

---

## 最终推荐方案

你的项目现在不要走：

```text
CR6606 → 直接改 /etc/config/network
```

也不要走：

```text
CR6606 → 二进制解包 → 修改 squashfs → 再封装
```

而是正式固定成：

```text
OpenWrt 23.05.6
       ↓
CR660x 原始 DTS
       ↓
新增 mt7621_xiaomi_mi-router-cr6606.dts
       ↓
compatible = "jcg,q20-cr6606"
model = "JCG Q20"
       ↓
port@0 → wan
port@1 → lan1
gmac1/PHY4 → lan2
port@2 → disabled
       ↓
自定义 Device/xiaomi_mi-router-cr6606
       ↓
GitHub Actions
       ↓
v23.05.6-jcgq20-r1
       ↓
GitHub Release
```

而且这个设计还有一个实际好处：**你以后升级 OpenWrt，只需要把 `OPENWRT_TAG` 从 `v23.05.6` 改成目标版本，并针对新版本源码重新验证这几个修改点，不需要重新研究整个硬件。**

你现在最应该做的是先跑 **`v23.05.6-jcgq20-r1` 的第一次编译**。第一次编译只要成功，下一步就是验证生成 DTB 中的 `port@0/port@1/gmac1` 是否确实进入最终 kernel，然后再刷到这台三口设备。

[1]: https://github.com/upleung/OpenWrt-JCG-Q20/tree/main/.github/workflows "OpenWrt-JCG-Q20/.github/workflows at main · upleung/OpenWrt-JCG-Q20 · GitHub"
[2]: https://raw.githubusercontent.com/openwrt/openwrt/v23.05.6/target/linux/ramips/mt7621/base-files/etc/board.d/02_network "raw.githubusercontent.com"
[3]: https://openwrt.org/zh/releases/23.05/start?utm_source=chatgpt.com "[OpenWrt Wiki] OpenWrt 23.05"
[4]: https://downloads.openwrt.org/releases/23.05.6/targets/ramips/mt7621/ "Index of /releases/23.05.6/targets/ramips/mt7621/"
[5]: https://github.com/upleung/OpenWrt-JCG-Q20 "GitHub - upleung/OpenWrt-JCG-Q20: 适用于JCG Q20的官方原版OpenWrt固件，仅修复物理端口映射和设备名称，其它均保持原生未修改（使用CR6606官方原版OpenWrt固件进行适配） · GitHub"
[6]: https://openwrt.org/releases/23.05/start?utm_source=chatgpt.com "[OpenWrt Wiki] OpenWrt 23.05"
