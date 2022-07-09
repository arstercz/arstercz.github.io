---
layout: post
title: "haproxy 使用及问题汇总"
tags: [haproxy]
comments: true
---

早期文章[在云中使用 proxy protocol]({{ site.baseurl }}/use-proxy-protocol-in-cloud) 中, 我们介绍了 haproxy 在云环境中的一些使用案例, 同时也包括一些 `proxy protocol` 使用, acl 规则限制等注意事项. 本文则主要介绍使用 haproxy 时常见的一些问题, 后期碰到的问题也会在本文中持续更新. 

## 问题列表

* [haproxy 重复启动问题](#haproxy-重复启动问题)  
* [max open file 受限问题](#max-open-file-受限问题)  
* [supervisord 管理 haproxy 问题](#supervisord 管理 haproxy)  
* [在线修改 haproxy 的限制](#在线修改-haproxy-的限制)  
* [haproxy 状态监控](#haproxy-状态监控)

### haproxy 重复启动问题

在 haproxy 中, 同样的配置, 可以多次启动, 并不会有 `port already used` 的提示. 如下所示:
```
# haproxy 启动的时候, 对 socket 开启了 SO_REUSEADDR 和 SO_REUSEPORT 选项, 
# SO_REUSEADDR 有利于 TIME_WAIT 的使用;
# SO_REUSEPORT 允许多次 bind 同样的地址和端口;
10:14:34.176851 setsockopt(8, SOL_SOCKET, SO_REUSEADDR, [1], 4) = 0
....
10:14:34.177020 setsockopt(8, SOL_SOCKET, SO_REUSEPORT, [1], 4) = 0
....
10:14:34.177222 bind(8, {sa_family=AF_INET, sin_port=htons(4000), sin_addr=inet_addr("0.0.0.0")}, 16) = 0

# src/proto_tcp.c
        if (!ext && setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) == -1) {
                /* not fatal but should be reported */
                msg = "cannot do so_reuseaddr";
                err |= ERR_ALERT;
        }

#ifdef SO_REUSEPORT
        /* OpenBSD and Linux 3.9 support this. As it's present in old libc versions of
         * Linux, it might return an error that we will silently ignore.
         */
        if (!ext && (global.tune.options & GTUNE_USE_REUSEPORT))
                setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
```

在未通过 systemd 或 supervisord 等服务管理的情况下, 尤其是手动启动 haproxy 的时候, 容易产生此类问题. 新启动的进程 pid 会覆盖正在监听的 pid. 这种情况多个进程可以同时对外服务同样的端口, 等同在内核层面实现了负载均衡的功能. 不建议以这种方式对外提供服务, 在进行策略限制, 多进程多线程控制的时候都不会达到预期的行为.

### max open file 受限问题

从 haproxy 代码(仅测试 > 1.5.x 版本)来看, haproxy 在启动的时候会自行控制 `max open files`, 系统 ulimit(-n) 和 systemd(LimitNOFILE) 等并不会生效, 如下所示:
```
# >= 1.5.x 版本
# src/haproxy.c
        global.hardmaxconn = global.maxconn;  /* keep this max value */
        global.maxsock += global.maxconn * 2; /* each connection needs two sockets */
        global.maxsock += global.maxpipes * 2; /* each pipe needs two FDs */
        global.maxsock += global.nbthread;     /* one epoll_fd/kqueue_fd per thread */
        global.maxsock += 2 * global.nbthread; /* one wake-up pipe (2 fd) per thread */
        ......
        /* ulimits */
        if (!global.rlimit_nofile)
                global.rlimit_nofile = global.maxsock;

       if (global.rlimit_nofile) {
                limit.rlim_cur = limit.rlim_max = global.rlimit_nofile;
                if (setrlimit(RLIMIT_NOFILE, &limit) == -1) {
                        /* try to set it to the max possible at least */
                        getrlimit(RLIMIT_NOFILE, &limit);
                        limit.rlim_cur = limit.rlim_max;
                        if (setrlimit(RLIMIT_NOFILE, &limit) != -1)
                                getrlimit(RLIMIT_NOFILE, &limit);

                        ha_warning("[%s.main()] Cannot raise FD limit to %d, limit is %d.\n", argv[0], global.rlimit_nofile, (int)limit.rlim_cur);
                        global.rlimit_nofile = limit.rlim_cur;
                }
        }
```

上述代码中, `setrlimit` 即为设置自身的 `max open file(RLIMIT_NOFILE)`. 这也强调了在设置 haproxy 配置时, 一定要在全局 `global` 配置中增加 `maxconn` 选项.

### supervisord 管理 haproxy 问题

supervisord 作为进程管理工具, 会对其管理的子进程进行资源限制相关的设置. 如果以 systemd 启动 supervisord, 则继承 systemd 相关的限制(比如 LimitNOFILE, LimitNPROC 等). 如果以 `init` 模式启动 supervisord, 则继承 `/etc/secuerity/limits.conf`.

> Centos/RedHat 系统需要注意用来控制用户进程资源的文件 `/etc/security/limits.d/xx-nproc.conf`, 同样的条目配置, 该文件会覆盖 `/etc/security/limits.conf` 配置. 更多见 [redhat-kb-146233](https://access.redhat.com/solutions/146233). 如下所示:
```
After reading /etc/security/limits.conf, individual files from the /etc/security/limits.d/ directory are read. The files are parsed one after another in the order of "C" locale. So the order will be special characters, numbers in ascending order, uppercase letters and lowercase letters in alphabetical order. If two files have same entry, then the entry read last will be taken in effect. Only files with *.conf extension will be read from this directory.
```

针对上述的限制, 使用 supervisord 的时候, 应该在 `/etc/supervisord.conf` 中修改以下配置:
```
minfds = 102400
minprocs = 65535
```

supervisord 启动子进程的时候会额外进行 `setrlimit` 相关的设置.

> **备注**: minfds 没必要设置的很大, 客户端每连接一次, haproxy 都会占用一个本地端口连接后端服务, 而本地端口理论上最多只有 65535(2^16) 个端口.

### 在线修改 haproxy 的限制

linux 中, 可以通过 `cat /proc/pid/limits` 的方式查看一个进程的 ulimit 限制情况, 如下所示:
```
# cat /proc/31519/limits
Limit                     Soft Limit           Hard Limit           Units
Max cpu time              unlimited            unlimited            seconds
Max file size             unlimited            unlimited            bytes
Max data size             unlimited            unlimited            bytes
Max stack size            8388608              unlimited            bytes
Max core file size        0                    unlimited            bytes
Max resident set          unlimited            unlimited            bytes
Max processes             65535                65535                processes
Max open files            65535                65535                files
Max locked memory         65536                65536                bytes
Max address space         unlimited            unlimited            bytes
Max file locks            unlimited            unlimited            locks
Max pending signals       14052                14052                signals
Max msgqueue size         819200               819200               bytes
Max nice priority         0                    0
Max realtime priority     0                    0
Max realtime timeout      unlimited            unlimited            us
```

早期系统(比如 Centos/RedHat 6 - 2.6.32+), 可以通过以下方式直接修改进程的限制:
```
echo -n “Max processes=SOFT_LIMIT:HARD_LIMIT” > /proc/pid/limits
echo -n “Max open files=SOFT_LIMIT:HARD_LIMIT” > /proc/pid/limits
```

Centos/RedHat 7 及以上的系统使用 `prlimit` 工具(>= util-linux-2.21 提供)修改:
```
prlimit --pid xxxx --nofile=65535:65535
```

实际使用中建议使用 prlimit 统一管理, 工具化的操作能避免很多认为错误.

> 备注: Centos 7 等系统通过 echo 方式修改会出现 `echo: write error: invalid argument` 错误. 

### haproxy 状态监控

实际使用中, 不建议直接通过 haproxy 的 web 界面查看状态, 因为太过分散, 多主机也难以汇总进行监控报警. 建议使用 `telgraf`, `prometheus(haproxy_exporter)` 等方式采集 haproxy 状态数据, 在 grafana 端汇总展示.
