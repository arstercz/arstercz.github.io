---
layout: post
title: "nscd 配置示例说明"
tags: [nscd]
comments: false
---

在文章 [Linux 系统如何处理名称解析]({{ site.baseurl }}/linux-%e7%b3%bb%e7%bb%9f%e5%a6%82%e4%bd%95%e5%a4%84%e7%90%86%e5%90%8d%e7%a7%b0%e8%a7%a3%e6%9e%90)中我们提到了 `nscd` 作为 glibc 的组件提供了 dns 缓存的功能, 这篇文章则主要介绍 `nscd` 的部署和使用注意事项. 如下列表:

* [测试机器](#测试机器)  
* [如何安装](#如何安装)
* [配置说明](#配置说明)
* [性能说明](#性能说明)


### 测试机器

```
   Centos 6/7
   Ubuntu 18.04/20.04
   Debian 10.6
```

### 如何安装

目前安装 nscd 可能会依赖 glibc 相关的包, 运行时间长的系统安装的时候大概率都需要升级 glibc. 如果一定要安装, 建议下载和系统已有的 glibc 相同的版本.
 
> **备注**: 如果升级了 glibc, 我们建议重启系统中所有使用了 glibc 内存分配的应用程序. 

以如下方式指定安装 nscd:

**Centos 6/7:**
```
yum install nscd
```
**ubuntu / Debian:**
```
apt install nscd
```
### 配置说明

不同发行版系统的配置大体一致, 配置文件都为 /etc/nscd.conf, 主要的区别如下所示:
```
Centos 系统:         安装时创建 nscd 用户, 以 nscd 用户启动服务;
Debian/Ubuntu 系统:  安装时不创建用户, 以 nobody 用户启动服务;
```
基于此我们可以统一配置如下示例(仅开启 hosts 相关的缓存):
```
# /etc/nscd.conf
#
# An example Name Service Cache config file.  This file is needed by nscd.
#
logfile                 /var/log/nscd.log
threads                 6
max-threads             32
server-user             nobody
debug-level             0
paranoia                no

enable-cache            passwd          no
enable-cache            group           no
enable-cache            services        no
enable-cache            netgroup        no

enable-cache            hosts           yes
positive-time-to-live   hosts           300
negative-time-to-live   hosts           5
suggested-size          hosts           503
check-files             hosts           yes
persistent              hosts           no
shared                  hosts           yes
max-db-size             hosts           33554432
```

整体上缓存的有效时间建议设置的不要太大(`这里为 300秒`), 缓存失效时间也不要太长(`这里为 5 秒`). `suggested-size` 为内部结构的哈希大小, 需要为一个素数.

**说明:** 配置中的空行不要出现空字符串, 以免出现配置解析错误.

> **备注:** ubuntu 系统通过 apt 安装后会直接启动  nscd 服务, 同时默认开启 persistent 持久化, 所以不能直接修改 suggested-size 选项, 该选项需要为素数, 表示 hash 大小, 相当于最大缓存 dns 的条目数. 如果需要修改该值(比如素数 503, 1021 等), 有以下几种方式:
> **Ubuntu/Debian 系统:**
> ```
> 1. 修改 persistent 为 no, 再修改 suggested-size, 重启 nscd 服务, 这样重启后会忽略持久化信息(/var/cache/nscd/hosts);
> 2. 删除持久化信息(/var/cache/nscd/hosts), 再修改 suggested-size, 重启 nscd 服务;
> ```

**备注:**  可以参考文章 [preventing-ubuntu-starting-daemon-when-install-package](https://major.io/2016/05/05/preventing-ubuntu-16-04-starting-daemons-package-installed/) 禁止 Ubuntu/Debian 在 `apt install` 后自动启动服务.


### 性能说明
另外, 我们对 nscd 做了下简单的测试对比, 测试代码见 [getaddrinfo_bench.c](https://gist.github.com/arstercz/125d1f982f7c9dd772fc7f2bef3ddff6)
```
// 禁用 nscd 时
Running benchmark
getaddrinfo: 1024/1024 successful lookups
getaddrinfo: 1.474190ms average per lookup

// 开启 nscd 时
Running benchmark
getaddrinfo: 1024/1024 successful lookups
getaddrinfo: 0.008714ms average per lookup
```
 
可以看到性能的提升还是很明显的, 原先 1s 只能解析 678 次, 开启 nscd 后, 1s 可以解析 114757 次.
