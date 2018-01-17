---
id: 9
title: MHA masterha manager检测master及failover处理说明
date: 2014-03-10T12:39:39+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=9
permalink: '/mha-masterha-manager%e6%a3%80%e6%b5%8bmaster%e5%8f%8afailover%e5%a4%84%e7%90%86%e8%af%b4%e6%98%8e/'
views:
  - "19"
dsq_thread_id:
  - "3477473229"
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - MHA
  - MySQL
---
masterha_manager按照设置频率(ping_interval)定期检测 master 的访问情况, 超过3次检测失败则调用 master_ip_failover_script，master_ip_online_change_script和masterha_master_switch脚本提升一个slave为新的master, 老的master独立出来，供DBA手动操作或者恢复;
详见: https://code.google.com/p/mysql-master-ha/wiki/masterha_manager

masterha_manager检测分为3部分: ping检测, ssh检测, MySQL connection检测;
1. MySQL connection检测: 使用init_conf_load_script参数提供的账号信息连接MySQL，成功则master->slave关系正常，失败转到ssh检测;
2. SSH检测:  在MySQL检测失败的情况下，继续检测ssh连接性，正常通信则拷贝binlog文件为提升新master做准备,失败则宣告master为dead状态，后续的slave提升会忽略该主机的binlog信息;
3. PING检测: 通用检测项,按照ping_interval参数定期ping master主机；

masterha_manager循环检测，直到做一次主从切换(不论切换成功或失败)就退出(退出后发送报告,report_script参数指定); 调用unix daemonize让masterha_manager命令检测作为守护进程运行:
<!--more-->
<pre>
#yum install daemonize

/web/scripts/mha_monitor/
├── 3306.lock
├── 3306.log
├── 3306.pid
└── run_3306          #一对主从，按照端口号区分

#!/bin/bash
daemonize -p /web/scripts/mha_monitor/3306.pid -l /web/scripts/mha_monitor/3306.lock  /usr/bin/masterha_manager --global_conf=/etc/masterha/app_default.cnf --conf=/etc/masterha/app_<name>.conf >> /web/scripts/mha_monitor/3306.log 2>&1
</pre>


详细的检测输出见: /web/masterhalog/app_<name>.log 文件;健康检测情况见masterhalog目录的health文件,按照ping_interval参数的指定时间刷新:
<pre># stat app_<name>.master_status.health 
  File: `app_<name>.master_status.health'
  Size: 34        	Blocks: 8          IO Block: 4096   regular file
Device: 801h/2049d	Inode: 935793      Links: 1
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2014-05-06 10:20:45.000000000 +0800
Modify: 2014-05-06 10:20:45.000000000 +0800
Change: 2014-05-06 10:20:45.432167619 +0800</pre>

总结: 在master不可访问（不管是手工shutdown还是主机或服务崩溃）的时候，masterha_manager会做主从切换, 该点需牢记, 后面如果有手工shutdown却不想切换的操作，可能会掉坑里。非重要业务不要使用该脚本, 出问题后在线切换主从即可; 重要业务可考虑使用，服务或主机崩溃不可访问的时候 30s 左右就可以切换完成。自动切换需考虑InnoDB预热问题(后面处理)；希望masterha_manager脚本一直运行下去，没有退出的一天。