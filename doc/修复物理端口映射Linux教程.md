根据你这份实机输出，现在可以把问题定性得比较准确：

**你的三口设备不是 `/etc/config/network` 单纯配置错了，而是这块三口 PCB 的物理 RJ45 实际接线，与 OpenWrt 对 CR6606 的默认 DTS 端口命名不一致。**

你实测的是：

| 机身物理口 | 当前 OpenWrt 识别 |
| ----- | ------------- |
| WAN   | `lan1`        |
| LAN1  | `lan2`        |
| LAN2  | `wan`         |

而且这台机器实际上只有 **3 个 RJ45**，却套用了 CR6606 的四口硬件描述。你上传的当前配置也明确显示系统实际建立的是 `wan`、`lan1`、`lan2`、`lan3` 这一套逻辑，而 `br-lan` 默认加入 `lan1 lan2 lan3`。 

OpenWrt 的 MT7621 DSA 体系中，`port@0`、`port@1`、`port@2` 等是交换芯片物理端口节点，而 `gmac1` 可以作为独立的 MAC 设备；CR660x 的 DTS 正是通过这些节点给端口命名。([GitHub][1])

所以你这次应该做的不是“交换 `/etc/config/network` 里的几个字符串”，而是：

```text
物理 RJ45
   ↓
MT7621 实际 port/gmac
   ↓
DTS label
   ↓
Linux 网络设备
   ↓
/etc/config/network
```

最终固定成：

```text
物理 WAN  → wan
物理 LAN1 → lan1
物理 LAN2 → lan2
```

---

# 一、最终应该怎么改

根据你已经确认的物理对应关系：

```text
当前：

物理 WAN  → port@0 → lan1
物理 LAN1 → port@1 → lan2
物理 LAN2 → gmac1  → wan
```

因此目标应该是：

```text
物理 WAN  → port@0 → wan
物理 LAN1 → port@1 → lan1
物理 LAN2 → gmac1  → lan2
```

同时：

```text
port@2 → 不使用
```

因为你的设备只有三个物理网口。

这和你现在的实际现象是完全吻合的。

CR660x 原始 DTS 使用 `gmac1` 作为 `wan`，并把 switch 的 `port@0/1/2` 命名为 `lan1/lan2/lan3`；这也是为什么你的三口变种会出现这种“整体错位”的结果。([OpenWrt Git][2])

---

# 二、不要直接修改官方 CR6606 DTS

这是最重要的一点。

**不要这样做：**

```text
直接修改：
mt7621_xiaomi_mi-router-cr6606.dts
```

然后把标准 CR6606 改坏。

因为标准 CR6606 有 4 个物理口，而你的设备只有 3 个。

正确方式是：

```text
保留：

xiaomi,mi-router-cr6606

新增：

xiaomi,mi-router-cr6606-3port
```

这样最终 OpenWrt 里面会出现两个不同硬件 Profile：

```text
Xiaomi Mi Router CR6606
Xiaomi Mi Router CR6606 3-Port
```

这样标准 CR6606 不受影响。

---

# 三、第一步：准备 OpenWrt 23.05.6 源码

建议直接使用你原本指定的 **23.05.6**，不要现在突然换到 24.10 / 25.x。

官方 Firmware Selector 明确提供 CR6606 的 23.05 系列固件，目标就是：

```text
ramips / mt7621
```

([OpenWrt固件选择器][3])

在 Ubuntu / WSL 中：

```bash
sudo apt update

sudo apt install -y \
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
  libssl-dev \
  python3 \
  python3-distutils \
  rsync \
  unzip \
  zlib1g-dev \
  file \
  wget \
  curl \
  time \
  subversion \
  xsltproc \
  swig \
  libelf-dev \
  libpython3-dev \
  python3-setuptools \
  python3-yaml
```

然后：

```bash
cd ~
git clone --branch v23.05.6 --depth 1 https://github.com/openwrt/openwrt.git openwrt-23.05.6
cd ~/openwrt-23.05.6
```

确认：

```bash
git describe --tags
```

应看到：

```text
v23.05.6
```

---

# 四、第二步：先确认官方 CR6606 的 DTS 架构

官方 CR6606 并不是一个完整独立 DTS，而是：

```text
mt7621_xiaomi_mi-router-cr6606.dts
                ↓
mt7621_xiaomi_mi-router-cr660x.dtsi
```

CR6606 自身 DTS 本来只有很少内容，主要是指定：

```text
compatible
model
```

这个结构可以从 OpenWrt 最初加入 CR660x 支持的提交中直接看到。([OpenWrt 邮件列表][4])

也就是说，我们最好直接复用：

```text
mt7621_xiaomi_mi-router-cr660x.dtsi
```

而不是复制整份硬件 DTS。

---

# 五、第三步：建立你的“三口版 DTS”

执行：

```bash
cd ~/openwrt-23.05.6

cp \
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606.dts \
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606-3port.dts
```

然后编辑：

```bash
nano target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606-3port.dts
```

把内容**完整替换成下面这个：**

```dts
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT

#include "mt7621_xiaomi_mi-router-cr660x.dtsi"

/ {
	/*
	 * Three-port hardware variant based on Xiaomi CR6606 platform.
	 *
	 * Physical ports:
	 *   WAN  -> MT7621 switch port 0
	 *   LAN1 -> MT7621 switch port 1
	 *   LAN2 -> MT7621 GMAC1 / external PHY
	 */
	compatible = "xiaomi,mi-router-cr6606-3port", "mediatek,mt7621-soc";
	model = "Xiaomi Mi Router CR6606 3-Port";
};

/*
 * Physical WAN is connected to MT7621 switch port 0.
 */
&switch0 {
	ports {
		port@0 {
			status = "okay";
			label = "wan";
		};

		/*
		 * Physical LAN1
		 */
		port@1 {
			status = "okay";
			label = "lan1";
		};

		/*
		 * No physical RJ45 for switch port 2 on this hardware.
		 */
		port@2 {
			status = "disabled";
		};
	};
};

/*
 * Physical LAN2 is connected to GMAC1.
 *
 * The original CR660x DTS labels GMAC1 as "wan".
 * For this three-port hardware, rename it to "lan2".
 */
&gmac1 {
	status = "okay";
	label = "lan2";
};
```

这里有一个非常关键的点：

### 不要修改：

```dts
phy-handle = <&ethphy4>;
```

也不要改：

```dts
nvmem-cells
nvmem-cell-names
```

因为这些属于 PHY/MAC 和设备校准数据。

我们这里只改：

```dts
label
```

以及：

```dts
port@2 status
```

这是最干净的处理方式。

---

# 六、为什么这样改是对的

MT7621 通用 DTS 的交换机结构本身就是：

```text
port@0 → ethphy0
port@1 → ethphy1
port@2 → ethphy2
port@3 → ethphy3
port@4 → ethphy4
port@6 → CPU / GMAC
```

OpenWrt 的通用 MT7621 DTS 对这些 port 和 PHY 的绑定就是这样定义的。([GitHub][1])

而 CR660x 的原始设计是：

```text
gmac1 = wan
port@0 = lan1
port@1 = lan2
port@2 = lan3
```

这正是你现在：

```text
物理 WAN  → lan1
物理 LAN1 → lan2
物理 LAN2 → wan
```

的根源。

现在我们把它改为：

```text
port@0 = wan
port@1 = lan1
gmac1   = lan2
```

于是：

```text
物理 WAN
   ↓
port@0
   ↓
wan

物理 LAN1
   ↓
port@1
   ↓
lan1

物理 LAN2
   ↓
gmac1
   ↓
lan2
```

这就是你需要的底层固定映射。

---

# 七、第四步：修改 `02_network`

这是第二个必须改的地方。

原因很简单：

你现在只有：

```text
wan
lan1
lan2
```

但是官方 CR6606 的 board 配置默认是：

```text
lan1 lan2 lan3
```

官方 `02_network` 对 CR6606 / CR6608 / CR6609 目前就是统一使用：

```sh
ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
```

([OpenWrt Git][5])

所以我们必须给自己的：

```text
xiaomi,mi-router-cr6606-3port
```

单独设置：

```text
LAN = lan1 lan2
WAN = wan
```

执行：

```bash
nano target/linux/ramips/mt7621/base-files/etc/board.d/02_network
```

找到：

```sh
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
	ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
	;;
```

**不要修改原来的标准 CR6606。**

改成：

```sh
xiaomi,mi-router-cr6606-3port)
	ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"
	;;
	
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
	ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
	;;
```

最终大概就是：

```sh
ramips_setup_interfaces()
{
	local board="$1"

	case $board in

	# ...

	xiaomi,mi-router-cr6606-3port)
		ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"
		;;

	xiaomi,mi-router-cr6606|\
	xiaomi,mi-router-cr6608|\
	xiaomi,mi-router-cr6609)
		ucidef_set_interfaces_lan_wan "lan1 lan2 lan3" "wan"
		;;

	# ...

	esac
}
```

---

# 八、第五步：修改 WAN LED

这个不是端口映射的核心，但建议一起改。

否则你的三口版：

```text
wan
```

已经变成正确的 WAN 设备，但 `01_leds` 对你的新 board name 不认识。

官方 CR6606 的 LED 配置目前也是通过：

```sh
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
	ucidef_set_led_netdev "internet" "Internet" "blue:net" "wan"
	;;
```

([GitHub][6])

编辑：

```bash
nano target/linux/ramips/mt7621/base-files/etc/board.d/01_leds
```

把：

```sh
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
```

改成：

```sh
xiaomi,mi-router-cr6606-3port|\
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
```

也就是：

```sh
xiaomi,mi-router-cr6606-3port|\
xiaomi,mi-router-cr6606|\
xiaomi,mi-router-cr6608|\
xiaomi,mi-router-cr6609)
	ucidef_set_led_netdev "internet" "Internet" "blue:net" "wan"
	;;
```

这样 WAN LED 仍然跟着真正的：

```text
wan
```

走。

---

# 九、第六步：增加新的固件 Profile

这是很多教程容易遗漏的地方。

现在 OpenWrt 的 MT7621 镜像定义里，CR660x 使用一个公共模板：

```text
Device/xiaomi_mi-router-cr660x
```

然后：

```text
Device/xiaomi_mi-router-cr6606
Device/xiaomi_mi-router-cr6608
Device/xiaomi_mi-router-cr6609
```

继承这个模板。([GitHub][7])

因此我们新增：

```text
xiaomi_mi-router-cr6606-3port
```

编辑：

```bash
nano target/linux/ramips/image/mt7621.mk
```

找到：

```make
define Device/xiaomi_mi-router-cr6606
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606
```

紧接着增加：

```make
define Device/xiaomi_mi-router-cr6606-3port
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
	DEVICE_VARIANT := 3-Port
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606-3port
```

所以最终是：

```make
define Device/xiaomi_mi-router-cr6606
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606

define Device/xiaomi_mi-router-cr6606-3port
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
	DEVICE_VARIANT := 3-Port
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606-3port

define Device/xiaomi_mi-router-cr6608
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6608
endef
TARGET_DEVICES += xiaomi_mi-router-cr6608
```

---

# 十、第七步：这里不要修改 Flash 分区

这是另外一个非常重要的安全点。

CR660x 固件使用的是 NAND 模板：

```text
Device/nand
Device/uimage-lzma-loader
```

以及：

```text
IMAGE_SIZE := 128512k
```

并生成：

```text
firmware.bin
```

([GitHub][7])

所以你这次：

**不要碰：**

```text
partition
mtd
firmware size
kernel size
NAND offset
factory
```

你只是修改：

```text
DTS port mapping
```

因此 Flash 布局应该保持官方完全一致。

---

# 十一、第八步：检查 DTS 是否有语法错误

先执行：

```bash
make defconfig
```

然后：

```bash
make target/linux/compile V=s
```

如果 DTS 出现错误，会在这里直接暴露。

更直接一点，可以搜索：

```bash
grep -R "mi-router-cr6606-3port" -n \
target/linux/ramips
```

应该能看到：

```text
target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr6606-3port.dts
target/linux/ramips/base-files/etc/board.d/02_network
target/linux/ramips/base-files/etc/board.d/01_leds
target/linux/ramips/image/mt7621.mk
```

---

# 十二、第九步：设置编译目标

执行：

```bash
make menuconfig
```

选择：

```text
Target System
    MediaTek Ralink MIPS

Subtarget
    MT7621

Target Profile
    Xiaomi Mi Router CR6606 3-Port
```

这里你应该能看到：

```text
Xiaomi Mi Router CR6606 3-Port
```

如果看不到，说明：

```text
mt7621.mk
```

里的：

```make
TARGET_DEVICES += xiaomi_mi-router-cr6606-3port
```

没有正确生效。

---

# 十三、第十步：建议不要一次编译所有包

先做最小验证：

```bash
make defconfig
make -j$(nproc) target/linux/compile V=s
```

成功以后：

```bash
make -j$(nproc) V=s
```

如果你的机器 CPU 核心较少：

```bash
make -j4 V=s
```

更稳。

---

# 十四、第十一步：最终固件在哪里

成功以后：

```bash
ls -lh bin/targets/ramips/mt7621/
```

你应该看到类似：

```text
openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-3port-squashfs-firmware.bin
```

以及：

```text
openwrt-23.05.6-ramips-mt7621-xiaomi_mi-router-cr6606-3port-squashfs-sysupgrade.bin
```

因为它仍然使用 CR660x 的 NAND image 模板。

官方 OpenWrt 也明确区分：

```text
FIRMWARE
SYSUPGRADE
```

两种 image 类型。([OpenWrt固件选择器][3])

---

# 十五、第十二步：第一次刷机前必须做验证

我强烈建议你**不要编译完成后直接刷**。

先检查生成的 DTB。

编译后：

```bash
find build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/ \
-name '*cr6606-3port*.dtb' -o -name '*cr6606-3port*.dtbo'
```

然后也可以在生成过程中搜索：

```bash
find build_dir -type f | grep cr6606-3port
```

---

# 十六、最重要的验证：检查最终 DTB

安装：

```bash
sudo apt install -y device-tree-compiler
```

然后：

```bash
dtc -I dtb -O dts \
build_dir/target-mipsel_24kc_musl/linux-ramips_mt7621/*.dtb \
> /tmp/cr6606-3port-final.dts
```

如果路径不同，就：

```bash
find build_dir -name '*.dtb' | grep cr6606
```

然后检查：

```bash
grep -n -A8 -B3 'port@0' /tmp/cr6606-3port-final.dts
```

应该看到：

```dts
port@0 {
	status = "okay";
	reg = <0x00>;
	label = "wan";
	...
};
```

再：

```bash
grep -n -A8 -B3 'port@1' /tmp/cr6606-3port-final.dts
```

应该是：

```dts
port@1 {
	status = "okay";
	reg = <0x01>;
	label = "lan1";
	...
};
```

再：

```bash
grep -n -A8 -B3 'port@2' /tmp/cr6606-3port-final.dts
```

应该：

```dts
port@2 {
	status = "disabled";
	reg = <0x02>;
	...
};
```

最后检查 GMAC1：

```bash
grep -n -A15 -B3 'gmac@1' /tmp/cr6606-3port-final.dts
```

应该看到：

```dts
label = "lan2";
```

### 这四个结果必须同时成立：

```text
port@0 = wan
port@1 = lan1
port@2 = disabled
gmac1  = lan2
```

这是整个修改的核心。

---

# 十七、刷入后应该看到什么

刷完以后：

```bash
ubus call system board
```

应该：

```json
{
    "model": "Xiaomi Mi Router CR6606 3-Port",
    "board_name": "xiaomi,mi-router-cr6606-3port"
}
```

然后：

```bash
ip -br link
```

应该类似：

```text
eth0
wan
lan1@eth0
lan2@eth0
br-lan
```

而不再应该有：

```text
lan3
```

---

# 十八、最重要的最终物理验证

拿网线逐个插：

### 插物理 WAN

```bash
ip -br link
```

预期：

```text
wan    UP
```

而：

```text
lan1
lan2
```

不应该跟着变成 UP。

---

### 插物理 LAN1

预期：

```text
lan1@eth0    UP
```

---

### 插物理 LAN2

预期：

```text
lan2@eth0    UP
```

---

最终必须得到：

```text
┌─────────────┬───────────────┐
│ 物理接口    │ OpenWrt       │
├─────────────┼───────────────┤
│ WAN         │ wan           │
│ LAN1        │ lan1          │
│ LAN2        │ lan2          │
└─────────────┴───────────────┘
```

这才算真正修复。

---

# 十九、不要用 `swconfig` 了

你上传的结果里：

```text
swconfig list
```

没有任何输出，而且：

```text
swconfig dev switch0 show
```

直接失败；`bridge` 和 `ethtool` 也不存在。

这并不说明底层交换机“不存在”。

这是因为你运行的是 **DSA 架构**，而不是老的 `swconfig` 管理方式。

你当前网络设备：

```text
wan
lan1@eth0
lan2@eth0
```

以及：

```text
br-lan
```

本身就是 DSA 风格的设备呈现。

所以不要再尝试这种：

```bash
swconfig dev switch0 set ...
```

来解决这个问题。

**你的修复点就是 DTS。**

---

# 二十、不要修改 MAC 地址

这一点也非常重要。

你当前设备：

```text
eth0
wan
lan1
lan2
```

看到的 MAC 都是：

```text
50:33:f0:43:cf:54
```

这是当前 DSA/GSMAC 的正常呈现方式。

我们这次不要碰：

```text
factory
EEPROM
MAC address
nvmem
```

尤其不要为了“让 WAN 变成 LAN2”去修改 MAC。

**端口名称和 MAC 地址是两个完全不同的问题。**

---

# 二十一、最核心的完整修改版

实际上，你最后真正需要改的只有三个逻辑层。

## ① DTS：真正的硬件端口映射

```dts
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

&gmac1 {
	status = "okay";
	label = "lan2";
};
```

## ② board.d：告诉 OpenWrt 三口 LAN/WAN 分组

```sh
xiaomi,mi-router-cr6606-3port)
	ucidef_set_interfaces_lan_wan "lan1 lan2" "wan"
	;;
```

## ③ image：建立单独固件 Profile

```make
define Device/xiaomi_mi-router-cr6606-3port
	$(Device/xiaomi_mi-router-cr660x)
	DEVICE_MODEL := Mi Router CR6606
	DEVICE_VARIANT := 3-Port
endef
TARGET_DEVICES += xiaomi_mi-router-cr6606-3port
```

---

# 二十二、我建议你实际采用的目录结构

最终你的 OpenWrt 源码里应该是：

```text
openwrt-23.05.6/
└── target/
    └── linux/
        └── ramips/
            ├── dts/
            │   ├── mt7621_xiaomi_mi-router-cr6606.dts
            │   ├── mt7621_xiaomi_mi-router-cr6606-3port.dts   ← 新增
            │   └── mt7621_xiaomi_mi-router-cr660x.dtsi
            │
            ├── mt7621/
            │   └── base-files/
            │       └── etc/
            │           └── board.d/
            │               ├── 01_leds
            │               └── 02_network
            │
            └── image/
                └── mt7621.mk
```

这是比“解包官方 bin → 修改 SquashFS → 重新封装”稳定得多的方案。

---

# 二十三、为什么我现在不建议你直接改 `.bin`

因为你这个问题涉及的是：

```text
DTS
 ↓
DSA
 ↓
switch port
 ↓
gmac1
 ↓
network interface
```

而不是：

```text
/etc/config/network
```

如果只是把：

```text
wan
lan1
lan2
```

在 `/etc/config/network` 里面互换，**底层物理端口并没有真的改变**。

例如你把：

```text
option device 'wan'
```

改成：

```text
option device 'lan1'
```

只是在告诉防火墙/协议栈：

> “把 lan1 当 WAN 使用。”

但实际上：

```text
物理 WAN
    ↓
仍然是 lan1
```

所以这种方式无法达到你要求的：

> **“修改好的固件刷进新设备，物理 WAN/LAN 天然就是正确对应。”**

而 DTS 修改后：

```text
物理 WAN
↓
MT7621 port@0
↓
label = wan
↓
Linux wan
↓
UCI wan
```

才是真正的底层固定。

---

# 二十四、还有一个更稳的做法：先不要把它叫“CR6606”

为了避免以后误刷到标准四口 CR6606，我甚至建议最终产品名保持：

```text
Xiaomi Mi Router CR6606 3-Port
```

而：

```text
compatible =
    "xiaomi,mi-router-cr6606-3port"
```

这样：

```text
标准 CR6606
    ↓
xiaomi,mi-router-cr6606

你的三口版
    ↓
xiaomi,mi-router-cr6606-3port
```

完全隔离。

---

# 二十五、最终结论

从你提供的实测结果看，这个问题实际上已经可以明确定位为：

```text
标准 CR6606 DTS：

port@0 → lan1
port@1 → lan2
port@2 → lan3
gmac1  → wan

你的三口 PCB 实际接线：

port@0 → 物理 WAN
port@1 → 物理 LAN1
gmac1  → 物理 LAN2
```

所以正确底层映射就是：

```text
                 你的三口 PCB

MT7621 port@0  ─────────→ 物理 WAN
      label=wan

MT7621 port@1  ─────────→ 物理 LAN1
      label=lan1

MT7621 gmac1   ─────────→ 物理 LAN2
      label=lan2

MT7621 port@2  ─────────→ 不存在
      disabled
```

这套修改方案比单纯修改 `/etc/config/network` 更符合你的目标，也不会改变 NAND 分区、MAC、Wi-Fi 校准或设备 Flash 布局。OpenWrt 当前 CR6606/CR660x 的 DTS、image profile 和 board.d 网络配置结构都支持这种 board-specific 处理。([OpenWrt Git][2])

**有一个地方我建议你在实际编译前再做一次硬验证：**把你那台三口设备的 `dmesg | grep -Ei 'mt7530|mt7621|dsa|switch|gmac|ethphy'` 和 `/sys/firmware/devicetree/base/` 下的端口节点信息导出来。这样可以直接把 **`port@0/port@1/gmac1` 与你实测 WAN/LAN1/LAN2 做最终一一对应**，确认后再刷，避免仅凭链路现象误判。

[1]: https://github.com/openwrt/openwrt/blob/main/target/linux/ramips/dts/mt7621.dtsi?utm_source=chatgpt.com "openwrt/target/linux/ramips/dts/mt7621.dtsi at main · openwrt/openwrt · GitHub"
[2]: https://git.openwrt.org/openwrt/staging/dangole/tree/target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi?h=366ffa53bd0b31bc3633828686d791ad5e3d7f7f&utm_source=chatgpt.com "mt7621_xiaomi_mi-router-cr660x.dtsi « dts « ramips « linux « target - staging/dangole - Staging tree of Daniel Golle"
[3]: https://firmware-selector.openwrt.org/?id=xiaomi_mi-router-cr6606&target=ramips%2Fmt7621&version=23.05.4&utm_source=chatgpt.com "OpenWrt Firmware Selector"
[4]: https://lists.infradead.org/pipermail/lede-commits/2022-February/012893.html?utm_source=chatgpt.com "[openwrt/openwrt] ramips: add support for Xiaomi Mi Router CR660x series"
[5]: https://git.openwrt.org/openwrt/staging/hauke/tree/target/linux/ramips/mt7621/base-files/etc/board.d/02_network?h=32ea8a9a7e4b1319607ae398e9bf7d8e3c4cd756&utm_source=chatgpt.com "02_network « board.d « etc « base-files « mt7621 « ramips « linux « target - staging/hauke - Hauke Mehrtens staging tree"
[6]: https://github.com/openwrt/openwrt/blob/main/target/linux/ramips/mt7621/base-files/etc/board.d/01_leds?utm_source=chatgpt.com "openwrt/target/linux/ramips/mt7621/base-files/etc/board.d/01_leds at main · openwrt/openwrt · GitHub"
[7]: https://github.com/openwrt/openwrt/blob/main/target/linux/ramips/image/mt7621.mk "openwrt/target/linux/ramips/image/mt7621.mk at main · openwrt/openwrt · GitHub"
