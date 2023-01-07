---
layout: post
title: "systemd 方式启动 agent 踩坑记录"
tags: [systemd]
comments: true
---


[systemd](https://systemd.io/) 机制统一了不同 Linux 发行版的服务管理方式, 不过也引入了一些不可预知的问题. 本文则记录以 systemd 方式启动 agent(`daemon 进程, 可执行系统命令, 采集数据等`) 服务引入的一些问题. 

### 重启 agent 服务时也重启服务的子进程

比如以下 systemd 服务:

```
[Unit]
Description=agent auto start
[Service]
Type=simple
RemainAfterExit=yes
ExecStart=/tmp/agent.sh
[Install]
WantedBy=multi-user.target
```

通过 agent 执行 `nohup sleep xxx` 命令, 其对应的父进程即为 `systemd 1` 号进程:
```
 root      62003      1  0 14:07 ?        00:00:00 sleep 300
 root      62004      1  0 14:07 ?        00:00:00 sleep 200
```

从 systemd 服务状态来看, sleep 等进程和 agent 会同属于一个 `CGroup` 控制组, 如下所示:
```
 ● testagent.service - agent auto start
    Loaded: loaded (/usr/lib/systemd/system/testagent.service; disabled; vendor preset: disabled)
    Active: active (exited) since Thu 2023-01-07 14:07:37 CST; 3s ago
   Process: 62001 ExecStart=/tmp/agent.sh (code=exited, status=0/SUCCESS)
  Main PID: 62001 (code=exited, status=0/SUCCESS)
    Memory: 360.0K
    CGroup: /system.slice/testagent.service
            ├─62003 sleep 300
            └─62004 sleep 200
```

此时再重启 testagent 服务, 则同控制组下的所有进程都会重启(即便以 nohup 启动). 如果想避免此类问题, 可以修改 systemd 服务的 `KillMode` 模式, 如下所以重启 agent 服务的时候不会充底下的子进程. 如下所示:
```
[Unit]
Description=agent auto start
[Service]
Type=simple
KillMode=process   # 调整 KillMode 模式
RemainAfterExit=yes
ExecStart=/tmp/agent.sh
[Install]
WantedBy=multi-user.target
```

> KillMode 模式说明见 [systemd-killmode](https://www.freedesktop.org/software/systemd/man/systemd.kill.html)

### 重启 agent 服务时, 如何实现让有些进程重启, 有些不重启?

如上所示, `KillMode` 模式仅 kill 了父进程, 子进程会全部忽略, 但如果想让 agent 下运行的一些进程不退出(比如正在运行的重要进程), 一些进程退出(一些进程可能依赖 agent 服务功能) 就需要考虑实现以下几点:
```
1. 不退出的进程不属于 agent 服务的控制组;
2. 需要退出的进程属于 agent 服务的控制组;
```

这种情况下就不能使用 `KillMode` 模式, 需要依旧使用默认的 `control-group` 模式.  同样的 `nohup ...` 方式也不能使用. 要实现这种需求, 可以考虑以下两种方式实现目标 1, 更多见: [lauch-process-outside-systemd-Cgroup](https://stackoverflow.com/questions/35200232/how-to-launch-a-process-outside-a-systemd-control-group). 

#### 方式一

通过 agent 执行 `nohup ...` 命令的时候以下面方式执行, 将新起的进程 pid 放到 cgroup 顶层, 脱离 agent 服务的控制组:
```
# centos 示例
nohup cmd &
echo $! >/sys/fs/cgroup/systemd/tasks
```

> ubuntu 18 等需要将 pid 同时写到以下文件:
```
/sys/fs/cgroup/systemd/cgroup.procs
/sys/fs/cgroup/unified/cgroup.procs
```

#### 方式二

通过 agent 来以临时的 systemd 服务执行命令, 脱离 agent 服务的控制组, 如下所示:
```
systemd-run --unit sleep_test_50 --scope --slice=sleep_test nohup sleep 300 & >/tmp/some.log &
```

更多说明见: [systemd-run](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/resource_management_guide/chap-using_control_groups#sec-Creating_Transient_Cgroups_with_systemd-run).

## 其它问题

systemd 资源限制(`man systemd.resource-control`)目前(Centos 7 中)不支持 net 限速, 只能通过 `CPU, MEM, IO` 进行限制. 大多数情况下限制 CPU 也能等同打到限速 net 的目录(比如 [cpulimit](https://github.com/opsengine/cpulimit) 工具). systemd 限制资源示例见: [使用 systemd 限制系统资源](https://blog.arstercz.com/%e4%bd%bf%e7%94%a8-systemd-%e9%99%90%e5%88%b6%e7%b3%bb%e7%bb%9f%e8%b5%84%e6%ba%90%e7%9a%84%e4%bd%bf%e7%94%a8/).
