OpenWrt 跨网段调用台式主机代理教程

**应用场景**：OpenWrt 作为主路由/桥接路由，但无法直接连通外网。内网下级华硕路由器连接的台式机（PC）运行有 v2rayN 科学上网客户端。需让 OpenWrt 通过 SSH 终端调用 PC 的代理网络，实现 `opkg update` 等命令正常拉取软件包。

### 1. 核心 IP 与端口盘点

| 设备名称 | 网络角色 | IP 地址 | 端口信息 | 说明 |
| --- | --- | --- | --- | --- |
| **OpenWrt** | 主路由/入户路由 | `192.168.50.1` | `22` (SSH) | 本次需要挂载代理的目标设备 |
| **华硕路由器** | 二级路由 (WAN侧) | `192.168.50.188` | `10808` | 由 OpenWrt 动态或静态分配的 IP |
| **华硕路由器** | 二级路由 (LAN侧) | `192.168.51.1` | - | 华硕路由器的局域网网关 |
| **台式主机 (PC)** | 终端设备 | `192.168.51.66` | `10808` | 运行 v2rayN 并开启局域网连接 |

### 2. 网络拓扑结构图

```text
[ 互联网/上级网络 ]
       │ (无线桥接 / WDS)
       ▼
┌──────────────────────────────────────┐
│  主路由 OpenWrt (网段: 50.x)       │
│  LAN IP: 192.168.50.1                │
└──────────────────┬───────────────────┘
                   │ LAN1 网线延伸
                   ▼
┌──────────────────────────────────────┐
│  华硕路由器 (网段隔离)                 │
│  WAN IP: 192.168.50.188 (面向 OpenWrt)│
│  LAN IP: 192.168.51.1   (面向 PC)     │
└──────────────────┬───────────────────┘
                   │ LAN1 网线延伸
                   ▼
┌──────────────────────────────────────┐
│  台式电脑 PC (网段: 51.x)              │
│  IP: 192.168.51.66                   │
│  状态: v2rayN 运行中 (端口: 10808)     │
└──────────────────────────────────────┘

```

### 3. 配置步骤

#### Step 1: PC 端放行防火墙与 v2rayN 设置

1. 打开 v2rayN 客户端，进入**设置 -> 参数设置**，勾选“允许来自局域网的连接”并保存重启。
2. 右键点击 Windows 桌面“开始”菜单，选择 **PowerShell (管理员)** 或终端 (管理员)。
3. 输入以下命令，在 Windows 防火墙上凿开一个允许外部连接的“小孔”：
```powershell
New-NetFirewallRule -DisplayName "v2rayN-Port" -Direction Inbound -LocalPort 10808 -Protocol TCP -Action Allow

```



#### Step 2: 华硕路由器设置端口转发 (核心穿透)

由于 OpenWrt 无法直接访问华硕路由器 LAN 侧的 PC，必须搭建端口转发桥梁。

1. 登录华硕路由器后台 (`192.168.51.1`)。
2. 进入左侧菜单：**外部网络 (WAN) -> 端口转发 (Port Forwarding)**。
3. 开启端口转发，添加一条新规则：
* 服务名称：自定义 (如 OpenWrt SSH)
* 外部端口：`10808`
* 内部 IP 地址：`192.168.51.66` (台式机 IP)
* 内部端口：`10808`
* 通信协议：`TCP`


4. 点击应用/保存。此时，所有发往华硕 WAN IP (`192.168.50.188`) 的 10808 端口流量，都会被送往 PC。

#### Step 3: OpenWrt 写入快捷切换脚本

1. 使用 SSH 登录 OpenWrt (`192.168.50.1`)。
2. 将以下命令整体复制、粘贴并回车执行，这会在环境变量中添加两个快捷指令：
```bash
cat << 'EOF' >> /etc/profile

v2ray_on() {
    export HOST_IP="192.168.50.188"
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


3. 临时降级 OpenWrt 官方软件源协议，规避内置 `wget` 对 HTTPS 代理支持极差导致的 `Operation not permitted` 报错：
```bash
sed -i 's/https:\/\//http:\/\//g' /etc/opkg/distfeeds.conf

```



#### Step 4: 生效与使用验证

1. 使配置立即生效：
```bash
source /etc/profile

```


2. 开启代理：
```bash
v2ray_on

```


3. 执行系统更新测试：
```bash
opkg update

```


*(此时可以看到 `Downloading...` 进度条迅速跑完，无 Error 4 报错。使用完毕后可输入 `v2ray_off` 关闭环境变量)*。

> **原理说明：为什么没有回环错误？**
> 我们使用的是**应用层环境变量代理**，只是告诉 `opkg` 这个软件去走代理，并没有修改 OpenWrt 的底层 `iptables` 路由表。PC 代理后的流量依然会按正常路径走华硕 -> OpenWrt -> 互联网，是清晰的单向流动，不会产生逻辑死循环。




#### Step 5: 删除与重写配置


要删除之前写入的配置，我们需要编辑 `/etc/profile` 文件，把上次添加的 `v2ray_on()` 和 `v2ray_off()` 函数内容清理干净。

推荐使用 `sed` 命令自动删掉这部分内容，然后再重新写入新的配置。

1. **清理旧配置:** OpenWrt 端.
在 OpenWrt (192.168.50.1) 的 SSH 终端中执行以下命令，它会删掉 `/etc/profile` 文件中所有包含 `v2ray_on`、`v2ray_off` 以及它们内部代码的行：

```bash
sed -i '/v2ray_on()/,/EOF/d; /v2ray_off()/,/EOF/d; /export HOST_IP=/d; /export PORT=/d; /export http_proxy=/d; /export https_proxy=/d; /export ALL_PROXY=/d; /Proxy enabled/d; /Proxy disabled/d; /unset http_proxy/d' /etc/profile

```

*说明：这个命令非常安全，只会精准删除我们上次写入的代理环境变量和函数，不会影响系统的其他默认配置。*


2. **然后重新写入新配置即可**
