---
layout: post
title: "再探 audit 审计机制"
tags: [audit system]
comments: true
---

在文章[如何审计 Linux 系统的操作行为]({{ site.baseurl }}/how-to-audit-linux-system-operation/)中, 我们详细介绍了审计系统行为的几种方式, 以及对应的优缺点. 但是在 `audit` 方面介绍还不够深入, 缺乏实践使用的一些准则. 本文则对 `audit` 机制以及相关工具做更多的延申介绍, 主要包含以下几点:

* [auditd 工作机制](#auditd-工作机制)  
* [auditd 机制的延申](#auditd-机制的延申)  
    * [auditbeat 工作机制](#auditbeat-工作机制)  
    * [wazuh 工作机制](#wazuh-工作机制)  
    * [Elkeid 工作机制](#Elkeid-工作机制)  
* [其它工具](#其它工具)  
    * [packetbeat 工作机制](#packetbeat-工作机制)  
    * [filebeat 工作机制](#filebeat-工作机制)  
* [各工具对比](#各工具对比)  
* [容量预估](#容量预估)  
* [细看 auditbeat](#细看-auditbeat)  
    * [系统调用的进与出](#系统调用的进与出)  
    * [audit 事件](#audit-事件)  
    * [规则测试](#规则测试)  
    * [audit 事件忽略](#audit-事件忽略)  
* [总结](#总结)  

## auditd 工作机制

### 如何实现

> 备注: 部分内容参考[如何审计 Linux 系统的操作行为]({{ site.baseurl }}/how-to-audit-linux-system-operation/).

`auditd` 主要由内核和用户空间两部分组成. 内核空间主要由 `kauditd` 组件支持, 目前主要的 `Linux` 发行版都会内置支持. 以 `Linux` 的 `audit` 用户空间工具为例说明, 主要流程如下所示:

<img src="{{ site.baseurl }}/images/articles/202403/audit-invoke.png" width="530" height="400" alt="audit-invoke.png"/>

> 备注: 更多见 [audit 事件](https://github.com/torvalds/linux/blob/master/include/uapi/linux/audit.h), [字段字典](https://github.com/linux-audit/audit-documentation/blob/main/specs/fields/field-dictionary.csv), [Linux 系统调用](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl). 用户空间侧一般仅关注 1300 ~ 1399 的类型事件;

audit 整体上为分离的架构, auditctl 可以控制 kauditd 生成记录的策略, kauditd 生成的记录事件会发送到 auditd 守护程序, audisp 可以消费 auditd 的记录到其它地方. 其主要的几个组件包含如下:

| 组件 | 说明 |
| :- | :- |
| auditctl | 配置 kauditd 事件的规则, 可以及时生效, 用户空间通常使用 auditctl 调整规则; |
| auditd | audit 相关配置的加载, 日志落盘等都通过 auditd 守护程序实现, 同时也和  kauditd 交互; |
| audisp | 与 auditd 通信, 将收到的记录信息发送到其它地方, 比如 syslog 中; |
| augenrules <br> ausearch <br> autrace <br> aureport | audit 提供的辅助分析工具; |

### 过滤规则

同 `snoopy` 规则类似, 不希望审计可能包含的敏感信息命令时, 在使用的时候我们可以忽略一些条目:

```bash
### ignore common tools
-a never,exit -F arch=b64 -F exe=/usr/bin/redis-cli
-a never,exit -F arch=b64 -F exe=/usr/bin/mysql
-a never,exit -F arch=b64 -F exe=/usr/bin/mongo

### record system invoke
-a always,exit -F arch=b64 -S execve
-a always,exit -F arch=b32 -S execve
-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EACCES -F key=access
-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EPERM -F key=access
```

> 上述的 `-EACCES, -EPERM` 是仅在访问错误或权限错误的时候才记录.

系统默认的 auditd 输出信息相对晦涩, 需要二次解析处理:
```bash
type=SYSCALL msg=audit(1669631724.918:33310): arch=c000003e syscall=59 success=yes exit=0 a0=11abec0 a1=1288450 a2=12345f0 a3=7ffd90cca5a0 items=2 ppid=19123 pid=19399 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts2 ses=62194 comm="ip" exe="/usr/sbin/ip" key=(null)
type=EXECVE msg=audit(1669631724.918:33310): argc=2 a0="ip" a1="addr"
```

## auditd 机制的延申

由于 `auditd` 的功能足够丰富, 市面上出现了很多基于 `auditd` 机制的工具, 相比 `Linux` 的 `audit` 套件, 这些工具架构更简单:

<img src="{{ site.baseurl }}/images/articles/202403/audit-ext.png" width="530" height="400" alt="audit-ext.png"/>

这些工具等同实现了 `auditd` 和 `audisp` 两个组件的功能, 同时还增加了事件的解析功能, 补足了 `audit` 输出信息晦涩的不足. 另外 `output` 支持的也更多, 可以直接落盘或者发送到 `es`, `kafka` 等组件.

这些工具中, [auditbeat](https://www.elastic.co/cn/beats/auditbeat) 为 `elastic` 公司产品 `beats` 中的一员, 周边生态丰富; [hids](http://www.ossec.net/) 和 [wazuh](https://wazuh.com/) 属于同类产品, 更侧重于安全分析和事件响应, 相比较 `wazuh` 更为活跃; [go-audit](https://github.com/slackhq/go-audit) 出现较早, 功能比较集中, 但活跃度不高. 

下面则主要介绍 `auditbeat`, `wazuh` 和 `Elkeid` 这三类工具.

### auditbeat 工作机制

#### 功能说明

`auditbeat(比如 7.17 版本)` 对审计做了不少扩展, 有的功能 `audit` 虽然支持, 但是解析更耗资源, 相比定期检查等方式更轻量方便. 目前主要支持三大类的审计功能:

| 模块 | 功能 | 说明 |
| :- | :- | :- |
| auditd | 兼容 Linux Audit | 与 kauditd 交互, 消费收到的事件消息，比 audit 日志更易阅读; |
| File Integrity | 文件完整性检查 | 定期(10s)遍历指定目录下的文件(/bin, /user 等), 保存文件哈希到 boltdb 中; 对比上报哈希值不同的文件信息; |
| System | **dataset**: <br>    host <br>    login <br>    package <br>    process <br>    socket <br>    user | **分别用来获取**: <br>    主机信息(ip, kernel, mac 等); <br>    登录信息; <br>    yum/deb 安装信息; <br>    进程启停信息(同文件完整性, 定期(10s)检查); <br>    tcp/udp 网络信息(数据可能很多); <br>  用户创建删除信息; |

上述的功能中, 有 3 点需要注意:
```
1. 定期执行意味着短时间运行的进程或文件可能监控不到;

2. 开启 socket 监控, 可能产生很多日志, 尤其在短连接很多的场景中;

3. auditbeat 提供了内存队列, 磁盘限额存储事件等特性, 防止事件太多造成不可控的影响;
```

> 备注: 和内核可能产生 [kernel 死锁](https://github.com/elastic/beats/issues/26031).

`auditbeat` 对日志信息做了额外的解析, 比起 `audisp` 更方便阅读:

<img src="{{ site.baseurl }}/images/articles/202403/auditbeat-info.png" width="750" height="660" alt="auditbeat-info.png"/>

#### 过滤规则

可以参考 `snoopy` 规则, 做以下过滤:
```bash
processors:
  - add_host_metadata: ~
  - drop_event:
      when:
        or:
          - contains:
              process.title: "iptables -S"
          - contains:
              process.title: "telegraf --test"
          - contains:
              process.title: "redis-cli"
          - regexp:
              process.title: "mysql.*-p"
          - equals:
              user.name: "telegraf"
          - equals:
              process.executable: "/usr/sbin/crond"
          - equals:
              process.name: "consul-kv"
          - equals:
              process.name: "sadc"
```

### wazuh 工作机制

#### 功能说明

`wazuh` 工具整体上功能更全, 也更偏重于安全分析和事件响应, 架构方面主要包含 `agent` 和 `manager` 组件:

> 数据可以存储到官方指定的 opensearch(兼容 es), 其在此基础上实现了很多看板和数据分析. 不过也可以存储到 es, 但需要单独安装 kibana 插件;

<img src="{{ site.baseurl }}/images/articles/202403/wazuh-info.png" width="750" height="520" alt="wazuh-info.png"/>

在上面架构中, `agent` 直接和 `cluster` 通信, 将搜集的信息发给 cluster 节点, cluster 节点落盘到日志文件, 最后通过 filebeat 消费到 es 集群中.

以下为 agent 主要的一些主要功能， 很多功能受 `manager` 端开关控制:

| 功能 | 说明 |
| :- | :- |
| 支持平台 | 支持 linux, windows, mac, unix |
| 自动升级 | 有自动升级的机制; |
| 数据搜集 | linux - audit 机制, 自定义内核模块以及系统信息; <br> windows - [auditing 规则](https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/security-auditing-overview)和系统信息. `auditing` 功能不够多, 主要集中于数据的修改以及用户, 进程等; |
| 系统调用 | 监控指定的系统调用, 仅支持 linux - 可能产生很多数据; |
| 入侵检测 | 扫描主机发现可能的恶意软件, rootkit 和可疑行为, 同时检测隐藏的文件和进程; |
| 日志分析 | 会获取系统日志或程序日志并发送到 server 端存储以供分析; |
| 文件完整性检查 | 同 auditbeat, 定期检查保存哈希到 sqlite 中, 上报哈希变更的信息; 进程检查也类似; |
| 漏洞扫描 | 定期获取本机软件详单和 server 端的 CVE 数据库交互，进而得到漏洞信息; |
| 事件响应 | 可以对指定的事件作出[动作响应](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/how-it-works.html), 比如修改 iptables, 删除用户, 执行指定命令等; |
| 安全(云/容器) | 结合各云厂商的安全 api, 来分析云主机的安全情况; |

#### 过滤规则

`wauzh` 通过搜集 `audit.log` 日志进而分析系统命令的执行, 参考 [wazuh-audit](https://documentation.wazuh.com/current/user-manual/capabilities/system-calls-monitoring/audit-configuration.html), 不过 `wazuh` 主要以 `audit` 关键字进行区分, 如下所示:

```bash
# cat /var/ossec/etc/lists/audit-keys
audit-wazuh-w:write
audit-wazuh-r:read
audit-wazuh-a:attribute
audit-wazuh-x:execute
audit-wazuh-c:command
```

所以在创建 `audit` 过滤规则的时候需要通过 `-k` 选项添加对应的过滤标识, 如下所示:

```bash
### ignore common tools
-a never,exit -F arch=b64 -F exe=/usr/bin/redis-cli
-a never,exit -F arch=b64 -F exe=/usr/bin/mysql
-a never,exit -F arch=b64 -F exe=/usr/bin/mongo

-a always,exit -F arch=b64 -S execve -k audit-wazuh-x
-a always,exit -F arch=b32 -S execve -k audit-wazuh-x
-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EACCES -F key=access -k audit-wazuh-r
-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EPERM -F key=access -k audit-wazuh-r
```

> 备注: `auditbeat` 和 `wazuh` 在审计方面是互斥的,  `wazuh` 需要 `auditd` 服务,  消费日志 `audit.log`, `auditbeat` 则需要关闭 `auditd` 服务,  自己来接收消息.

### Elkeid 工作机制

[Elkeid](https://elkeid.bytedance.com) 是字节出的一款入侵检测系统, 功能有点类似 `wazuh`, 不过它的机制有很大的不同, 如下所示:

<img src="{{ site.baseurl }}/images/articles/202403/elkeid-invoke.png" width="750" height="600" alt="elkeid-invoke.png"/>

目前主要开源了 `agent`, `driver` 和 `RASP` 几个组件, 通过源码编译时也出现了一些异常，比如缺少一些依赖说明, `rasp` 组件依赖太多等问题. 不过从这几个组件也能看出 `Elkeid` 的工作机制有很大的不同.

| 组件 | 功能说明 |
| :- | :- |
| agent | 插件及自定义插件管理; <br> 系统信息, 日志数据的搜集; <br> 和 server 端通信, 进行服务发现; |
| driver | **主要用于搜集 kernel 数据, 包括**: <br>    hids_driver.lo 内核模块; <br>    跟踪 io, bind, execve 系统调用, 通过 ptrace 实现; <br>    rootkit 检测; |
| rasp | **主要为进程运行时分析, 包括**: <br>    jvm - 通过 ASM 修改类的字节码, 跟踪堆栈和参数调用; <br>    golang - 从 gopclntab 块中解析符号表, 再加入 hook api, 进而跟踪堆栈和参数调用; <br>    php - 增加 hook 函数和 opcodes, 跟踪堆栈和参数调用; |

`driver` 组件中, 主要通过 `ptrace` 和内核模块实现了内核空间的数据搜集, 这种方式对发行版的侵入很大, 通用性不够, 内核模块和内核版本也强绑定, 见 [ko_list](https://github.com/bytedance/Elkeid/blob/main/driver/ko_list.md), 所以这种方式不适合我们线上使用.

## 其它工具

### packetbeat 工作机制

#### 功能说明

[packetbeat](https://www.elastic.co/guide/en/beats/packetbeat/7.17/packetbeat-overview.html) 同样是 beats 的组件之一, 主要通过 pcap 抓包机制实时分析网络包, 不过比起 auditbeat 的 socket 功能, packetbeat 的功能更丰富, 解析报文支持的协议也更多, 包括:

```
ICMP, DHCP, DNS, HTTP
AMQP, Cassandra, MySQL, PostgreSQL, Redis, MongoDB, Memcached
NFS, TLS, Thrift
```

> 备注: 同 `auditbeat`, `packetbeat` 也提供了内存队列, 磁盘限额存储事件等特性, 防止事件太多造成不可控的影响.

#### 过滤规则

过滤规则同样可以使用 drop_event 语法, 如下所示:

```
processors:
  - add_host_metadata: ~
  - drop_event:
      when:
        or:
          - network:
              source.ip: private
          - network:
              destination.ip: '192.168.1.0/24'
```

### filebeat 工作机制

#### 功能说明

[filebeat](https://www.elastic.co/guide/en/beats/filebeat/7.17/filebeat-overview.html) 同样是 beats 的组件之一, 主要用来搜集文件内容. 目前通过模块化的方式支持并解析了所有常见的系统和软件日志, 包含:

```
syslog, audit, secure, haproxy, iis, tomcat, nginx, kafka, zeek
mysql, postgresql, mssql, oracle, mongodb, redis, elasticsearch ...
```

开启模块并设置字段建立索引模板后, 各模块的 `mapping` 映射信息会自动同步到 es.

#### 过滤规则

由于 filebeat 的目的很单一, 主要为搜集日志, 如果仅考虑系统运维层面, 可以考虑使用以下配置:
```
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/telegraf/telegraf*.log
  fields:
    logmon: telegraf

- type: log
  enable: true
  paths:
    - /var/log/filebeat/filebeat*
  fields:
    logmon: filebeat

- type: log
  enable: true
  paths:
    - /data/scripts/logs/*.log
  fields:
    logmon: scripts

filebeat.config.modules:
  reload.enabled: true
  reload.period: 15s
  path: /etc/filebeat/modules.d/*.yml
```

并开启以下模块:
```
mysql, redis, system
```

## 各工具对比

上述工具各有优缺点, 不过应用到线上需要慎重考虑. 对各工具的优劣对比如下:

| 特点 | snoopy | auditbeat | wazuh | packetbeat | filebeat | Elkeid |
| :- | :- | :- | :- | :- | :- | :- |
| 应用领域 | 命令审计 | 命令审计 | 安全分析 | 网络分析 | 日志收集 | 安全分析 |
| 是否全平台 | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 部署简单 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 方便升级维护 | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 是否活跃 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 影响应用成都 | 中高 | 轻微 | 轻微 | 中高 | 轻微 | 中高 |
| 影响内核程度(可能死锁, 崩溃等) | 轻微 | 中等 | 中等 | 轻微 | 轻微 | 中高 |
| 过滤规则 | 事后 | 事后 | 事后 | 事后 | ❓ | 事前事后 |
| 是否适合线上 | ✅ | ✅ | ❗| ❌ | ✅ | ❌ |

> 过滤规则中, 事后表示无论设置什么规则, 都是先由工具接收所有事件后再应用规则. 这意味着如果系统调用的事件很多, 无论是否应用规则, 内核 kauditd 的压力都可能增大.

是否适合线上, `wazuh` 为感叹号, 因为他的审计依赖 `audit` 套件, 并消费 `audit.log` 日志. 另外不少事件响应功能也不是线上所需要的.

## 容量预估

以测试环境的一台 `centos 7` 主机为例说明, 该主机相对空闲, 仅运行两台 `MySQL` 和 `telegraf` 监控程序, 单日的数据量大致如下:

### auditbeat 测试

| 编号 | 功能 | 数据量 |
| :- | :- |:- |
| 1 | 开启 execve, 开启 file_integrity, login, process, user, socket | 2.5 GB |
| 2 | 开启 execve, 开启 file_integrity, login, process, user | 200 MB |
| 3 | 同 2, 开启过滤规则 | 40 MB |

### filebeat 测试

| 编号 | 功能 | 数据量 |
| :- | :- | :- |
| 1 | 仅监控运维层面的日志信息 | 8 MB |


### wauzh 测试

| 编号 | 功能 | 数据量 |
| :- | :- | :- |
| 1 | 默认配置, 不设置 audit 规则 | 25 MB |
| 2 | 设置 auditctl 规则 | 接近 auditbeat 的规则 2, 3 |

### packetbeat 测试

未做测试, 主要受配置和系统上运行服务的影响. 网络请求越多, 单日数据量越大.  但上限受内存队列和磁盘限额的调整.

**总结**: 从上述的数据量来看, `auditbeat` 的规则 2, 3, `filebeat` 和 `wauzh` 的数据量相对合适, 比如 1 千台主机产生的数据量(单日 40G ~ 200G 左右).

## 细看 auditbeat

根据上述的对比, `auditebat` 更适合实际的使用情况, 如果需要应用到线上, 我们需要对 `auditbeat` 有更多的了解.

### 系统调用的进与出

对每个 `Linux` 的[系统调用](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl)而言, 比如以简单的 `open` 调用, 对应到内核中为 `sys_open` 函数:

```c
asmlinkage long sys_open(const char __user *filename,
                int flags, umode_t mode);
```

如果需要跟踪 `open` 调用, 可以在 `sys_open` 函数执行前后两个点来获取上下文信息, 不过为了尽量避免影响函数的执行, 通常都会选择执行完后, 即在 `sys_open` 函数 `exit` 的时候开始记录信息. 

对应到 `auditctl` 规则, 可以表示如下:

```
-a never,exit   # 系统调用 exit 的时候永不记录
-a always,exit  # 总在系统调用 exit 的时候记录
```

### audit 事件

由于可以跟踪很多系统调用, 这些系统函数及其参数信息就可以组成很多可以审计的事件(用户空间 `1300 ~ 1399`), 比如常见的下面事件:

```c
AUDIT_PATH
AUDIT_CWD
AUDIT_EXECVE
AUDIT_PROCTITLE
```

事件配合进程和线程的上下文信息即可获取到我们需要的审计信息.

### 规则测试

#### auditbeat 规则

```
# 仅测试环境
-a always,exit -F arch=b64 -S open -S sendfile -S truncate -S ftruncate -S chdir -S fchdir -S rename -S mkdir -S rmdir -S creat -S unlink -S readlink -S openat -S mkdirat -S unlinkat -S renameat -S readlinkat -F key=note

-a always,exit -F arch=b64 -S mount,umount2 -F auid!=-1 -F key=mount
-a always,exit -F arch=b32 -S mount,umount,umount2 -F auid!=-1 -F key=mount

-w /etc/sysconfig/iptables -p wa -k iptables

-w /etc/sysctl.conf -p wa -k sysctl
-w /etc/sysctl.d -p wa -k sysctl

-w /sbin/auditctl -p x -k audittools
-w /sbin/auditd -p x -k audittools
-w /usr/sbin/auditd -p x -k audittools
-w /usr/sbin/augenrules -p x -k audittools

-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p rwxa -k identity
-w /etc/shadow -p rwxa -k identity

-w /etc/sudoers -p wa -k actions
-w /etc/sudoers.d -p wa -k actions
-w /usr/bin/passwd -p x -k passwd_modification
-w /usr/sbin/groupadd -p x -k group_modification
-w /usr/sbin/groupmod -p x -k group_modification
-w /usr/sbin/addgroup -p x -k group_modification
-w /usr/sbin/useradd -p x -k user_modification
-w /usr/sbin/userdel -p x -k user_modification
-w /usr/sbin/usermod -p x -k user_modification
-w /usr/sbin/adduser -p x -k user_modification
-w /etc/ssh/sshd_config -p rwxa -k sshd
-w /etc/ssh/sshd_config.d -p rwxa -k sshd

# 常见命令打标签, 方便监控
-w /usr/sbin/iptables -p x -k note_cmd
-w /usr/bin/zip -p x -k note_cmd
-w /usr/bin/gzip -p x -k note_cmd
-w /usr/bin/bzip2 -p x -k note_cmd
-w /usr/bin/lz4 -p x -k note_cmd
-w /usr/bin/zstd -p x -k note_cmd
-w /usr/bin/tar -p x -k note_cmd
-w /usr/bin/cp -p x -k note_cmd
-w /usr/bin/mv -p x -k note_cmd
-w /usr/bin/wget -p x -k note_cmd
-w /usr/bin/curl -p x -k note_cmd
-w /usr/bin/scp -p x -k note_cmd
-w /usr/bin/rsync -p x -k note_cmd
-w /usr/bin/ftp -p x -k note_cmd
-w /usr/bin/sftp -p x -k note_cmd
-w /usr/bin/hexdump -p x -k note_cmd
-w /usr/bin/xxd -p x -k note_cmd
-w /usr/bin/ln -p x -k note_cmd

-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EACCES -F key=access
-a always,exit -F arch=b64 -S truncate,ftruncate,creat -F exit=-EPERM -F key=access

-a always,exit -F arch=b64 -S bind -S execve -S connect
-a always,exit -F arch=b32 -S bind -S execve -S connect
```

> connect 仅测试环境.

#### 文件完整性规则

```
- module: file_integrity
  paths:
  - /bin
  - /usr/bin
  - /sbin
  - /usr/sbin
  - /etc

  max_file_size: 3000 MiB
```

#### 系统规则

```
- module: system
  datasets:
    - login
    - process
    - user

  state.period: 8h
  process.hash.max_file_size: 1000 MiB

  user.detect_password_changes: true
  login.wtmp_file_pattern: /var/log/wtmp*
  login.btmp_file_pattern: /var/log/btmp*
```

#### 标签及自定义规则

```
tags: ["xxxxx"]         # 标识信息

fields:
  logmon: auditbeat     # 自定义字段, 方便 logstash 等工具判断处理

```

### audit 事件忽略

为避免产生过多的日志, 整体上按以下规则忽略事件:

```
没有 uid 的行为;
忽略 telegraf/zabbix 等监控行为相关的事件;
忽略 crond 相关的事件;
忽略 mysql, redis-cli 等相关的正常事件;
```

对应 `auditbeat` 的规则语法如下示例:
```
  - drop_event:
      when:
        or:
          - equals: # old-uid is not set(-1)
              auditd.summary.actor.primary: "unset"
          - contains:
              process.title: "iptables -S"
          - contains:
              process.args: "-tnlp"
          - equals:
              process.name: "redis-cli"
          - equals:
              process.executable: "mysql"
          - equals:
              process.executable: "mongo"
          - equals:
              user.saved.name: "telegraf"
          - equals:
              user.name: "telegraf"
```


### 报警策略

规则报警可以集中在 `audit key` 信息, 对应 `auditbeat` 规则的 `-k` 属性. 

## 总结

在上述的介绍中, 可以看到不通工具都有很强的功能定位行, 而且越偏底层, 带给内核的风险就越大, 所以具体实践中很难将这些功能都集成到一个工具中, 但是借助这些工具又能加强我们的基础能力. 所以如果从功能和风险因素角度来看:

| 功能 | 风险 |
| :- | :- |
| 记录执行的命令; <br> 系统文件完整性检查; <br> 进程启停检查; <br> 系统和脚本日志搜集; <br> 所有信息结合 CMDB,可搜索, 可视化, 可告警; | 是否对内核, 应用产生影响; <br> 是否加重系统压力; <br> 出现问题是否方便部署升级;  <br> 是否会产生安全问题; <是否产生日志过多, 加重存储负担>; |

部署多个组件可以将风险都分担开, 不至于一个组件出问题对系统产生很大的影响. 可以参考下图:

```
+-----------------+
|     Host A      |
|  +-----------+  |
|  | telegraf  |  |           +--------------------+                              +-----------------+
|  +-----------+  |           |   victoriaMetrics  |----------------------------> |  metric monitor |
|  | filebeat  |--+------->   +--------------------+        +---------------+     +-----------------+
|  +-----------+  |           |  logstash / kafak  |------> | elasticsearch |---> |  audit  monitor |
|  | auditbeat |  |           +--------------------+        +---------------+     |  log    monitor |
|  +-----------+  |                                                               +-----------------+
|                 |
+-----------------+

```

> 事实上 `telegraf` 也支持 `elasticsearch`, 只不过对监控的指标数据而言, `victoriametrics` 的压缩比更高, 且 alert 组件的功能也更完善. logstash 和 kafka 可以视具体情况而定. 如果需要加工信息, 比如去除一些多余字段, 增加一些 CMDB, 使用人等字段可以考虑使用 kafka, 由消费程序统一处理.

由 `telegraf + filebeat + auditbeat` 组合来覆盖系统层所有的监控, 可以很好的满足我们在审计方面的需求. 如果是采用云产品或其它商业产品, 相信在功能方面也是相对分层的, 毕竟几个组件功能都很庞大, 与底层的交互也较深, 也更有利于生产环境的操作维护.

