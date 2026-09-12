# OpenWrt 新设备初始调优与全能代理部署指南
**适用设备**: JCG Q20 (及同类联发科 MT7621 路由)
**系统架构**: `mipsel_24kc`
**最后更新**: 2026年9月

本教程针对新刷入 OpenWrt 官方固件（如 23.05.x）的 JCG Q20 路由器，完整覆盖从基础系统调优、中文界面与主题安装，到动态域名解析、多播转换以及两大主流科学上网插件（OpenClash 与 PassWall 2）的详细部署流程。

## 📋 部署前置要求
1. 路由器已成功联网，且有足够的存储空间（若空间不足，建议配置 USB 扩容 Extroot 后再安装）。
2. 已通过 SSH（推荐使用 VS Code 终端或 MobaXterm）使用 `root` 账户登录路由器。

---

## 一、 系统基础调优与依赖补全

登录 SSH 后，首先更新软件源列表，并安装后续必要的底层网络工具和证书，同时将系统时区修正为北京时间。

```bash
# 1. 更新软件源
opkg update

# 2. 安装基础依赖组件
opkg install curl wget-ssl ca-certificates unzip tar jq htop vim

# 3. 调整系统时区为 CST-8（北京时间）
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].timezone='CST-8'
uci commit system
/etc/init.d/system reload

```

*验证：输入 `date` 命令，确认返回当前正确的北京时间。*

---

## 二、 汉化系统界面与双主题安装 (Argon / Neobird)

原版 OpenWrt 默认全英文，我们需要安装中文语言包，并部署目前最受欢迎的两款现代 UI 主题。

```bash
# 1. 安装核心中文包、Argon 主题及其配置模块
opkg install luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-theme-argon luci-i18n-argon-config-zh-cn

# 2. 下载并安装 Neobird 主题 (第三方库引入)
wget -O /tmp/neobird.ipk [https://github.com/thinkst20/luci-theme-neobird/releases/latest/download/luci-theme-neobird_all.ipk](https://github.com/thinkst20/luci-theme-neobird/releases/latest/download/luci-theme-neobird_all.ipk)
opkg install /tmp/neobird.ipk

```

*提示：安装完成后，刷新浏览器进入 OpenWrt 后台界面，即可在 `System -> System -> Language and Style` (或汉化后的 `系统 -> 系统 -> 语言和界面`) 中自由切换 Argon 或 Neobird。*

---

## 三、 安装 Cloudflare DDNS 与 IPTV 组播转换

为满足外部网络访问与内网流媒体需求，部署 CF 动态域名解析及组播转单播工具。

```bash
# 1. 安装动态 DNS 核心、中文包及 Cloudflare 专用脚本
opkg install ddns-scripts-cloudflare luci-app-ddns luci-i18n-ddns-zh-cn

# 2. 安装 rtp2httpd (常用于 IPTV 组播转 HTTP 单播)
opkg install rtp2httpd

```

---

## 四、 核心网络环境准备：平滑替换 dnsmasq-full

> **🚨 严重警告：** OpenClash 等代理插件强制要求使用完整版的 `dnsmasq-full`。直接卸载原版 `dnsmasq` 会导致路由器瞬间丢失域名解析（DNS）能力，从而使得后续 `wget` 无法解析 GitHub 域名下载任何文件。**必须严格按照以下顺序“先缓存、再卸载、后安装”。**

```bash
cd /tmp

# 1. 先将 dnsmasq-full 及其所有依赖下载到本地缓存
opkg download dnsmasq-full

# 2. 卸载自带的基础版 dnsmasq（此时 DNS 解析会断开）
opkg remove dnsmasq

# 3. 立即从本地缓存安装完整版 dnsmasq-full（恢复 DNS 解析）
opkg install dnsmasq-full*.ipk

```

---

## 五、 安装 OpenClash 代理核心

OpenClash 功能强大但依赖众多环境组件。

```bash
# 1. 安装 OpenClash 必需的核心依赖包
opkg install coreutils coreutils-nohup bash curl ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy

# 2. 从 GitHub 下载并安装最新的 OpenClash 客户端
wget -O /tmp/openclash.ipk [https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash_all.ipk](https://github.com/vernesong/OpenClash/releases/latest/download/luci-app-openclash_all.ipk)
opkg install /tmp/openclash.ipk

```

---

## 六、 针对 `mipsel_24kc` 架构安装 PassWall 2

与 OpenClash 的 `all.ipk` 架构无关不同，PassWall 2 的诸多核心代理组件（如 Xray, Sing-box）强依赖于 CPU 架构。以下为 JCG Q20 (`mipsel_24kc`) 的专属安装命令：

```bash
# 1. 创建临时目录并进入
mkdir -p /tmp/passwall2 && cd /tmp/passwall2

# 2. 下载针对 mipsel_24kc 架构打包的 PassWall 2 组件包合集
wget [https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/latest/download/passwall2_packages_mipsel_24kc.zip](https://github.com/Openwrt-Passwall/openwrt-passwall2/releases/latest/download/passwall2_packages_mipsel_24kc.zip)

# 3. 解压缩包
unzip passwall2_packages_mipsel_24kc.zip

# 4. 强制忽略版本校验安装所有插件包和依赖
opkg install *.ipk --force-depends

```

---

## 七、 收尾与清理

所有核心组件安装完成后，清理临时占用空间并重启路由器以应用所有更改。

```bash
# 清理 /tmp 目录下的大体积缓存文件，释放内存
rm -rf /tmp/*.ipk /tmp/passwall2 /tmp/dnsmasq-full*.ipk

# 重启路由器
reboot

```

重启后，即可进入 OpenWrt（如 `192.168.5.1`）后台，在“服务”菜单中开始导入节点、配置 OpenClash 或 PassWall 2 等相关服务。