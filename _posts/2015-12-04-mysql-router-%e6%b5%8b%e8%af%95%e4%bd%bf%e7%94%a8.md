---
id: 613
title: MySQL Router 测试使用
date: 2015-12-04T20:04:30+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=613
permalink: '/mysql-router-%e6%b5%8b%e8%af%95%e4%bd%bf%e7%94%a8/'
ultimate_sidebarlayout:
  - default
categories:
  - database
  - performance
tags:
  - MySQL
  - Router
---
MySQL Router 测试使用

<strong>1. 特性</strong>

MySQL Router 并没有包括一些特别新的特性, 总体上看中规中矩, 不过 first-available 和插件两个特性挺有意思, 后续会进行讲解, 特性包括:
```
对连接请求进行路由;
和 Fabric 配套使用, 方便管理;
插件特性, 需要的功能以插件形式提供;
``` 
<more></more>

<strong>2. 配置</strong>

MySQL Router 在启动的时候会读取默认的配置文件, 用户可以通过  -DROUTER_CONFIGDIR=<path> 或编辑 cmake/settings.cmake 来自定义配置文件, 默认情况下从以下路径读取:
```
[root@cz-centos7 bin]# ./mysqlrouter --help
Copyright (c) 2015, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Start MySQL Router.

Configuration read from the following files in the given order (enclosed
in parentheses means not available for reading):
  (./mysqlrouter.ini)
  (/root/.mysqlrouter.ini)

Usage: mysqlrouter [-v|--version] [-h|--help]
                   [-c|--config=<path>]
                   [-a|--extra-config=<path>]
Options:
  -v, --version
        Display version information and exit.
  -h, --help
        Display this help and exit.
  -c <path>, --config <path>
        Only read configuration from given file.
  -a <path>, --extra-config <path>
        Read this file after configuration files are read from either
        default locations or from files specified by the --config
        option.
```

值得一提的是 -c 选项指定的配置会被最先加载, -a 指定的配置后续加载.

<strong>2.1 配置文件设置</strong>

<strong>2.1.1 通用选项</strong>

通用选项可以放到 [DEFAULT] 块中, 通常包括一些目录路径配置:
```
logging_folder: MySQL Router 运行时产生 log 的目录路径, log 文件默认为 mysqlrouter.log, 不设置路径默认输出到标准输出(STDOUT);
plugin_folder: MySQL Router 的插件路径, 该路径必须和 MySQL Router 的安装目录对应上, 如果是自定义的安装路径, 该选项必须要指定, 默认为 /usr/local/lib/mysqlrouter;
runtime_folder: MySQL Router 运行时候的目录路径, 默认为 /usr/local ;
config_folder: MySQL Router 配置文件的路径, 默认为 /usr/loca/etc/mysqlrouter
```

举例如下:
```
[DEFAULT]
logging_folder = /var/log/mysqlrouter
plugin_folder = /usr/local/mysqlrouter/lib
runtime_folder = /usr/local/mysqlrouter
```

<strong>2.1.2 路由选项</strong>

以下选项可以放到路由策略 [routing:<section_key>] 块中:
```
bind_address: 工具启动的时候绑定的网卡地址, 默认为 127.0.0.1, 如果没有指定端口, bind_port 选项则必须指定;
bind_port: 工具启动监听的端口, 如果 bind_address 以 ip:port 形式指定, 则 bind_port 不需要再指定;
connect_timeout: 工具连接后端 MySQL Server 的超时时间, 默认为 1s, 有效的值为 1 ~ 65535;
destinations: 以分号形式提供后端需要连接的 MySQL Server 列表;
mode: 该选项必须要指定, 不同模式对应不同的调度策略, 目前支持两种方式: read-write 和 read-only;
max_connections: 连接到 MySQL Router 的最大连接数, 类似 MySQL Server 中的 max_connections 选项;
```

在 mode 选项中, 我们可以选用 read-write 和 read-only 模式:
read-write: 通常用于路由到后端的 MySQL master, 在 read-write 模式中, 所有的流量都转发到 destinations 指定的列表的首个地址, 比如 "127.0.0.1:3301, 127.0.0.1:3302", 则所有的流量都转发到 3301 端口, 如果 3301 端口失败, 则尝试连接 3302 端口, 如果列表中没有有效的MySQL Server, 路由请求会被中断丢弃; 这种方式被称作 "first-available". 这种方式可以适用于一般的主从架构中, 比如指定列表 "master:3301, slave1:3301", 在 master 出现故障的时候, MySQL Router 会自己连接 slave1, 不过中间的切换过程需要我们做很多的操作来满足这种工作模式.

read-only: 路由请求到后端的 MySQL slave, 从这点看 read-only 模式下, destitions 指定的 MySQL Server 列表应该都是 slave, 不同于 read-write 都指定的是 master. 在 read-only 模式中, 使用轮询( round-robin )方式转发请求到后端的 Server. 如果一个 Server 不可用，则尝试下一个 Server, 这意味着不会丢失一个请求, 如果服务都不可用, 则丢弃请求.这种模式下如果应用读写分离, read-only 会是比较好的选择.

从上面两点看, MySQL Router 的服务模式和我们熟知的 cobar, atlas, kingshard 等大为不同, master, slave 都需要单独配置, 这点在扩展性方面比较差, 估计很多人不会喜欢该模式, 不过话说回来, 如果能够和 Fabric 很好的配合使用的话, 可能会吸引一部分用户使用.

<strong>2.1.3 日志</strong>
 
  日志选择可以放到 [logger] 块中, 可以用来指定日志级别, 默认为 INFO, 输出则依赖 logging_folder 的选项:
```
[logger]
level = DEBUG
```

<strong>2.2 配置举例</strong>

我们以读扩展的配置举例说明(read-write 模式估计不受欢迎 ~~, 可以配置多个 routing:<section_key>, MySQL Router 可以启动多个routing ):
```
[DEFAULT]
logging_folder = /usr/local/mysqlrouter/log
plugin_folder = /usr/local/mysqlrouter/lib/mysqlrouter
runtime_folder = /usr/local/mysqlrouter

[logger]
level = DEBUG

[routing:readtest]
bind_address = 0.0.0.0:7001
mode = read-only
destinations = 10.0.21.7:3301,10.0.21.17:3301  #不能有空格
```

<strong>3  连接测试</strong>

启动
```
./bin/mysqlrouter -c /usr/local/mysqlrouter/etc/mysqlrouter.ini
```
   先来看看最简单的测试:
```
[root@cz-centos7 ~]# time for x in `seq 1 5`; do /opt/Percona-Server-5.5.33-rel31.1-566.Linux.x86_64/bin/mysql -h 10.0.21.90 -P 7001 -uroot percona -Bse "show global variables like 'hostname'; show tables"; done
hostname	cz-test2
t
hostname	cz-test3
t
hostname	cz-test2
t
hostname	cz-test3
t
hostname	cz-test2
t

real	0m0.134s
user	0m0.014s
sys	0m0.030s
```
看起来路由是正常的, 再来试试 mysqlslap 读写测试:

*主从结构*
```
+-- 10.0.21.17:3301(master)
   +-- 10.0.21.7:3301(slave)
```

配置举例
```
[DEFAULT]
logging_folder = /usr/local/mysqlrouter/log
plugin_folder = /usr/local/mysqlrouter/lib/mysqlrouter
runtime_folder = /usr/local/mysqlrouter

[logger]
level = DEBUG

[routing:readtest]
bind_address = 0.0.0.0:7001
mode = read-write
destinations = 10.0.21.17:3301 #多个地址用逗号分隔, 中间不能有空格
```

我们这里只设置一个 master, 然后再对比下直连 MySQL 和连接 MySQL Router 的测试结果.

直连 master: 
```
[root@cz-centos7 ~]# /opt/mysql/bin/mysqlslap -h 10.0.21.17 -P 3301 -uroot -a --auto-generate-sql-execute-number=10000 --auto-generate-sql-load-type=read --auto-generate-sql-secondary-indexes=3 --auto-generate-sql-unique-query-number=1 --auto-generate-sql-write-number=1000 -c 10
Benchmark
	Average number of seconds to run all queries: 180.839 seconds
	Minimum number of seconds to run all queries: 180.839 seconds
	Maximum number of seconds to run all queries: 180.839 seconds
	Number of clients running queries: 10
	Average number of queries per client: 10000
```

连接 MySQL Router:
```
[root@cz-centos7 ~]# /opt/mysql/bin/mysqlslap -h 10.0.21.90 -P 7001 -uroot -a --auto-generate-sql-execute-number=10000 --auto-generate-sql-load-type=read --auto-generate-sql-secondary-indexes=3 --auto-generate-sql-unique-query-number=1 --auto-generate-sql-write-number=1000 -c 10
Benchmark
	Average number of seconds to run all queries: 433.598 seconds
	Minimum number of seconds to run all queries: 433.598 seconds
	Maximum number of seconds to run all queries: 433.598 seconds
	Number of clients running queries: 10
	Average number of queries per client: 10000
```

从时间总是上看, 直连方式中10个线程执行 1w 次请求需要大约 181s 左右, 平均每个线程每秒执行5.5次, 连接 MySQL Router 则每个线程平均每秒执行2.3次, 多了一层转发性能消耗还是比较明显的. 这里只是简单的测试, destinations 中如果提供多个服务作为 read 扩展, 相信性能还是会有所提升的.

总体上看, 应用程序本身支持读写分离的话, 分别指定两个 routing section(read-write 和 read-only) 会是很不错的选择, 当然比起 atlas, cobar 等, 应用程序的结构会稍显复杂, 扩展性不强.