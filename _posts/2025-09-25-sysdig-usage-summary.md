---
layout: post
title: "sysdig 使用汇总"
tags: [sysdig,system]
comments: true
---

## 说明
在文章 [Linux 系统动态追踪技术介绍]({{ site.baseurl }}/introduction_to_linux_dynamic_tracing/) 和 [如何审计 Linux 系统的操作行为]({{ site.baseurl }}/how-to-audit-linux-system-operation/) 介绍了 sysdig 这款系统跟踪工具相关的原理和案例, 但其众多的选项使用起来不容易记住, 本文则汇总了安装部署以及一些常用的命令方便随时参考使用.

> 可使用命令 `sysdig -l` 列出不同 rule 规则下各字段说明, 更多见: [rule-fields-library](https://docs.sysdig.com/en/sysdig-secure/rule-fields-library/)  

## 依赖说明

`sysdig` 属于底层的诊断工具, 需要捕捉内核态的系统调用行为, 捕捉的时候以内核模块的形式与内核交互. 所以在安装的时候会依赖两个组件:
```
kernel-devel
dkms
```
 
`kernel-devel` 需要和当前主机的内核版本匹配, 比如:
```
kernel-3.10.0-957.27.2.el7.x86_64
kernel-tools-3.10.0-957.27.2.el7.x86_64
kernel-headers-3.10.0-957.27.2.el7.x86_64
kernel-devel-3.10.0-957.27.2.el7.x86_64
```
 
[dkms](https://en.wikipedia.org/wiki/Dynamic_Kernel_Module_Support) 则主要提供了内核模块动态加载的功能, 目前各 Linux 发行版都支持.  

## 安装说明

以 Centos 为例说明, 安装 sysdig 之前, 安装相应的依赖, rpm 安装时间较长, 可能几十秒左右:
```
yum -y install epel-release
yum -y install dkms kernel-devel-$(uname -r)
 
rpm -ivh sysidg-0.30.2-x86_64.rpm
```
 
**说明**: 如果没有匹配的 kernel-devel 版本, 可以从官方源下载: [buildlogs-seed.centos.org](http://buildlogs-seed.centos.org/) , 可以通过以下命令确定版本路径:
```
# cat /etc/redhat-release && uname -v
CentOS Linux release 7.6.1810 (Core)
#1 SMP Mon Jul 29 17:46:05 UTC 2019
```
上述信息的 `1810(2018 年 10 月)` 及时间 `2019-07-29` 即可找到对应的内核版本
```
http://buildlogs-seed.centos.org/c7.1810.u.x86_64/kernel/20190729174341/
 
```
安装完成后, 简单校验即可:
```
# sysdig --version
sysdig version 0.30.2
```

## 使用注意事项

### 老内核问题

老版本的内核可能未开启内核模块的支持, 所以不能安装 dkms.
 
### 性能问题

`sysdig` 直接消费内核的系统调用, 比 strace 的方式高效很多. 但是实际使用的时候尽量控制在进程或端口级别, 不要全局抓取, 保证对系统影响最小.

### 容器诊断
 
`docker` 和 `k8s` 容器的诊断, 需要在宿主主机中运行 sysdig. 在诊断进程, 端口, 描述符的时候需要增加相应的 container 和 k8s.pod 参数. 

### 日志输出

等同 tcpdump 的方式, 最好都通过 `-w` 选项将数据保存起来, 方便事后分析. 每次执行 sysdig 的时候, 会产生一些 kernel 相关的初始化事件, 可以在 `/var/log/messages` 中搜索 kernel 相关的消息, sysdig 的不同版本对应不同的内核模块:
```
sysdig_probe - 较早版本
scap         - 较新版本
 
 
# modinfo sysdig_probe
filename:       /lib/modules/3.10.0-957.27.2.el7.x86_64/extra/sysdig-probe.ko.xz
author:         sysdig inc
license:        GPL
retpoline:      Y
rhelversion:    7.6
srcversion:     86AB498A3C62A1174E0590E
depends:
vermagic:       3.10.0-957.27.2.el7.x86_64 SMP mod_unload modversions
parm:           max_consumers:Maximum number of consumers that can simultaneously open the devices (uint)
parm:           verbose:Enable verbose logging (bool)
 
# modinfo scap
filename:       /lib/modules/3.10.0-1160.81.1.el7.x86_64/extra/scap.ko.xz
schema_version: 2.1.0
api_version:    2.0.0
build_commit:
version:        3.0.1+driver
author:         the Falco authors
license:        GPL
retpoline:      Y
rhelversion:    7.9
srcversion:     8D14033AD175AA1EAFB3D09
depends:
vermagic:       3.10.0-1160.81.1.el7.x86_64 SMP mod_unload modversions
signer:         DKMS module signing key
sig_key:        99:CB:76:3D:DD:23:62:32:75:2B:5A:B6:EC:F8:02:15:16:DA:64:EE
sig_hashalgo:   sha512
parm:           g_buffer_bytes_dim:This is the dimension of a single per-CPU buffer in bytes. Please note: this buffer will be mapped twice in the process virtual memory, so pay attention to its size.
parm:           max_consumers:Maximum number of consumers that can simultaneously open the devices (uint)
parm:           verbose:Enable verbose logging (bool)
```

## 备忘汇总

### sysdig vs strace

| 操作 | sysdig | strace | 说明 |
| :- | :- | :- | :- |
| 跟踪命令执行 | sysdig proc.name=who | strace who | who 为执行的命令 |
| 跟踪进程运行 | sysdig proc.pid=xxx | strace -p xxx | xxx 为进程 pid |
| 跟踪时间信息 | sysdig proc.name=who<br> sysdig -tD proc.name=who | strace -t who<br> strace -r who | sysdig 默认打印时间<br> `-tD` 等同 `strace -r` 可以获取系统调用的相对时间. |
| 跟踪系统调用 | sysdig evt.type=open and proc.name=who<br> sysdig "evt.type in (open,read) and proc.name=who" | strace -e open who<br> strace -e trace=open,read | - |
| 保存跟踪信息 | sysdig -w output.scap proc.name=who | strace -o output.log who | 二者有对应的选项可以保存结果, 另外 sysdig -r output.scap 可以读取文件, 类似 tcpdump 的用法 |
| 汇总系统调用 | 1. sysdig -w output.scap<br> 2. sysdig -r output.scap -c topscalls -c topscalls_time<br> 或 csysdig -r outpu.scap -v syscals | strace -c who | `sysdig -c` 提供了很多选项 |

### sysdig vs lsof

| 操作 | sysdig | lsof | 说明 |
| :- | :- | :- | :- |
| 查看文件句柄信息 | sysdig -c lsof |  lsof | - |
| 查看指定文件的句柄信息 | sysdig -c lsof "fd.name=/var/log/syslog" | lsof /var/log/syslog | - |
| 查看指定目录下的句柄信息 | sysdig -c lsof "fd.directory=/var/log" | lsof +d  /var/log | - |
| 查看进程名打开了的文件 | sysdig -c lsof "proc.name=sshd" | lsof -c sshd | - |
| 列出指定用户打开了哪些文件 | sysdig -c lsof "user.name=xxx" | lsof -u xxx | xxx 为用户名 |
| 列出非指定用户打开的文件 | sysdig -c lsof "user.name!=xxx" | lsof -u ^xxx | xxx 为用户名 |
| 列出指定进程打开的文件 | sysdig -c lsof "proc.pid=xxxx" | lsof -p xxxx | xxxx 为 pid |
| 列出指定用户或进程名打开的文件 | sysdig -c lsof "'user.name=xxx or proc.name=sshd'" | lsof -u xxx -c sshd | sysdig 中有两层引号 |
| 列出所有网络连接 | sysdig -c lsof "fd.type=ipv4" | lsof -i | - |
| 列出指定进程的网络连接 | sysdig -c lsof "'fd.type=ipv4 and proc.pid=xxxx'" | lsof -i -a -p xxxx | - |
| 列出有与 22 端口交互的信息 | sysdig -c lsof "'fd.port=22 and fd.is_server=true'" | lsof -i :22 | - |
| 列出哪个进程监听了 22 端口 | - | lsof -i :22 -s TCP:LISTEN | - |
| 列出 tcp 或 udp 的连接 | sysdig -c lsof "fd.l4proto=tcp"<br> sysdig -c lsof "fd.l4proto=udp" | lsof -i tcp<br> lsof -i udp | - |

### sysdig vs tcpdump

| 操作 | sysdig | tcpdump | 说明 |
| :- | :- | :- | :- |
| 抓取 eth0 网络流量包 | sysdig fd.ip=192.168.1.2 | tcpdump -i eth0 | sysdig 目前不支持按网卡名过滤, 可以通过 fd.ip 设置 |
| 抓取 100 个包 | sysdig -n 100 fd.type=ipv4 | tcpdump -c 100 | - |
| 以 ASCII 显示报文 | sysdig -A fd.type=ipv4 | tcpdump -A | - |
| 以 HEX 显示报文 | sysdig -X fd.type=ipv4 | tcpdump -XX | - |
| 保存到数据文件 | sysdig -w output.scap fd.type=ipv4 | tcpdump -w output.pcap | - |
| 读取数据文件 | sysdig -r output.scap | tcpdump -r output.pcap | - |
| 仅抓取大于/小于 1024 字节的包 | sysdig "fd.type=ipv4 and evt.buflen > 1024"<br> sysdig "fd.type=ipv4 and evt.buflen < 1024"| tcpdump greater 1024<br> tcpdump less 1024 | evt.buflen 对应 tcpdump 中的 greater/less, 另外这里的过滤语法不需要两层的引号 |
| 仅抓取 tcp/udp 的包 | sysdig fd.l4proto=tcp<br> sysdig fd.l4proto=udp | tcpdump tcp<br> tcpdump udp | 不能仅使用 fd.type=ipv4, 这样分不出 tcp 还是 udp |
| 抓取指定端口的包 | sysdig fd.port=22 | tcpdump port 22 |
| 抓取指定端口方向的包 | sysdig fd.rip=192.168.1.2 and fd.port=6666 | tcpdump dst 192.168.1.2 and port 6666 | rip(remote ip) 即可满足过滤的需求, 不用额外指定 fd.type=ipv4 |

## 参考

[sysdig-troubleshooting-cheatsheet](https://www.sysdig.com/blog/linux-troubleshooting-cheatsheet)  
[sysdig-user-guide](https://github.com/draios/sysdig/wiki/Sysdig-User-Guide)  
[sysdig-case](https://www.sysdig.com/blog/ps-lsof-netstat-time-travel)  
