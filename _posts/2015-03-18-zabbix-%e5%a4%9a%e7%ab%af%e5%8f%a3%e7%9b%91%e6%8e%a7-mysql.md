---
id: 515
title: zabbix 多端口监控 MySQL
date: 2015-03-18T11:52:14+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=515
permalink: '/zabbix-%e5%a4%9a%e7%ab%af%e5%8f%a3%e7%9b%91%e6%8e%a7-mysql/'
dsq_thread_id:
  - "3604773324"
dsq_needs_sync:
  - "1"
ultimate_sidebarlayout:
  - default
categories:
  - database
  - monit
tags:
  - perl
  - zabbix
---
### 介绍
使用 zabbix 的 low-level 自动发现功能完成单主机多端口的监控, 详见[low_level_discovery](https://www.zabbix.com/documentation/2.2/manual/discovery/low_level_discovery), 整体上监控类似 percona 的 [zabbix](http://www.percona.com/doc/percona-monitoring-plugins/1.1/zabbix/index.html) 监控插件, 不过使用 `mymonitor.pl` 替换了脚本 `ss_get_mysql_stats.php`, 而且配置有点不同.

具体代码及配置详见: [zabbix_mysql](https://github.com/arstercz/zabbix_mysql)


### 1. 结构说明:
```
zabbix_mysql/
|-- README.md
|-- bin
|   |-- get_mysql_stats_wrapper.sh              # 对 mymonitor.pl 运行结果的一个封装脚本, 默认 5 分钟运行一次
|   |-- mymonitor.pl                            # 等同 ss_get_mysql_stats.php 脚本
|   `-- mysql_port.pl                           # 自动发现 MySQL 端口的脚本, 返回 json 格式的输出
|-- install.sh                                  # 安装脚本
`-- templates
    |-- userparameter_discovery_mysql.conf      # zabbix_agent 配置参数
    `-- zabbix_mysql_multiport.xml              # zabbix_server 端模板
```

`mymonitor.pl` 脚本依赖以下模块:
```
perl-DBI
perl-DBD-mysql
```
监控需要的权限包括: `PROCESS, SUPER, REPLICATION SLAVE`, 在 `mysql_port.pl` 脚本中通过 `netstat` 命令获取运行 MySQL 的端口, 脚本以 zabbix 用户(或普通用户)启动, 为避免权限问题, 脚本 install.sh 默认执行 `chmod +s /bin/netstat` 命令.

mymonitor.pl 脚本默认以 `monitor/monitor` 用户及口令的方式连接 MySQL 获取状态， 可以在脚本的初始处修改默认密码, 或者在运行时指定`--user`和`--password`相关参数信息, 也可以在 `/home/mysql/.my.cnf` 指定用户信息, 详细可参见 `perldoc mymonitor.pl`

`get_mysql_stats_wrapper.sh` 脚本默认读取 `mymonitor.pl` 生成的文件以响应 zabbix 的请求, 默认5分钟一次; 同时因为需要频繁(默认1分钟)检测 slave 运行状态, 需要提供 MySQL 登录信息, 以便 slave 的检测.

### 2. 安装说明
在 agent 端操作：
```
# git clone https://github.com/arstercz/zabbix_mysql.git /usr/local/zabbix_mysql
# bash /usr/local/zabbix_mysql/install.sh em1
```
em1 为内网 ip 网卡, 这里考虑到可能存在多个内网ip, 需要用户手动添加.

在 server 端操作:
```
import templates/zabbix_mysql_multiport.xml using Zabbix UI(Configuration -> Templates -> Import), 
and Create/edit hosts by assigning them “MySQL” group and linking the template “MySQL_zabbix” (Templates tab).
```
导入模板, 并将模板加到待监控的机器里.

### 3. 测试
```
# perl  mymonitor.pl --host 10.0.0.10 --port 3300 --items hv
hv:36968
# perl  mymonitor.pl --host 10.0.0.10 --port 3300 --items kx
kx:1070879944

# php ss_get_mysql_stats.php --host 10.0.0.10 --port 3300 --items hv
hv:36968
# php ss_get_mysql_stats.php --host 10.0.0.10 --port 3300 --items kx 
kx:1070911408

# zabbix_get -s 10.0.0.10 -p 10050 -k "MySQL.Bytes-received[3300]"
472339244134
```

### 其它特性

较新的版本增加了 innodb 事务, 锁, 长语句运行检测:
```
item                       throttle
max_duration             if > 100s, then trigger an alarm
waiter_count             if > 10, then trigger an alarm
idle_blocker_duration    if > 200s, then trigger an alarm
```
如下测试:
```
zabbix_get -s cz-test2 -p 10050 -k "MySQL.max_duration[3301]"
max_duration:longest transaction active seconds: max time: 18, thread_id: 4838781, user: root@10.0.21.5:59980
```
