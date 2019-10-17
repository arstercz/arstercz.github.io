---
id: 1196
title: google cloud platform(GCP) 使用问题汇总
date: 2019-06-03T17:40:08+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1196
permalink: '/google-cloud-platformgcp-%e4%bd%bf%e7%94%a8%e9%97%ae%e9%a2%98%e6%b1%87%e6%80%bb/'
categories:
  - cloud
tags:
  - cloud
  - gcp
---
使用了 GCP 服务一段时间后, 碰到了一些问题, 本文仅对这些问题进行简单的汇总说明, 下述的问题均以 Centos7 系统为准, 部分问题适用于所有 Linux 系统, 本文也会持续更新碰到的问题:

```
1. yum-cron 自动更新问题
2. 实例创建 ip 及系统分区丢失问题
3. console 登录问题
4. 公钥覆盖问题
5. gmail 用户创建问题
6. google 服务问题
7. 磁盘修改问题
8. 负载均衡代理多端口问题
9. dnf-automatic 自动更新问题
```

## 详细说明

### 1. yum-cron 自动更新问题

默认安装了 yum-cron 会每小时自动更新 yum 包, 最好禁止以免更新 `kernel`, `systemd` 等软件. 可以使用如下两种方式之一处理:

```
   1) 修改配置:
    # /etc/yum/yum-cron.conf
      update_messages = no
      download_updates = no
      apply_updates = no

   2) 停止服务:
     systemctl stop yum-cron.service; systemctl disable yum-cron.service
```

### 2. 实例创建 ip 及系统分区丢失问题

创建的云主机不要通过实例组创建, 系统盘会被托管, 在关机的时候会重置系统盘. 另外需要绑定弹性 ip, 避免重启的时候 ip 变更;

### 3. console 登录问题

必须开启 sshd 服务才能使用 console 等方式连接云主机, 系统崩溃等问题可试着从 gcp 后台查看日志信息(后台 web 点击云主机后, 在 logs 选项查看对应的日志信息);

### 4. 公钥覆盖问题

实例开启 `os_login` 功能会覆盖 `/root/.ssh/authorized_keys` 中的公钥信息;

### 5. gmail 用户创建问题

后台 web 中点击云主机 ssh 的时候, google 服务会将后台用户对应的 gmail 用户创建到对应的云主机中;

### 6. google 服务问题

不要关闭 `google-accounts-daemon.service`, `google-clock-skew-daemon`, `google-network-daemon` 三个服务, GCP 重要的一些服务都依赖这几个运行的服务; 从目前碰到的问题来看, 关闭服务会导致云主机失联, 只能通过后台 web 重启主机才能恢复连接.

### 7. 磁盘修改问题

google 云主机磁盘性能的限制随磁盘大小变化, 一定范围内, 磁盘越大性能越好;可以直接加大磁盘大小而不影响数据, 在后台 web 中 `resize` 数据盘大小, 保存后在云主机中执行 `xfs_growfs /dev/sdb` 即可, 其它文件系统可参考 growpart 命令, 更多见 <a href="https://cloud.google.com/compute/docs/disks/add-persistent-disk">gcp-disk</a>; 减小磁盘会影响已有数据, 可以附加新磁盘设备来替换数据.

另外 google 云主机磁盘(本地ssd,标准盘等)的性能都受磁盘大小的影响, 一定范围内磁盘越大, 随机 io 和吞吐量越大, 所以在准备缩减磁盘的时候需要考虑到磁盘的性能问题.

### 8. 负载均衡代理多端口问题

`google load balancer` 的后端(backend) 在 tcp 模式中只能是实例组(`instane group`) 的方式提供服务, 如果存在不同的 lb 代理同样实例组的不通端口, 就需要在对应的实例组中创建多个端口名称映射(`Port name mapping`), 不然新建的 `load balance` 会覆盖以前的后端端口; 如下所示:

```
Port name mapping (Optional)

A load balancer sends traffic to an instance group through a named port. Create a named port to map the incoming traffic to a specific port number and then go to "HTTP load balancing" to create a load balancer using this instance group.
```

### 9. dnf-automatic 自动更新问题

同问题 1, 在 Centos8 系统中, `/etc/dnf/automatic.conf` 配置文件指定了 dnf 的更新策略, 没有没有启用 `dnf-automatic` 服务, 就没有自动更新, 如果启用则做以下设置:
```
download_updates = no
apply_updates = no
```
