---
id: 1124
title: 使用 mmm-manager 管理云环境中的 MySQL 双主实例
date: 2019-01-28T13:59:38+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1124
permalink: '/%e4%bd%bf%e7%94%a8-mmm-manager-%e7%ae%a1%e7%90%86%e4%ba%91%e7%8e%af%e5%a2%83%e4%b8%ad%e7%9a%84-mysql-%e5%8f%8c%e4%b8%bb%e5%ae%9e%e4%be%8b/'
categories:
  - database
tags:
  - mmm
  - MySQL
comments: true
---
### 介绍说明

在之前的工具中, [mha_switch](https://github.com/arstercz/mha_switch) 和 [mha_manager_consul](https://github.com/arstercz/mha_manager_consul) 的使用都是建立在虚 ip 漂移的基础上实现的高可用方案. 不过在云环境中, 目前很多的云厂商还不支持虚 ip 漂移的功能, SLB(负载均衡)等没有类似 haproxy 的 backup 模式, 所以不适用于单 master 读写的场景. 如果使用 SLB 代理多 master, 则很难保证数据一致性问题(比如主从延迟). 一些组织在使用云环境的时候可能首要考虑数据安全性, 这种情况下可能不会考虑 RDS 之类的服务, 而是在云主机中自建 MySQL 实例, 并且最好占用整个宿主机. 如果自建实例, 就一定需要考虑高可用方案, 在不支持虚 ip 漂移的情况下, dns 服务或者绑 hosts 文件是个可选的方案, 在故障切换的时候做好对应的记录修改即可, 不过这种方式需要业务做对应调整, 在业务复杂的场景下, 需要保证修改记录的准确性和及时性. 

[mmm-manager](https://github.com/arstercz/mmm-manager) 则提供了另一种方案用来管理双主满足高可用的需求. 不过该方案依赖一些编程语言驱动的特性支持. 对于不支持特性的编程语言, mmm-manager 提供了更新 redis key 值, 以满足在执行切换操作后大家可以使用 [confd](https://github.com/kelseyhightower/confd) 等工具进行相关的触发操作, 比如更新 dns, hosts 记录等.

### 如何工作

如下图所示:
```
                                                     3
                                                +-----------+
         +------------------------------------> | mmm-agent |
         |                                      +----^------+
         |                                           |
         V                                           |
 +----------------+                                  |
 |  +----------+  |                                  |
 |  | master A |  |               1               +-------+                2
 |  +----------+  |        +-------------+        |       |         +--------------+
 |                | -----> | mmm-monitor | -----> | Redis | <-----> | mmm-identify |
 |  +----------+  |        +-------------+        |       |         +--------------+
 |  | master B |  |                               +-------+
 |  +----------+  |
 +----------------+
```

mmm-manager 的工作依赖于 Redis 的运行, 具体则包含以下三步:

* mmm-monitor 收集 master 的状态信息并存到 Redis 中;

* mmm-identify 读取 Redis 中的状态信息, 并判断当前哪个 master 为主 master, 哪个为备 master, 并将其更新到 Redis 中;

* mmm-agent 从 Redis 获取主备模式的信息, 依据这些信息设置对应的 master, 这些设置包括:
```
   在主 master 中关闭 read_only, 备 master 中关闭开启 read_only;
   在主 master 中恢复 MySQL user 密码, 备 master 中反转 MySQL user 密码;
   进行上面用户密码操作的时候, 关闭本地的 sql_log_bin 参数;
   在主 master 中, 如果 slave 的 IO 和 SQL 两个线程都为 No, 则进行 start slave 操作;
```

### 应用连接配置

上面提到 mmm-manager 依赖编程语言的驱动特性, 主要原因是建议应用程序使用 failover 模式连接 MySQL, 比如 Java 语言的 jdbc-5.x 驱动提供的 [failover 模式](https://dev.mysql.com/doc/connector-j/5.1/en/connector-j-config-failover.html), 如下连接示例:

```
jdbc.user.url=jdbc:mysql://10.0.21.5:3308,10.0.21.7:3308/db_test?failOverReadOnly=false
&secondsBeforeRetryMaster=60&initialTimeout=1;maxReconnects=2;autoReconnect=true
```

mmm-manager 的切换遵循 jdbc 的规则:
```
1. 连接第一个 ip;
2. 如果第一个 ip 有问题, 就连接第二个 ip;
3. jdbc 定期检查第一个 ip;
4. 如果第一个 ip 正常, 则连接回第一个 ip;
```

**备注**: 建议在各实例的 my.cnf 配置中开启 read_only 参数, 这样在实例异常崩溃并恢复启动后, 当前 master 的 slave 状态可能出现 1236 等异常状态, 这个时候如果 jdbc 连接回该实例, 可能很容易出现数据不一致的问题(比如另一个 master 的更新, 在当前 master 读取不到). 将 read_only 写到配置中及避免这个问题的发生, 因为 jdbc 也会依据实例是否 read_only 而判断是否可用.

如果应用程序的 MySQL 驱动不支持 failover 特性, 可以考虑使用 confd + redis 的方式触发主 master 更改时的操作. 比如更新 hosts 记录, 更新 haproxy 配置等操作.

### 配置说明

配置示例可以参考 [configure](https://github.com/arstercz/mmm-manager#how-to-set-configure-file), 在配置的时候需要注意以下几点:
```
1. mmm-monitor 和 mmm-identify 同时使用 mmm.conf 配置, mmm-agent 使用 mmm-agent.conf 配置;

2. mmm.conf 中每个实例对应命名工具中的 tag 选项, 每个实例都有唯一的 uniqsign 标识;

3. mmm-agent.conf 中, 只有一个 [mysql] 配置, 这种方式的初衷是为了方便工具读取配置, 因为切换操作都是统一的, 只是收到的消息不同, 该设置要求所有的实例的用户密码都一样;
```

### 其它问题

#### 反转密码

该功能为可选项, 如果配置了 block_user 和 block_host, 则进行密码反转功能, 该功能用于限制备 master 写入数据. 该功能在 MySQL 5.7 中还不能使用.

#### confd 支持

可用 confd 读取 Redis 的 key `mysql-$uniqsign-master`, $uniqsign 为 mmm.conf 中的实例唯一标识. confd 感知到 key 值变化后即可进行相应的触发操作, 详见 [confd resource config](https://github.com/kelseyhightower/confd/blob/master/docs/quick-start-guide.md#create-a-template-resource-config)

#### 不支持 active-active 模式

现在的 mmm-manager 仅支持 `active-passive` 模式, 这意味着应用程序仅连接 active master 进行读写服务. 实际上在 `active-active` 模式下很难保证数据的一致性. 如果需要读取 passive master, 可以使用其他普通用户连接, 并将该用户添加到配置文件的 exclude_user 选项中. mmm-manager 在识别主 master 的时候会忽略该用户创建的连接.
