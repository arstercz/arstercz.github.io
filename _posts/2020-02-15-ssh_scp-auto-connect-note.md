---
layout: post
title: "ssh/scp 自动连接使用技巧"
tags: [ssh, autologin]
comments: false
---

我们经常通过 `ssh/scp` 免密登录的方式来自动化的批量执行一些操作, 不过在实际的使用中可能经常碰到下面几种中断自动连接的问题.

* [自动连接的问题](#自动连接的问题)
    * [Host key 添加提示](#Host-key-添加提示)
    * [指纹信息变更](#指纹信息变更)
    * [连接超时](#连接超时)
* [使用建议](#使用建议)

### 引起中断的问题

目前主要由以下几方面问题会引起连接中断:

#### Host key 添加提示

在连接新的机器的时候, 通常需要将新机器的加密指纹信息添加到自身的 `~/.ssh/known_hosts` 中. 如下所示, 这种提示需要我们手动确认, 会暂停自动登录操作, 即便新机器保存着连接机的公钥信息.

```bash
$ ssh newhost
The authenticity of host 'newhost (10.0.1.2)' can't be established.
ECDSA key fingerprint is SHA256:+PmcUMRVQIccL3N7WEkjRuZ5B5iyyVJDV2MGekPXCoo.
ECDSA key fingerprint is MD5:5a:eb:33:c8:ae:be:b0:d7:f0:ec:e3:a2:d8:92:2e:77.
Are you sure you want to continue connecting (yes/no)? 
```

可以通过 `expect` 等工具处理此提示, 也可以通过设置 `ssh/scp` 选项跳过确认过程而直接登录新机器, 如下所示:
```
$ ssh -o StrictHostKeyChecking=no newhost
Warning: Permanently added '10.0.1.2' (RSA) to the list of known hosts.
Last login: Fri Feb 14 03:53:33 2020 from 10.0.1.10
[cztest@cz ~]$ 
```
`StrictHostKeyChecking=no` 选项会忽略确认过程, 自动将指纹信息加到 `~/.ssh/known_hosts` 中.

#### 指纹信息变更

这种问题通常在重新初始化远程机器的时候, 比如重装机器, ssh 的指纹信息变更, 如下所示:
```
$ ssh newhost
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
......
......
Host key verification failed.
```
该问题同样可以通过 `StrictHostKeyChecking=no` 选项解决:
```
$ ssh -o StrictHostKeyChecking=no newhost
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
......
......
Last login: Sat Feb 15 09:26:58 2020 from 10.0.1.10
[cztest@cz ~]$ 
```

#### 连接超时

在执行一些比较重的操作的时候, 可能会出现连接超时断开的情况, 这种问题一方面可能是因为操作确实费时, 操作等待的时间过长, 也有可能是因为一些代理中间件(比如 haproxy) 的连接超时设置而引起中断. 这些本质上都是因为 tcp 连接长时间没有通信引起的, 可以通过以下选项对连接进行保活:

```
ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=20 server
```
上面的选项每 60s 发送一次保活信息, 最多发送 20 次. 实际使用中可以按需调整这两个参数.

另外, 有的机器设置了一些超时参数避免长时间不操作而占用连接的情况, 如下所示:
```bash
TMOUT=600
readonly TMOUT
```
`TMOUT` 可以用来控制连接的输入行为, 在交互式中很有用. 上面将 `TMOUT` 设置为只读变量, 所有连接到此机器的连接在 10 分钟内没有 `read(bash buildin, 比如没有输入命令)` 操作则断掉连接. 这种情况无法通过 `ssh` 的选项来避免, 可以通过一些 ssh 的工具避免此类问题, 比如 `SecureCRT` 工具的 `session options -> Terminal -> Anti-idle` 功能指定每隔一定时间对连接的会话发送一些特殊字符来避免 `TMOUT` 引起的中断. 

### 使用建议

实际的使用中可以通过对 `ssh/scp` 增加以下选项尽量避免自动登录失败:
```
-o ServerAliveInterval=60 -o ServerAliveCountMax=20 
-o StrictHostKeyChecking=no -o PasswordAuthentication=no
-o BatchMode=yes -o ConnectTimeout=8
```

在启用 `BatchMode` 的时候, `ssh/scp` 会忽略输入密码的提示, 这点在批量操作的时候很有用. 另外也可以将上面的选项增加到 `~/.ssh/config` 配置中, 如下所示:
```
Host *
    GSSAPIAuthentication no
    ControlMaster auto
    ControlPath ~/.ssh/master-%r@%h:%p
    ForwardAgent yes
    TCPKeepAlive yes
    ServerAliveInterval 60
    ServerAliveCountMax 20
    StrictHostKeyChecking no
    PasswordAuthentication no
    BatchMode yes
    ConnectTimeout 8
```
`ControlMaster` 和 `ControlPath` 两个选项控制 socket 的文件路径信息方便 agent 方式复用 socket 文件登录机器, 更多可以参考 [ssh-agent](https://github.com/msimerson/ssh-agent).
