**OpenWrt 通过 USB 网卡调用宿主机代理终端连网教程**

本教程适用于在不修改底层路由架构的情况下，使 OpenWrt 路由器通过 USB 网卡直连电脑，并在 SSH 终端中按需临时调用电脑端（宿主机）的 v2rayN 代理网络。该方案常用于给刚刷好机或离线的 OpenWrt 路由器安装软件、拉取 `opkg` 软件源、或下载依赖包。

---

**一、 适用场景与网络拓扑**

* **场景**：OpenWrt 路由器未连外网（或无法直连外网拉取 GitHub/外源），仅通过 USB 网卡与一台能科学上网的 Windows 电脑（宿主机）物理直连。
* **拓扑**：
* **宿主机网卡**：连接真实外网（例如 `192.168.50.x`）。
* **物理连接**：网线一头插入 **OpenWrt 的 LAN 口**（强烈推荐，避免 WAN 口防火墙阻断），一头插入电脑的 **USB 网卡**。
* **USB 网卡 IP**：由 OpenWrt 的 DHCP 自动分配，或手动设置在 `192.168.5.x` 网段（假设分配到的 IP 为 `192.168.5.253`）。
* **OpenWrt IP**：假设为 `192.168.5.1`。



---

**二、 宿主机 v2rayN 设置**

要让 OpenWrt 能够连上电脑的代理，必须开启 v2rayN 的局域网共享功能。

1. **开启局域网共享**：
* 打开 v2rayN 客户端主界面。
* 点击顶部菜单栏的 **设置** -> **参数设置**。
* 在 **基础设置** 标签页中，勾选 **允许来自局域网的连接**（Allow LAN）。


2. **确认监听端口**：
* 在基础设置中，找到 **本地监听端口** 或 **混合端口 (mixed-port)**。
* 确认并记下该端口号。推荐使用 `10000 ~ 30000` 之间的端口（例如本教程使用的 `10808`），避免与系统服务冲突。



---

**三、 确定电脑的局域网 IP（USB 网卡 IP）**

OpenWrt 需要知道电脑的 IP 才能发送请求。

1. 在 Windows 电脑上打开终端（PowerShell 或 CMD）。
2. 输入 `ipconfig` 并回车。
3. 找到连接到路由器的那个以太网适配器（通常是 USB 网卡），记下它的 **IPv4 地址**。
* *注：本教程假设该 IP 为 `192.168.5.253`。如果您的 IP 不同，请在后续步骤中替换。*



---

**四、 在 OpenWrt 中配置代理环境快捷开关**

通过 SSH 登录到 OpenWrt 后，可以将代理的开启和关闭命令封装成两个快捷指令写入系统配置中，方便日后一键调用。

**1. 写入配置文件**

在终端中，整段复制以下代码并执行（**请确保将下方代码中的 `192.168.5.253` 替换为您在第三步查到的真实 IP，`10808` 替换为 v2rayN 的混合端口**）。

*注意：OpenWrt 的 ash shell 对语法非常敏感，函数名中绝对不能使用连字符（`-`），必须使用下划线（`_`）。*

```sh
cat << 'EOF' >> /etc/profile

v2ray_on() {
export HOST_IP="192.168.5.253"
export PORT="10808"
export http_proxy="http://$HOST_IP:$PORT"
export https_proxy="http://$HOST_IP:$PORT"
export ALL_PROXY="socks5://$HOST_IP:$PORT"
echo "Proxy enabled -> $HOST_IP:$PORT"
}

v2ray_off() {
unset http_proxy https_proxy ALL_PROXY HOST_IP PORT
echo "Proxy disabled."
}
EOF

```

**2. 刷新配置生效**

执行以下命令，让系统重新读取刚才写入的环境变量配置：

```sh
source /etc/profile

```

如果没有报错，即代表写入成功。

---

**五、 使用与验证**

配置完成后，您就可以在 SSH 终端中随意开关代理了。

**1. 开启代理并更新软件源**

* 开启代理：
```sh
v2ray_on

```


（终端应回显：`Proxy enabled -> 192.168.5.253:10808`）
* 执行 OpenWrt 的包管理器更新命令：
```sh
opkg update

```


如果代理配置正确，您应该能看到类似 `Downloading [https://downloads.openwrt.org/](https://downloads.openwrt.org/)...` 且以 `Signature check passed` 结尾的成功拉取信息。 `opkg update` 之后即可通过 `opkg install` 安装各类插件。


**2. 关闭代理**

当不需要使用代理时，或者需要访问 OpenWrt 本地的网络资源时，执行：

```sh
v2ray_off

```

（终端应回显：`Proxy disabled.`）

---

**常见排障：**

* **执行 `source /etc/profile` 报错 `syntax error: bad function name**`：说明之前写入的文件包含了带连字符的函数名（如 `v2ray-on`）。执行 `sed -i '/v2ray/,$d' /etc/profile` 和 `sed -i '/HOST_IP/,$d' /etc/profile` 清理残留，然后重新执行第四步的纯净代码。
* **连通性测试报错 `curl: not found**`：OpenWrt 默认极简，通常不内置 `curl`。开启代理后，若要测试连通性，可使用系统自带的 `wget` 命令：`wget -qO- [https://www.google.com](https://www.google.com) | head -n 5`。