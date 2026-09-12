以下是 OpenWrt 新设备在 SSH 环境下执行完 `opkg update` 后的完整调优与多环境代理插件安装流水线。请确保设备有足够的剩余存储空间（建议至少剩余 100MB 以容纳内核），并根据你的实际硬件架构（例如通用 `x86_64`、OneCloud 对应的 `arm_cortex-a7_neon-vfpv4` 或 JCG Q20 对应的 `mipsel_24kc`）调整部分下载链接。

1. **系统调优与基础依赖包补全:** 约 2 分钟.
调整路由器时区为北京时间（CST-8），并补全后续下载、解压和网络处理所需的底层依赖。

```bash
# 安装基础依赖
opkg install curl wget-ssl ca-certificates unzip tar jq htop vim

# 调整系统时区与 NTP
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].timezone='CST-8'
uci commit system
/etc/init.d/system reload

```

验证：在终端输入 `date` 命令，确认终端返回的时间为当前的准确北京时间。


2. **本地化与 UI 主题安装:** Argon 与 Neobird.
安装 LuCI 中文语言包，并部署官方软件源中的 Argon 主题以及从 GitHub 侧载 Neobird 主题。

```bash
# 安装系统中文语言包及 Argon 主题
opkg install luci-i18n-base-zh-cn luci-theme-argon luci-i18n-argon-config-zh-cn

# 下载并安装 Neobird 主题
wget -O /tmp/neobird.ipk https://github.com/thinkst20/luci-theme-neobird/releases/latest/download/luci-theme-neobird_all.ipk
opkg install /tmp/neobird.ipk

```

验证：刷新浏览器的 OpenWrt 后台登录页，界面应显示为中文，且在“系统 -> 系统 -> 语言和界面”菜单中可以随时切换 Argon 和 Neobird 主题。


3. **安装 Cloudflare DDNS 与 rtp2httpd:** 解析与组播转换.
```bash
# 安装 DDNS 核心组件及 Cloudflare 脚本
opkg install ddns-scripts-cloudflare luci-app-ddns luci-i18n-ddns-zh-cn

# 安装 rtp2httpd 组件
opkg install rtp2httpd

```

验证：在 LuCI 的“服务”菜单下应能看到“动态 DNS”选项；在 SSH 执行 `rtp2httpd -h` 会输出该服务的帮助信息。


4. **替换 dnsmasq 并安装 OpenClash:** 网络核心替换.
```bash
cd /tmp
# 1. 缓存 dnsmasq-full 及其依赖
opkg download dnsmasq-full

# 2. 安全卸载默认 dnsmasq 并安装完整版
opkg remove dnsmasq
opkg install dnsmasq-full*.ipk

# 3. 安装 OpenClash 依赖
opkg install coreutils coreutils-nohup bash curl ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy

# 4. 下载并安装 OpenClash 核心包
wget -O /tmp/openclash.ipk https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash_all.ipk
opkg install /tmp/openclash.ipk

```

验证：执行 `opkg list-installed | grep openclash` 若返回版本号，且 LuCI “服务”栏出现 OpenClash 即表示安装成功。


5. **批量安装 PassWall 2 及其核心组件:** 需核对架构.
PassWall 2 需要配合 Xray、Sing-box 等众多依赖运行。请根据你实际的 CPU 架构（将下方链接中的 `x86_64` 替换为你的实际架构）下载预编译包。

```bash
mkdir -p /tmp/passwall2 && cd /tmp/passwall2

# 注意：请务必将下方链接中的 x86_64 替换为对应架构（如 mipsel_24kc 或 aarch64_generic 等）
wget https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/latest/download/passwall2_packages_x86_64.zip

# 解压并批量强制安装所有组件
unzip passwall2_packages_*.zip
opkg install *.ipk --force-depends

```

验证：执行 `opkg list-installed | grep passwall` 确认主程序已就绪，并在 LuCI 中检查 PassWall 的“组件信息”页，确认 Xray/Sing-box 等核心均处于“已安装”状态。