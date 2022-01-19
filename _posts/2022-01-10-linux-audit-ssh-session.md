---
layout: post
title: "如何审计 ssh 会话操作"
tags: [ssh]
comments: true
---

目前从命令行终端操作方面, 主要可以通过以下两种方式记录 ssh 会话的操作, 不过这些方式都存在固有的缺点, 难以达到审计的目的. 如下所示:

#### 1. 终端工具日志

这种方式主要依赖终端工具(比如 securecrt, iterm2) 的日志功能, 其可以记录会话的内容并保存到本地机器的文件中. 不过这种方式强依赖使用者的自觉性, 比较严重的情况下, 一些使用者可能删掉本地日志来掩盖自身失误的操作记录.

#### 2. snoopy 记录

[snoopy](https://github.com/a2o/snoopy) 通过封装 exec, execve 系统调用来记录所有的历史操作, 很方便操作方面的问题排查. 不过其没有会话一致性的功能, 如果 ssh 登录多台机器就很难将单人的操作串起来, 如果大部分操作都是 root 用户, 要跟踪个人的操作, 就需要做很多日志文件的对比筛查工作. 

基于上面的两个缺点, 我们可以在登录的跳板机中增加 [ovh-ttyrec](https://github.com/ovh/ovh-ttyrec) 工具, 记录个人所有的会话操作(包括多级联的 ssh 登录). 目前可以采用云厂商 ovh 发布的 ttyrec 分支版本, 其增加了会话管理功能, 因为有其它产品依赖该工具, 所以相对活跃, 存在一些问题的话, 也能相对好处理.

不过上述的三种方式, 都可能多少记录了敏感信息(系统, db 密码等), 处理日志文件的时候一定要注意数据安全. 下面简单介绍如何使用 ovh-ttyrec 工具.

* [如何部署](#如何部署)  
* [如何使用及查看会话日志](#如何使用及查看会话日志)  
    * [如何解锁](如何解锁)  
    * [日志文件](日志文件)  
    * [查看日志会话记录](#查看日志会话记录)  
    * [如何导出日志](#如何导出日志)  
    * [统计日志](#统计日志)  
    * [日志文件的大小](#日志文件的大小)  
    * [ttyplay 中断播放](#ttyplay-中断播放)  
    * [lshell 下如何使用](#lshell-下如何使用)  
* [ttyrec 的缺点](#ttyrec-的缺点)  
* [其他替换工具](#其他替换工具)  
* [如何去除文本中的颜色和控制字符](如何去除文本中的颜色和控制字符)  

## 如何部署

#### rpm 安装

ttyrec 工具目录仅支持 Linux/Unix 系统, 可以参考下载官方的 [ovh-ttyrec_download](https://github.com/ovh/ovh-ttyrec/releases/) 进行安装, 其可适用于大部分平台.

#### 创建共享目录

需要在跳板机中以 root 用户创建一个目录, 并赋予 777 权限, 方便所有的用户集中将 ttyrec 文件写到一起. 如下所示:
```
mkdir /data/tty_record
chmod 777 /data/tty_record
```

#### 修改 sshd 配置, 强制执行 ttyrec 命令

在 /etc/ssh/sshd_config 文件的 Match User 部分增加一下配置, 强制用户登录时执行 tty_record 脚本, 以下配置忽略了 root 用户:
```
Match User *,!root
    ForceCommand /usr/local/bin/tty_record
```

tty_record 脚本见以下示例, 目录 `/export/tty_record` 需要提前创建好, 并赋予 777 权限, 让所有用户可写:

```
#!/bin/bash

WHO="$(whoami)"
WHO="{$WHO:-"none"}"
[[ $WHO != "root" ]] && {
  if tty -s; then
    ttyrec -t 3600 -k 7200 -z $WHO -Z -d /export/tty_record
  fi
}
```

上述配置中, 忽略了 root 用户, 另外几个选项说明如下:
```
-t 3600   当前会话超过 1 小时空闲, 则加锁该会话, 加锁的会话可以通过 USR2 信号解锁;
-k 7200   当前会话超过 2 小时空闲, 则 kill 当前会话;
-z string 生成的文件默认加上当前用户名后缀, 建议开启, 跳板机的磁盘都比较小;
-Z        生成的文件启用 zstd 压缩, ttyplay 也会自动识别压缩;
-d string 生成的文件都放在指定的目录中, 默认为用户 home 目录;
```

#### 重启 sshd

配置完成后, 需要重启 sshd 服务以便生效.

## 如何使用及查看会话日志

#### 如何解锁

以上述配置为例, 会话空闲超过 1 小时则被锁, 超过 2 小时才会被 kill, 这即说明在 kill 之前, 我们可以执行解锁会话的操作. 解锁会话需要单独再登录一个会话, 给被锁的会话发送 SIGUSR2 信号, 如下所示:
```
pkill -USR2 ttyrec  # 给所有匹配 ttyrec 信息的进程发送 USR2 信号, 未锁的会话不受影响.
```  

#### 日志文件

在设置完 ssh 的 ForceCommand 后, 用户登录的时候, 会在指定的目录中生成 ttyrec 结果的日志文件, 如果开启了 zstd 压缩, 会生成 zst 结果的文件. 如下所示:
```
$ ls -hl /export/tty_record
......
-rw-rw-r-- 1 arstercz arstercz  147 Jan 10 02:57 2022-01-10.02-57-19.705167.cz.ttyrec.zst
-rw-rw-r-- 1 arstercz arstercz 1.9K Jan 10 03:28 2022-01-10.02-58-29.293751.cz.ttyrec.zst
```

#### 查看日志会话记录

可以通过 ttyplay 工具, 以指定倍速(-s 选项)重新播放 ttyrec 文件. 在播放的过程中也可以通过 +/- 符号加速减速播放.

#### 如何导出日志

可以通过 ttyplay -n 的方式导出 ttyrec 文件的内容到指定文本文件:
```
ttyplay -n -Z 2022-01-10.02-57-19.705167.cz.ttyrec.zst > /tmp/cz.session.log
```

*备注*: ttyrec 文件中本身包含了时间信息, 文本高亮(如果 ssh 会话包含颜色显示), 导出的文件会包含一些特舒服和颜色字符. 不过通过 cat 等方式也可以正常显示. 一些命令的操作也可以通过 grep 进行处理. 另外也可以通过工具 [sys-rmcolor](https://github.com/arstercz/sys-toolkit#sys-rmcolor) 进行处理.

#### 统计日志

上述的配置中, 统一包含了时间, 用户名等信息, 在统计的时候, 也可以通过 ttytime 额外查看 ttyrec 文件包含了多长时间的内容:
```
$ ttytime 2022-01-10.02-23-52.068179.cz.ttyrec
    391	2022-01-10.02-23-52.068179.cz.ttyrec           # 共计 391 秒时长
```

#### 日志文件的大小

从原理来看, ttyrec 记录的文件大小和时间长短没有绝对的关系. 目前文件大小主要受以下因素制约:
```
1. 会话输出多, 比如用户执行了查看文件的操作, 或者脚本 debug 打印了很多日志;
2. 交互会话多, 比如长时间的 top, db, redis 等命令操作;
3. 执行了 rz/sz 等操作, 文件越大, 对应的日志就越大;
```

基于这些因素, ttyrec 建议开启 -Z 压缩减少对磁盘的占用.

#### ttyplay 中断播放

一些会话可能包含 `rz/sz` 的命令, 这些命令在通过 `ttyplay` 播放的时候会出现交互页面, 比如播放 rz 的时候, 如果你的终端(securecrt, iterm 等)支持 `Zmodem`, 则会弹出窗口让你选择文件列表. 这点像是 ttyplay 没有正确处理 Zmodem 协议. 如果终端禁止 Zmodem 协议, sz/rz 也会等待直到命令超时才会播放下一步骤.

目前没有好的方法, 可以通过 ttyplay 的 `-n` 选项, 先导出 ttyrec 文件的内存, 再通过 less 等命令查看. 也可以找找开源的 web 端播放工具, 可能解决了此类问题.

#### lshell 下如何使用

lshell 类似特定的 shell, 如果用户的 shell 环境被修改为 `lshell`, 在一开始登录的时候就会进入 lshell 会话, 再去执行 ttyrec 之类的命令, 但是 ttyrec 命令本身需要在当前 shell 中继续加载 shell 会话, 如下所示, ttyrec 需要继续调用 lshell, 
```
ut1:~$ ttyrec
/usr/bin/lshell: Permission denied

ttyrec: aborting!
```

从 lshell 的实现来看, 底层的很多关联(比如 exec, bash) 等都是严格限制, 工具或者脚本依赖的一些命令或调用都不一定可以通过, 所以只能从 `先执行 ttyrec 启动新会话, 再执行 lshell 限制会话` 的方式来解决, 如下所示, 用户还是 `bash shell`, 在 `sshd_config` 中执行以下命令:
```
ttyrec -t 3600 -k 7200 -Z -d /export/tty_record -- sh -c 'lshell'
```


## ttyrec 的缺点

通过 ssh 的 ForceCommand 方式可以让使用者无感的登录跳板机. 不过 ttyrec 本质上还是在 ssh 登录后又起了一个子进程, 所以以下操作不会成功:
```
1. 从其它机器 scp 文件到跳板机, 会出现 lost connection 的情况;
2. 从其他机器 rsync(以 ssh 方式) 文件到跳板机, 会出现 lost connection 的情况;
```

如果一定要传文件, 需要提前做好上传文件的通路, 比如在跳板机启动 rsync 服务, 或者提供统一的上传下载服务.

另外, ttyrec 目前仅适用于 Linux/Unix 系统, 如果需要连接 windows 等机器, 则无能为力, 只能借助其他工具, 比如 Apache 项目 [Guacamole](https://guacamole.apache.org/) 提供了通用的远程管理协议, 通过它可以统一管理基于 VNC, RDP(windows 系统等), 和 SSH 协议的会话. 如果需要统一所有系统的登录管理, 可以在 Guacamole 项目的基础上做更多的定制. 现成的项目可以参考 [next-terminal](https://github.com/dushixiang/next-terminal).

## 其他替换工具

另一个工具 [log-user-session](https://github.com/open-ch/log-user-session), 提供了和 `ttyrec` 类似的功能, 但不支持录屏, 仅以文本文件的方式存储会话内存, 等同 `ttyplay -n xxxx` 后的结果, 不过从易用性来看不如 ttyrec 方便, 而且不好和 lshell 结合, 但是该工具不会启动子会话, scp, rsync 等命令不受影响. 主要的几个配置选项说明如下:

```
LogFile = /export/user_session/%h-%u-%y%m%d-%H%M%S-%c-%p.log      # 格式见文档说明
LogRemoteCommandData = 1                                          # remote command 对应 SSH_ORIGINAL_COMMAND 环境变量, 比如 'ssh host1 uptime', uptime 即为 SSH_ORIGINAL_COMMAND 的值
LogNonInteractiveData = 1                                         # 是否记录非交互会话, 比如 'ssh host1 uptime' 即为非交互方式执行命令
NonInteractiveCommandWhitelist = rsync,ps,uptime                  # 非交互会话命令白名单, 在名单里的只记录命令, 不记录输出结果
```

上述三个容易混淆的选项, 可以从源代码中详细区分, 只有返回 1 才会记录命令的输出:
```c
 544 int should_log_data(int interactive, const char *original_command) {
 545     if (!interactive && !opt_log_non_interactive_data) return 0;
 546     if (!interactive && *whitelist_size && is_command_whitelisted(original_command)) return 0;
 547     if (original_command && !opt_log_remote_command_data) return 0;
 548     return 1;
 549 }
```

更多说明见: [log-user-session_doc](https://github.com/open-ch/log-user-session/blob/develop/doc/log-user-session.pod).

## 如何去除文本中的颜色和控制字符

参见工具 [sys-rmcolor](https://github.com/arstercz/sys-toolkit#sys-rmcolor).
