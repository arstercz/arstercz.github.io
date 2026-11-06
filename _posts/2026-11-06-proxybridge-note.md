---
layout: post
title: "ProxyBridge 的进程代理分流原理"
tags: [proxy,system]
comments: true
---

> 本文由 AI 汇总生成
{: .prompt-tip } 

最近在看 [ProxyBridge](https://github.com/InterceptSuite/ProxyBridge) 这个工具。它的定位是"按进程把流量分流到 SOCKS5/HTTP 代理"的透明代理——应用自己完全无感知、不用改任何代理配置,由系统在内核层把目标进程的连接悄悄劫持过去。

本文梳理这么几件事:

1. 它的核心思路;
2. Windows / macOS / Linux 三个平台各自的**机制、系统要求、使用限制**;
3. 三平台通用的两个点:UDP 代理限制、DNS 怎么走;
4. 三平台"进程匹配"能力对比(以及它到底能不能当正则用);
5. 为什么在 CentOS 7 这种老系统上跑不起来,以及替代方案。

## 一、核心思路:内核拦截连接,转交本地 relay

三个平台的内核机制不同,但套路是一致的:

> **在系统层拦住目标进程发起的连接,把它改写 / 重定向到本机的一个用户态 relay,relay 再按规则用 SOCKS5/HTTP 代理把流量转发出去。**

应用本身看到的还是"我在直连目标",全程无感知,因此不需要程序支持代理、也不用改启动参数。区别只在于"用什么内核能力去拦":

| 平台 | 拦截机制 | 内核/系统能力 |
|---|---|---|
| Windows | WinDivert 驱动抓包 / 改包 | WinDivert.sys 内核驱动 |
| macOS | Network Extension 透明代理 | System Extension(flow 级拦截) |
| Linux | eBPF | cgroup v2 的 `connect4` / `connect6` / `sendmsg` hook |

下面逐个展开。

## 二、Windows:WinDivert 驱动

### 机制

Windows 版基于 [WinDivert](https://reqrypt.org/windivert.html)(一个内核级抓包 / 改包库),整个数据流是:

1. 应用(Chrome、Discord、游戏、服务等)产生 TCP/UDP 包;
2. `WinDivert.sys` 驱动在内核层拦下**所有出站包**;
3. `WinDivert.dll` 把拦下来的包交给用户态的 ProxyBridge;
4. 规则引擎逐包判定:`BLOCK` 丢弃、`DIRECT` 放行、`PROXY` 交给 relay;
5. relay 做原始 socket 与代理协议之间的转换,走代理转发;
6. 返回流量经 relay 时,**还原原始的源 IP / 端口**再重新注入,应用完全无感知。

GUI / CLI 用原生 C + Win32 API 写,启动快、体积小。

### 系统要求

- 64 位 Windows(官方按 Windows 10+ 主力支持,构建要求写的是 Windows 7+ / 64 位);
- **管理员权限**(加载 WinDivert 内核驱动必须);
- 安装包自带 WinDivert 驱动,无需单独装。

### 使用限制

- 跑引擎(`--profile`)必须管理员;`--update` / `--version` 不需要;
- **localhost 流量**按规则单独控制(勾选 "Also proxy localhost traffic",默认关),因为很多本地服务(NVIDIA GeForce Experience、Chrome DevTools 的 `127.0.0.1:9222` 等)必须留在本机;
- 最多 **32** 个代理配置同时生效(这是 Windows 的数字,Linux 的上限是每个 profile 256 个代理),规则可各自指定走哪个代理;
- UDP、DNS 的行为是三平台通用的,放到第五节单独讲。

## 三、macOS:Network Extension

### 机制

macOS 版基于 Apple 的 **Network Extension** 框架,以一个 **System Extension** 的形式注册为系统级透明代理,在 flow 层截获目标应用的网络流,在 Extension 内做规则匹配后交给代理。流程大致:

```
应用 ──(1) TCP/UDP flow──▶ [user mode]
      ──(2) Network Extension 截获──▶ ProxyBridge System Extension
      ──(3) 规则匹配(进程名/路径 或 Bundle ID / 目标 / 端口 / 协议)──▶ 代理 或 直连
```

匹配进程时它是**双管齐下**:从 flow 的 `sourceAppAuditToken` 拿到 pid,再用 `proc_pidpath` 解析出可执行文件完整路径(即进程名),同时也拿到签名标识(Bundle ID),两者都参与 glob 匹配(见 `AppProxyProvider.swift` 的 `matchesProcess` / `getProcessName`)。所以**进程名匹配在 macOS 上是能用的**。

### 系统要求

- **macOS 13.0(Ventura)或更高**;
- 首次启动需在 **System Settings → General → Login Items & Extensions → Network Extension** 里**授权系统扩展**;
- 分发为 `.pkg` 通用二进制(ARM/x64),也可 `brew install --cask proxybridge`;
- 自己编译需要 Xcode 14+ / Swift 5.7+ 和有效的 Apple Developer 账号(代码签名)。

### 使用限制

- **UDP 规则只能按"进程 + 协议"匹配,不能按目标 IP / 端口**:macOS 的 Network Extension 在 flow 打开时拿不到 UDP 的目标地址,所以 UDP 规则里的 host/port 条件无效(代码里 `handleUDPFlow` 调 `findMatchingRule(..., checkIpPort: false)`)。注意这**不是**"只有某类进程才有 UDP"——任何命中规则的进程,其 UDP 都能走(前提是用 SOCKS5,见第五节);没命中规则的 UDP 直接交给系统,日志记成 "unknown";
- **部分系统进程绕过扩展**:为系统稳定,关键 macOS 服务不被拦截;
- TCP 支持完整(可按进程 / 目标 IP / 域名 / 端口 / 协议匹配)。

> 📌 顺带纠正一个流传的说法:仓库里较早的 README 写过 "macOS 只能按 Bundle ID、拿不到进程名"。看现在的源码,它已经通过 audit token + `proc_pidpath` 支持进程名/路径匹配了,那段 Limitations 已过时。

## 四、Linux:eBPF(cgroup connect hook)

Linux 版是完整的原生实现:CLI + GTK3 GUI + systemd service。

> ⚠️ 注意:GitHub **主页** README 把 Linux 写成 "Netfilter NFQUEUE + iptables",这段**已经过时**。真正的实现是 **eBPF 方案**——看代码 `Linux/src/bpf/proxybridge.bpf.c` 和 `Linux/README.md` 就清楚了。

### 机制

1. eBPF 程序挂在 cgroup v2 的 `SEC("cgroup/connect4")` / `connect6` hook 上,进程一发起 `connect()` 就触发,此时内核侧能直接拿到 pid / cgroup;
2. 规则引擎判定应 `ACT_PROXY` 时,直接改写 `ctx->user_ip4 = 127.0.0.1` 和端口,把连接导向本机 relay,并把**原始目标地址**存进一张 BPF map;
3. 用户态 relay(`pb_relay.c`)从 map 取回原始目标,再走 SOCKS5 / HTTP 代理转发;
4. UDP 走 `sendmsg` hook;DNS 还会额外维护一张 **IP ↔ 域名映射表**,以支持按域名写规则(内核只看得到 IP,得先从 DNS 应答里把域名和解析出的 IP 关联起来)。

这套"在 cgroup 层改写 sockaddr → 本地 relay"的做法,本质和 macOS 用 NetworkExtension 截获 flow 是同一种思路,只是换了内核接口。

### 系统要求

- **root**(加载 eBPF 需要);
- 内核 **≥ 5.11**;
- 内核编译时开启 **BTF**(`CONFIG_DEBUG_INFO_BTF`,CO-RE 需要);
- **cgroup v2**。

> 说明一下这个 5.11:它是 **ProxyBridge 自己设的下限,不是 eBPF 的下限**。eBPF 很早就有了,连 cgroup 的 `connect` hook 也是内核 4.17 就引入的——所以"4.x 支持 eBPF"没错。但 ProxyBridge 依赖 BTF/CO-RE 和它用到的 cgroup sock_addr 特性,代码里把门槛写死在 5.11,内核不达标时加载直接报错 `needs a kernel >= 5.11 with BTF`([pb_bpf.c:178](https://github.com/InterceptSuite/ProxyBridge/blob/master/Linux/src/pb_bpf.c#L178))。也就是说,4.x 哪怕有 eBPF,这个工具也明确不支持。

架构上和 Windows 一样拆成两部分:`proxybridge.service`(root 跑引擎,监听 `/run/proxybridge/ctl.sock`)和 `ProxyBridgeGUI`(普通用户,通过 socket 向 service 发请求)。允许使用 service 的是 root 和 `proxybridge` 组成员。

一键安装:

```bash
curl -Lo deploy.sh https://raw.githubusercontent.com/InterceptSuite/ProxyBridge/refs/heads/master/Linux/deploy.sh && sudo bash deploy.sh
```

### 使用限制

- 进程名**区分大小写**;解释型程序(python/node/java)按解释器二进制识别(如 `python3.12`);
- 规则按顺序匹配、首次命中生效;本地代理工具(Burp / mitmproxy / Tor / `ssh -D`)会被自动豁免以防回环;
- 每个 profile 最多 256 个代理、4096 条规则;
- UDP、DNS 的行为同样是三平台通用的,见下一节。

## 五、三平台通用的两个点:UDP 代理 与 DNS

这两件事三个平台行为一致,单独拎出来讲,免得在每个平台重复。

### UDP:只有 SOCKS5 能代理,HTTP 一律回退直连

这不是某个平台的限制,而是**代理协议本身决定的**:HTTP 代理(`CONNECT`)只能隧道 TCP,无法承载 UDP。所以:

- UDP 要走代理,**必须配 SOCKS5**,而且该 SOCKS5 要支持 `UDP ASSOCIATE`;
- 只配了 HTTP 代理时,UDP 自动**回退成直连**;
- 注意很多 SOCKS5(包括 SSH 的 `-D` 隧道)并不支持 UDP ASSOCIATE;现在很多 UDP 应用用 HTTP/3、DTLS,也要代理链路能处理。

三平台的源码都印证了这点(macOS `handleUDPFlow` 注释 "http proxies can't carry udp";Linux `pb_relay.c` 开头也写明 UDP 走 SOCKS5 UDP ASSOCIATE)。

> 📌 两点澄清,免得误解:
>
> 1. 这里说的"HTTP 代理不支持 UDP"指的是**传统的 HTTP/HTTPS 正向代理**(靠 `CONNECT` 建 TCP 隧道,协议里没有转发 UDP 数据报的机制)。协议层面其实有 [RFC 9298 "Proxying UDP in HTTP"](https://datatracker.ietf.org/doc/html/rfc9298)(`CONNECT-UDP` / MASQUE)这类较新的扩展能转发 UDP,但那是 HTTP/3 时代的新东西;ProxyBridge 的 HTTP 代理走的是经典 `CONNECT`,不涉及它。
> 2. 现在很多"UDP 流量"其实是 QUIC / HTTP/3、DTLS。浏览器走 HTTP 代理时,QUIC 通常会被降级回 TCP 上的 HTTP/2,所以网页照样能开——只是没走 UDP;但纯 UDP 的应用(游戏、DNS、WebRTC 等)在只配 HTTP 代理时就是直连。

### DNS:应用自己解析,但默认查询和目标解析都走远端

一个常见疑问:命中规则的进程,它的 DNS 是"代理远程解析返回",还是"本地先解析再走代理连"?三平台是同一套模型:

**应用始终自己发起 DNS 查询**,ProxyBridge 不会替它预解析再放行。但在默认配置下,DNS 查询本身和最终连接的解析**都走远端**,两道都不往本地 ISP 泄漏:

1. **DNS 查询本身按规则走。** `DnsViaProxy`(profile 字段,默认 `true`)会把命中进程的 DNS(53 端口)查询**隧道进代理**,所以解析实际发生在代理那一侧的网络里。与此同时,ProxyBridge 旁路观测明文 DNS 应答,建一张 **IP → 域名映射表**——因为内核/扩展只看得到 IP,域名规则(`*.github.com` 这种)全靠它把 IP 反查回域名。**DoH / DoT 会绕过这个观测**,域名规则就会失效。
2. **发起连接时默认把域名交给代理再解析一次。** 应用拿到 IP 去连接,命中代理规则后,`SendDomainToProxy`(每个代理一项,默认 `true`)会从映射表查出该 IP 对应的域名,把**域名**发给代理(SOCKS5 域名地址 ATYP=3,或 HTTP `CONNECT host:port`),由**代理远程再解析**真正要连的目标;关掉它(CLI `?dns=local`)则发送本地解析出的那个 IP。UDP 数据报始终带 IP、不带域名。

一句话总结默认行为:**本地解析只是用来"认出域名、触发连接",查询本身和最终连接的解析都由代理在远端完成**,所以既能命中域名规则、又基本不泄漏 DNS。

## 六、三平台"进程匹配"对比:都不是正则

很多人关心能不能"按进程名正则分流",这里专门对比一下:

| 平台 | 匹配对象 | 匹配方式 |
|---|---|---|
| Windows | 可执行文件名 / 路径 | glob 通配(`*` `?`、`;` 分隔) |
| macOS | 进程名 / 路径 **以及** Bundle ID | glob 通配(两者都试,命中即可) |
| Linux | 可执行文件名 + 完整路径(区分大小写) | glob 通配(`*` `?`、`;`/`,` 分隔) |

重点结论:

- **三平台都支持按进程名/路径匹配**(macOS 额外还能用 Bundle ID),所以 `*chrome*`、`fire*` 这类写法三家都能用;
- 但**三平台都不支持真正的正则**,用的都是 glob 通配(看 Linux 源码 `pb_rules.c` 里的 `pb_glob_match`,只实现了 `*` 和 `?`),没有 `[...]` 字符类、`(a|b)` 分组、`.*`/`+`/`{n}` 量词、`^`/`$` 锚点。

glob 合法写法示例(三平台通用):

```
curl
fire*
*chrome*
/usr/bin/*
firefox;chrome
```

### 如果你一定要正则

在 **Linux** 版上相对好办:进程名匹配发生在**用户态规则引擎**——eBPF 只负责提供触发点和 pid/cgroup,真正把"进程 → 规则"对应起来是在用户态写进 map 的。所以加正则**只需改用户态**(把 `pb_glob_match` / 规则解析换成 `regexec` 或 PCRE),**不用动 eBPF**,改动量不大、风险可控。

## 七、CentOS 7 跑得起来吗?——基本不行

既然 Linux 版是 eBPF 方案,老系统就卡在硬门槛上了。拿 CentOS 7 对一下:

| 要求 | CentOS 7 实际情况 |
|---|---|
| 内核 ≥ 5.11 | 默认 **3.10**(RHEL7 内核),差十几个大版本 |
| 内核带 BTF | 3.10 没有,BTF 是 5.x 才普及 |
| cgroup v2 | 默认 **cgroup v1**,`cgroup/connect4` 这类 hook 挂不上 |

它依赖的 `cgroup/connect4`、BTF/CO-RE 这些全是 5.x 内核的能力,放到 3.10 上 eBPF 程序加载直接失败。补充两点:

- CentOS 7 已在 **2024 年 6 月 EOL**;
- 官方安装脚本的发行版列表里也没有 CentOS 7(列的是较新的 RHEL/Rocky/Alma 等);
- 就算用 ELRepo 的 `kernel-ml` 强升到 5.11+ 内核、再开 cgroup v2,也很折腾且脱离作者测试环境,生产不建议。

## 八、CentOS 7 上实现"按进程分流走代理"的替代方案

不依赖新内核 eBPF,也能做到类似效果:

### 方案 1:`redsocks` + iptables

用 iptables 把流量 `REDIRECT` 到本地 redsocks,由它转 SOCKS5/HTTP。按"进程"分流可配合 iptables 的 `-m owner --uid-owner`(按运行用户)或 cgroup 匹配。

- 优点:成熟、稳定、系统侵入小;
- 局限:是按 **uid / cgroup** 分流,不是按进程名正则。

### 方案 2:`proxychains-ng`

LD_PRELOAD 劫持,只对你用它启动的那个进程生效。

- 优点:最简单;
- 局限:只对动态链接、且你能控制启动命令的程序有效(静态链接、setuid 的不行)。

### 方案 3:自写 daemon + cgroup(net_cls)+ iptables —— 最接近 ProxyBridge 又能支持真正则

1. 一个小 daemon 轮询 `/proc/*/exe`,对进程做**正则**匹配;
2. 命中的进程塞进一个 cgroup v1 `net_cls`,打上 classid;
3. iptables 用 `-m cgroup --cgroup <classid>` 把该 cgroup 的流量 `REDIRECT` 给 redsocks;
4. redsocks 转到你的代理。

这是 CentOS 7 上最贴近 ProxyBridge 效果、且能支持**真正的正则进程匹配**的做法。

## 小结

- ProxyBridge 的分流本质:**内核拦连接 → 本地 relay → SOCKS5/HTTP**,应用无感知;
- 三平台拦截机制:**Windows = WinDivert 驱动,macOS = Network Extension,Linux = eBPF(cgroup connect hook)**,主页写的 NFQUEUE 已过时;
- 系统要求差异大:Windows 要管理员 + 驱动,macOS 要 Ventura+ 并授权系统扩展,Linux 要 root + 内核 ≥ 5.11 + BTF + cgroup v2;
- UDP 只有 SOCKS5(需 UDP ASSOCIATE)能代理,HTTP 代理一律回退直连,这是协议本身的限制,三平台通用;
- DNS 默认"本地认域名、远端真解析":`DnsViaProxy` 把查询隧道进代理,`SendDomainToProxy` 把域名交给代理再解析,基本不泄漏;
- 进程匹配三平台都**支持按进程名/路径**(macOS 额外支持 Bundle ID),但都**不是正则**,只是 glob 通配;Linux 版想加正则只需改用户态;
- **CentOS 7(3.10 内核)跑不起来**(5.11 是工具硬门槛,非 eBPF 门槛),想在老系统做按进程正则分流,用"自写 daemon + net_cls cgroup + redsocks"这条路。
