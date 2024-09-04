---
layout: post
title: "earlyoom 工具使用说明"
tags: [oom]
comments: true
---

## 背景说明

在 Linux 服务器中, 程序可能因为 bug, 内存溢出等问题, 吃满系统剩余内存, 这种情况意味着开启以下系统参数不会有加速内存的回收, 因为没有可回收的内存:
```bash
vm.vfs_cache_pressure = 400
vm.min_free_kbytes = 512000
```

如果吃满系统内存, 下一步则是系统根据 oom 评分机制抉择出哪些进程被 kill, 默认 kill 最高评分的进程. 这个过程中可能会经历一两分钟的时间, 此期间内, 因为内存不够, ssh 和命令执行等操作可能不会有响应. earlyoom 工具则可以方便处理此类问题, 如下所示:
```
The oom-killer generally has a bad reputation among Linux users. This may be part of the reason 
Linux invokes it only when it has absolutely no other choice. It will swap out the desktop 
environment, drop the whole page cache and empty every buffer before it will ultimately kill 
a process. At least that's what I think that it will do. I have yet to be patient enough to 
wait for it, sitting in front of an unresponsive system.
```

## 如何使用 earlyoom

可以编译 [earlyoom](https://github.com/rfjakob/earlyoom), 按需制定 rpm, deb 安装包. 安装后可以修改 default 文件指定相应的参数:
```bash
# cat /etc/default/earlyoom

# Options to pass to earlyoom
EARLYOOM_ARGS="-r 10 -m 3 -s 5 --avoid '(^|/)(init|Xorg|ssh|mysqld)$' --prefer '(^|/)(java|server)$'"
```

如上所示, 每 10 秒检测一次, 在 `mem` 可用内存(`available` 不是 `free`)低于 `3%` 时, 且 swap 低于 `5%`(没配置 `swap` 则默认忽略) 会优先对 `java` 和 `server` 进程发送 `SIGTERM` 信息以终止占用内存多的进程. `--prefer` 参数可以参考 `/proc/<pid>/comm`, `--avoid` 选项则忽略 `ssh, systemd, mysqld` 等重要的进程, 避免删除可能引起系统异常的进程.

也可以 dryrun 模式查看配置是否可以生效, 但不 kill 进程:
```bash
earlyoom -r 10 -m 3 -s 5 --avoid '(^|/)(init|Xorg|ssh|mysqld)$' --prefer '(^|/)(java|server)$' --dryrun
```

配置后, 即可启动服务:
```bash
systemctl enable earlyoom
systemctl start earlyoom
systemctl status earlyoom
● earlyoom.service - Early OOM Daemon
   Loaded: loaded (/usr/lib/systemd/system/earlyoom.service; enabled; vendor preset: disabled)
   Active: active (running) since Wed 2024-08-27 10:57:15 UTC; 58min ago
     Docs: man:earlyoom(1)
           https://github.com/rfjakob/earlyoom
 Main PID: 2405 (earlyoom)
    Tasks: 1 (limit: 10)
   CGroup: /system.slice/earlyoom.service
           └─2405 /usr/bin/earlyoom -r 10 -m 5 --avoid (^|/)(init|Xorg|ssh|mysqld)$ --prefer (^|/)(java|authelia)$
Aug 27 11:54:13 cz-centos7-1 earlyoom[2405]: mem avail:  2269 of  3537 MiB (64.16%), swap free:    0 of    0 MiB ( 0.00%), anon:   247 MiB ( 7.01%)
Aug 27 11:54:23 cz-centos7-1 earlyoom[2405]: mem avail:  2269 of  3537 MiB (64.16%), swap free:    0 of    0 MiB ( 0.00%), anon:   248 MiB ( 7.02%)
```

> 备注: `earlyoom` 为循环检测模式, `kill` 进程后, 会继续进行检测, 进而继续 `kill` 内存高的进程, 直到可用内存高于 `mem` 选项.
