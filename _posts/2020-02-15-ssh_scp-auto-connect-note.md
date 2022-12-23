---
layout: post
title: "ssh/scp/rsync 使用技巧"
tags: [ssh, rsync, autologin]
comments: true
---

我们经常通过 `ssh/scp` 免密登录的方式来自动化的批量执行一些操作, 不过在实际的使用中可能经常碰到一些中断自动连接的问题. 下面则主要介绍如何避免这些问题并提供一些使用建议.

* [引起中断的问题](#引起中断的问题)
    * [Host key 添加提示](#Host-key-添加提示)
    * [指纹信息变更](#指纹信息变更)
    * [连接超时](#连接超时)
* [公钥不匹配引起登录失败](#公钥不匹配引起登录失败)
* [隐藏进程说明](#隐藏进程说明)
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
```bash
$ ssh newhost
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
......
......
Host key verification failed.
```

该问题同样可以通过 `StrictHostKeyChecking=no` 选项解决:

```bash
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

### 公钥不匹配引起登录失败

如果当前用户目录 `~/.ssh` 下的私钥 `id_rsa` 和 `id_rsa.pub` 不匹配, 则会出现登录失败的情况. 如下所示, 我们分三种情况来测试, 以下三种情况都假定公钥信息存在于远端机器的 `~/.ssh/autheorized_keys` 文件中:

#### 没有公钥 id_rsa.pub

在 `~/.ssh` 目录没有 `id_rsa.pub` 的情况下, ssh 会直接尝试使用私钥 `id_rsa` 连接机器, 这种情况下会正常登录:
```
debug1: Next authentication method: publickey
debug1: Trying private key: /root/.ssh/identity
debug1: Trying private key: /root/.ssh/id_rsa
debug1: read PEM private key done: type RSA
debug1: Authentication succeeded (publickey).
```

#### 有公钥 id_rsa.pub

`~/.ssh` 目录下有 `id_rsa.pub` 的情况下, ssh 会校验公钥 `id_rsa.pub`, 如下所示, 注意这里的 `Offering public key` 不同于上述的 `Trying private key`:
```
debug1: Next authentication method: publickey
debug1: Trying private key: /root/.ssh/identity
debug1: Offering public key: /root/.ssh/id_rsa
debug1: Server accepts key: pkalg ssh-rsa blen 277
```

#### 有公钥 id_rsa.pub 但不匹配

在修改 `id_rsa.pub` 的内容后, ssh 校验失败, 出现登录失败的情况:
```
debug1: Next authentication method: publickey
debug1: Trying private key: /root/.ssh/identity
debug1: Offering public key: /root/.ssh/id_rsa
debug1: Authentications that can continue: publickey,gssapi-keyex,gssapi-with-mic,password
debug1: Trying private key: /root/.ssh/id_dsa
debug1: Next authentication method: password
```

从 sshd 源码 `sshconnect2.c` 来看, 有 `id_rsa.pub` 公钥的时候会进行 pubkey 检测, 不匹配就退出, 没有公钥文件则直接尝试私钥 `id_rsa` 连接. 如下所示:
```c
1355 int
1356 userauth_pubkey(Authctxt *authctxt)
1357 {
1358     Identity *id;
1359     int sent = 0;
1360 
1361     while ((id = TAILQ_FIRST(&authctxt->keys))) {
1362         if (id->tried++)
1363             return (0);
1364         /* move key to the end of the queue */
1365         TAILQ_REMOVE(&authctxt->keys, id, next);
1366         TAILQ_INSERT_TAIL(&authctxt->keys, id, next);
1367         /*
1368          * send a test message if we have the public key. for
1369          * encrypted keys we cannot do this and have to load the
1370          * private key instead
1371          */
1372         if (id->key && id->key->type != KEY_RSA1) {
1373             debug("Offering public key: %s", id->filename);
1374             sent = send_pubkey_test(authctxt, id);
1375         } else if (id->key == NULL) {
1376             debug("Trying private key: %s", id->filename);
1377             id->key = load_identity_file(id->filename);
1378             if (id->key != NULL) {
1379                 id->isprivate = 1;
1380                 sent = sign_and_send_pubkey(authctxt, id);
1381                 key_free(id->key);
1382                 id->key = NULL;
1383             }
1384         }
1385         if (sent)
1386             return (sent);
1387     }
1388     return (0);
1389 }
```

所以在公钥不匹配的时候, 就会出现登录的问题, 可以简单的将 `id_rsa.pub` 换个文件名来跳过校验 pubkey, 以便正常登录.

### 隐藏进程说明

在日常使用 `scp/rsync/sftp` 的时候, 对端的机器一般都会产生一些隐含的进程, 具体如下:

#### scp 文件

如果在 A 主机执行 `scp file B:/tmp`, 那么 B 主机会产生下面的进程:
```
scp -t ...
```

如果在 A 主机执行 `scp B:/tmp/file /tmp`, 那么 B 主机会产生下面的进程:
```
scp -f ...
```

> 备注: `-t 和 -f` 选项不在手册选项中体现, 仅在源码中显现, 如下所示:
```c
// https://github.com/openssh/openssh-portable/blob/master/scp.c#L569
		case 'f':	/* "from" */
			iamremote = 1;
			fflag = 1;
			break;
		case 't':	/* "to" */
			iamremote = 1;
			tflag = 1;
```

#### sftp 传输文件

如果在 A 主机执行 `sftp B` 来传输文件, 那么 B 主机会产生下面的进程:
```
/usr/libexec/openssh/sftp-server
```

> 备注: 该进程受 B 主机 `/etc/ssh/sshd.conf` 配置 `Subsystem       sftp    /usr/libexec/openssh/sftp-server` 决定.

#### rsync 传输文件

如果在 A 主机执行 `rsync -av /tmp/file B:/tmp/` 或 `rsync -av B:/tmp/file /tmp/`, B 主机会产生下面的进程:
```
rsync --server ...
```

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
