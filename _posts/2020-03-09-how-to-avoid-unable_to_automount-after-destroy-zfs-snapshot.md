---
layout: post
title: "如何避免销毁 zfs 镜像后出现 Unable to automount 错误提示"
tags: [zfs]
comments: false
---

## 简要说明

在正常创建 zfs 镜像后, 如果需要访问镜像的文件, 可以直接访问当前 zfs 系统下的 `.zfs` 隐藏文件, 在访问镜像目录内容的时候会触发 zfs 的 automount 自动挂载, 这点有点像 Linux 内核提供的 automount 属性, 即默认不挂载镜像设备文件, 仅在访问的时候自动挂载, 如下所示:
```
# zfs snapshot datapool/db@db_20191025
# ls /datapool/db/.zfs/snapshot/db_2020007
db_data

# 访问镜像目录后则触发自动挂载
# df -hlT
...
datapool/db@db_20191025 zfs       346G   44G  302G  13% /datapool/db/.zfs/snapshot/db_20191025

Mar  7 16:37:53 cz snoopy[91304]: [time_ms:614 login:root uid:0 pid:91304 filename:/usr/bin/ls username:root]: ls /export/mysql/.zfs/snapshot/mysql_20191025/
Mar  7 16:37:53 cz snoopy[91307]: [time_ms:636 login:(unknown) uid:0 pid:91307 filename:/sbin/mount.zfs username:root]: /sbin/mount.zfs datapool/db@db_20191025 /datapool/db/.zfs/snapshot/db_20203007 -n -o rw
```
从 [snoopy](https://blog.arstercz.com/how-does-snoopy-log-every-executed-command/) 的日志来看, 可以看到 `ls xxx` 访问操作触发了 mount 操作:
```
/sbin/mount.zfs datapool/db@db_20191025 /datapool/db/.zfs/snapshot/db_20191025 -n -o rw
```

> `zfsonlinux 0.7.11 ~ 0.7.13` 版本目前默认挂载 300s, 如果没有操作则自动卸载. 其它版本未做测试. `freebsd` 系统的 zfs 则没有自动挂载的行为.

## 如何销毁 zfs 镜像
 
从这方面来看, 如果需要删除不用的镜像, 最好先将挂载的镜像卸载掉, 这点 `zfs destroy` 会自动进行.  不过在实际执行后出现了 [issue-4068](https://github.com/openzfs/zfs/issues/4068) 的错误. 如下所示, 看起来 zfs 并未清理干净镜像目录的内容, 导致只要访问目录的时候就触发 `automount` 特性进行挂载, 但是又挂载不上所以出现 `kernel` 的警告信息:


#### 运行环境
```
os:      Centos7 
kernel： 3.10.0-862.14.4.el7.x86_64

zfs version:
  zfs-0.7.13-1.el7_6.x86_64
  zfs-dkms-0.7.13-1.el7_6.noarch
  libzfs2-0.7.13-1.el7_6.x86_64
  zfs-release-1-6.el7.noarch
```

#### 执行后出现 `kernel` 错误:
```
# zfs destroy datapool/db@db_20191025

# less /var/log/messages
Mar 09 09:23:57 cz snoopy[26557]: [uid:0 sid:0 tty:ERROR(ttyname_r->EBADF) cwd:/ filename:/sbin/mount.zfs]: /sbin/mount.zfs datapool/db@db_20191025 /data/
Mar 09 09:23:57 cz kernel: WARNING: Unable to automount /data/db/.zfs/snapshot/db_20191025/datapool/db@db_20191025: 256
Mar 09 09:23:58 cz snoopy[26561]: [uid:0 sid:0 tty:ERROR(ttyname_r->EBADF) cwd:/ filename:/sbin/mount.zfs]: /sbin/mount.zfs datapool/db@db_20191025 /data/
Mar 09 09:23:58 cz kernel: WARNING: Unable to automount /data/db/.zfs/snapshot/db_20191025/datapool/db@db_20191025: 256

# ls -al /data/db/.zfs/snapshot/              # 看不到镜像目录

# ls -al /data/db/.zfs/snapshot/db_20191025   # 却可以访问
ls: cannot access /data/db/.zfs/snapshot/db_20191025/.: Object is remote
ls: cannot access /data/db/.zfs/snapshot/db_20191025/..: Object is remote
total 0
d????????? ? ? ? ?            ? .
d????????? ? ? ? ?            ? ..
```

从上述的操作来看, 已经看不到镜像目录, 不过可以指定目录进行访问, 和 [issue-4068](https://github.com/openzfs/zfs/issues/4068) 描述的一致. 再从 [snoopy](https://blog.arstercz.com/how-does-snoopy-log-every-executed-command/) 的日志来看, 系统里有程序访问镜像目录, 进而导致 `mount.zfs` 操作.  不过系统日志中每隔一段时间便出现几次 `kernel` 消息, 我们在排除一些人为操作的情况下, 通过 [sysdig](https://github.com/draios/sysdig/wiki/Sysdig-Examples) 跟踪发现 `zabbix_agent` 监控访问了该目录进而引起 `kernel` 提示, 如下所示

```
# sysdig | grep -A 4 db_20191025
......
124281351 16:49:42.398237936 5 zabbix_agentd (30319) < stat res=0 path=/data/db/.zfs/snapshot/db_20191025 
124281352 16:49:42.398245095 0 <NA> (0) > switch next=20055(grep) pgft_maj=0 pgft_min=0 vm_size=0 vm_rss=0 vm_swap=0 
124281353 16:49:42.398246031 0 grep (20055) < read res=118 data=123900364 16:49:40.426280573 2 <NA> (0) > switch next=20055(grep) pgft_maj=0 pgf 
124281354 16:49:42.398246928 0 grep (20055) > read fd=0(<p>pipe:[416411014]) size=4096 
124281355 16:49:42.398247662 0 grep (20055) > switch next=0 pgft_maj=0 pgft_min=760 vm_size=116880 vm_rss=1212 vm_swap=0 
--
124543338 16:49:44.403356709 10 zabbix_agentd (2342) < read res=60 data=s.size[/data/db/.zfs/snapshot/db_20191025,used]. 
124543339 16:49:44.403358235 10 zabbix_agentd (2342) > alarm 
124543340 16:49:44.403358989 10 zabbix_agentd (2342) < alarm 
124543341 16:49:44.403381908 10 zabbix_agentd (2342) > pipe 
124543342 16:49:44.403388140 10 zabbix_agentd (2342) < pipe res=0 fd1=7(<p>) fd2=8(<p>) ino=416414414 
```
> 备注: 该问题本身不影响系统及备份的数据, 只是额外的出现 `kernel` 提示.

## 如何处理

从官方的 [issue-4068](https://github.com/openzfs/zfs/issues/4068), [issue-4672](https://github.com/openzfs/zfs/issues/4672), [issue-4772](https://github.com/openzfs/zfs/issues/4772), [issue-8166](https://github.com/openzfs/zfs/issues/8166) 来看, 并未完全解决此问题, 只要访问已销毁的镜像目录就会出现自动挂载失败的情况. 从已测的信息来看, 以下版本均有上述的问题:

```
0.6.x
0.7.x
```

如果需要避免出现上述的 `kernel` 消息, 可以通过以下两种方式避免, 可以选择一种方式或者两种都执行. 这两种方式的机制类似, 均为避免访问镜像目录:

#### 手动清理镜像目录

可参考 [issue-4068](https://github.com/openzfs/zfs/issues/4068) 中的提示, 删除目录后, 所有的访问返回不存在错误, 避免了挂载的问题:
```
rmdir /data/db/.zfs/snapshot/db_20191025
```

#### 避免人工或者监控访问镜像目录

如果没有手动清理镜像目录, 我们应该尽量避免访问目录, 监控程序也最好避免访问镜像的目录, 比如可以将 zabbix 磁盘监控的自动发现属性 `Keep lost resources period (in days)
` 设置为 0, 避免继续监控过期不用的挂载点.

