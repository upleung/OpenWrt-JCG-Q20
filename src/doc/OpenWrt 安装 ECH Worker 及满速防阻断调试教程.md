

## OpenWrt 安装 Tuple ECH Worker 及满速防阻断调试教程

**应用场景**：在 OpenWrt 24.10.4 新版系统中安装第三方 `luci-app-ech-workers`，解决空壳插件无法运行、新系统界面不显示、以及 Cloudflare Worker 代理导致“同为 CF CDN 节点网站（如官网、测速站）打不开”的死循环问题，并追求极致网速。

### 1. 手动补齐核心文件与安装

大多数 [GitHub](https://github.com/SunshineList/luci-app-ech-workers) 下载的 `.ipk` 插件只是一个网页壳子，安装时若路由器无法连外网，则无法自动下载核心二进制程序，导致日志提示 `二进制文件不存在: /usr/bin/ech-workers`。

1. **上传并安装界面壳子**：
通过 SSH 登录 OpenWrt，安装你已经下载好的插件包：
```bash
opkg install /root/luci-app-ech-workers_1.0.0-1_all.ipk

```


2. **[下载并放入核心文件](https://github.com/SunshineList/luci-app-ech-workers)**：
根据 CPU 架构（如 JCG Q20 是 MT7621，属 `mipsle`），去作者 GitHub Release 页面下载 `ech-workers-linux-mipsle`。
将文件重命名为 `ech-workers`，上传到 OpenWrt 的 `/usr/bin/` 目录下。
3. **赋予执行权限并启动**：
```bash
chmod +x /usr/bin/ech-workers
/etc/init.d/ech-workers restart

```



### 2. 解决 LuCI 菜单不显示的问题（直接重启即可）

OpenWrt 24.x 全面抛弃了旧版 Lua 架构。旧插件装完后如果不显示，需要安装官方兼容包并深度重载系统缓存：

```bash
# 1. 在终端开启代理（参照教程一的 v2ray_on）后安装兼容层
opkg update
opkg install luci-compat

# 2. 清空所有的网页菜单内存缓存
rm -rf /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache/

# 3. 强制重启网页 RPC 守护进程与 Web 服务器 (核心)
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

```

刷新浏览器页面后，插件将出现在 **服务 (Services) -> Tuple ECH Worker** 中。

### 3. 修改 CF Worker 代码 (解决部分网站打不开)

**问题病因**：当你代理访问同属 Cloudflare 保护的网站（如 CF 官网）时，流量从你的 Worker 发向目标 CF 节点，触发了 CF 防火墙禁止“内循环 TCP 转发”的底层安全机制。
**终极解法**：修改 Cloudflare 后台部署的 `worker.js` 代码，使用可用的第三方 ProxyIP 进行绕路中转。

登录 Cloudflare 面板，编辑对应的 Worker 代码。找到顶部的 `CF_FALLBACK_IPS` 变量（作者默认写的可能已失效），将其**替换**为高可用节点：

```javascript
const WS_READY_STATE_OPEN = 1;
const WS_READY_STATE_CLOSING = 2;
// 替换失效的 IPv6，使用高连通率的 Proxy IP 进行跨墙绕路
const CF_FALLBACK_IPS = ['ProxyIP.CMLiussss.net'];

```

保存并部署后，CF 官网、伪装检测等网站将“药到病除”，瞬间秒开。

### 4. 插件端提速至极致 (追平 GCP hy2)

进入 OpenWrt -> 服务 -> Tuple ECH Worker，按以下关键参数进行配置，确保晚高峰不卡顿：

* **监听地址**：`0.0.0.0:30000` (或保持默认 30001)
* **服务器地址**：填写你的真实 Worker 域名 (例如 `自定义.workers.dev:443`)。
* **身份令牌**：填写在 worker.js 中约定的密码 (例如 `token`)。
* **优选 IP/域名 (决定速度的关键)**：**强烈建议替换默认域名**，可填写你以往在 Armbian Docker 中实测过极快的优质反代域名，例如 `visa.com`、`icook.hk` 或 `time.is`。
* **透明代理 (安全起见)**：
* **不要急着打勾！** 建议先留空保存，然后在电脑客户端新建一个 Socks5 节点（指向 OpenWrt IP `192.168.50.1` 端口 `30000`）进行连通性测试。
* 一旦确认 YouTube 4K 能够丝滑秒开，再回后台勾选“**启用透明代理**”，让局域网所有设备实现无感全局翻墙。



---

**🔗 实用配套资源工具箱：**

* **CloudFlare 优选域名查询**: [https://cf.090227.xyz/](https://cf.090227.xyz/?utm_source=gemini)
* **Proxy IP 查询**: [https://check.proxyip.cmliussss.net/](https://check.proxyip.cmliussss.net/?utm_source=gemini)