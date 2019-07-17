---
id: 155
title: mha 部署及流程说明
date: 2013-09-09T11:47:17+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=155
permalink: '/mha-mysql-master-high-availability-manaager-%e9%83%a8%e7%bd%b2%e5%8f%8a%e6%b5%81%e7%a8%8b%e8%af%b4%e6%98%8e/'
views:
  - "8"
dsq_thread_id:
  - "3559176001"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - MHA
  - MySQL
  - performance
---
mha (Mysql Master High Availability Manaager) 流程及部署说明

一. 系统环境
**  管理节点
<pre>
   Hostname | mgr.com
    Platform | Linux
     Release | CentOS release 6.4 (Final)
      Kernel | 2.6.32-358.el6.i686
Architecture | CPU = 32-bit, OS = 32-bit
</pre>
<!--more-->
**  节点1
<pre>
    Hostname | node1.com
      System | innotek GmbH; VirtualBox; v1.2 (Other)
 Service Tag | 0
    Platform | Linux
     Release | CentOS release 5.5 (Final)
      Kernel | 2.6.18-194.el5
Architecture | CPU = 32-bit, OS = 32-bit
</pre>

**   节点2
<pre>
    Hostname | node2.com
      System | innotek GmbH; VirtualBox; v1.2 (Other)
 Service Tag | 0
    Platform | Linux
     Release | CentOS release 5.5 (Final)
      Kernel | 2.6.18-194.el5
Architecture | CPU = 32-bit, OS = 32-bit
</pre>

**  节点3
<pre>
    Hostname | node3.com
    Platform | Linux
     Release | CentOS release 6.4 (Final)
      Kernel | 2.6.32-358.el6.i686
Architecture | CPU = 32-bit, OS = 32-bit
</pre>

二. 实验环境:
<pre>
192.168.56.108 (current master)
 +--192.168.56.109
 +--192.168.56.110
 
vip - 192.168.56.200
</pre>
 
From:
<pre>
192.168.56.108 (current master)
 +--192.168.56.109
 +--192.168.56.110
</pre>

To:
<pre>
192.168.56.109 (new master)
 +--192.168.56.110
</pre>
  详细参数:
<pre>
node1.com  192.168.56.108
Version         5.5.30-rel30.2-log
Server ID       199914
Uptime          3+15:39:49 (started 2013-05-30T19:12:20)
Replication     Is not a slave, has 2 slaves connected, is not read_only
Filters         binlog_ignore_db=mysql,test,information_schema,performance_schema
Binary logging  STATEMENT
Slave status    
Slave mode      STRICT
Auto-increment  increment 1, offset 1
InnoDB version  5.5.30-rel30.2
+- 192.168.56.109
   Version         5.5.30-rel30.2-log
   Server ID       134378
   Uptime          3+15:20:38 (started 2013-05-30T19:31:31)
   Replication     Is a slave, has 0 slaves connected, is read_only
   Filters         binlog_ignore_db=mysql,test,information_schema,performance_schema; replicate_ignore_db=mysql,test,information_schema,performance_schema
   Binary logging  STATEMENT
   Slave status    0 seconds behind, running, no errors
   Slave mode      STRICT
   Auto-increment  increment 1, offset 1
   InnoDB version  5.5.30-rel30.2
+- 192.168.56.110
   Version         5.5.30-rel30.2-log
   Server ID       68842
   Uptime          3+15:43:24 (started 2013-05-30T19:08:46)
   Replication     Is a slave, has 0 slaves connected, is not read_only
   Filters         binlog_ignore_db=mysql,test,information_schema,performance_schema; replicate_ignore_db=mysql,test,information_schema,performance_schema
   Binary logging  STATEMENT
   Slave status    0 seconds behind, running, no errors
   Slave mode      STRICT
   Auto-increment  increment 1, offset 1
   InnoDB version  5.5.30-rel30.2
</pre>

三. 配置说明
  详细参数见 : <a href="https://code.google.com/p/mysql-master-ha/wiki/Parameters">Parameters</a>
  
  全局配置:
<pre>
[root@mgr tmha]# cat global.conf 
[server default]
user=root
repl_user=replica
port=3306
init_conf_load_script=/usr/local/bin/init_conf_loads    #  密码信息，不以明文方式显示,init_conf_loads脚本通过base64封装密码;
ssh_user=root
master_binlog_dir=/web/mysql/node3306/data               ## mysql server  数据目录,主从目录需一致,否则每次切换主从后，改参数都需更新.
remote_workdir=/web/log/masterha                         ## mha 管理节点处理的日志信息
ping_interval=3
master_ip_failover_script=/usr/local/bin/master_ip_failover        ## 不定义stop函数 (见流程说明), 定义start函数 切换vip地址
#shutdown_script=/usr/local/bin/power_manager
report_script=/usr/local/bin/send_report                           ## mail 命令发送报告
</pre>

  应用配置 (主从对)
<pre>
[root@mgr tmha]# cat tcase.cnf 
[server default]
manager_workdir=/web/log/mha/tcase1
manager_log=/web/log/mha/tcase1/case1.log

[server1]
hostname=192.168.56.108
candidate_master=1               # master 候选

[server2]
hostname=192.168.56.109
candidate_master=1               #  master 候选

[server3]
hostname=192.168.56.110
no_master=1                      #  永远不做master.
</pre>

mha启用
<pre>
nohup masterha_manager --global_conf=/web/tmha/global.conf --conf=/web/tmha/tcase.cnf --ignore_last_failover > /web/tmha/manager.log 2>&1 & 
</pre>


四. 流程说明   
<a href="https://code.google.com/p/mysql-master-ha/wiki/Sequences_of_MHA">Sequences_of_MHA</a>

<pre>
 | 复制设置和当前 master 的检测 |    注 1
             |
             |
         | 验证 | -- N -> exit.
             |
             Y
             |
       | 监控master |  -- no die --> wait until master dies.  注 2
             |                        /
            die                      /
             |                      /
    | master 连续3次失败 |  -- N --+    注 3
             |
             Y
             |
      | 检测 slave 配置 |   -- N --> stop with error. 注 4
             |
             Y
             |
      | last failover | [optional]  -- Y --> stop     ||--> ignore this setup by using ignore_last_failover
             |
             N
             |
    | master_ip_failover | [optional]  -- Y -- stop server || ->  注1   modify script based on environment.   注 5
             |
             N
             |
   | recovering new master | -- 1. saving binaty log [optinal] -- 2. determining new master -- 3. latest slave -- 4. recovering and promoting new master. 注 6.
             |
   | activating new master | -- switch virtual ip address [optional]  注 7.
             |
   | recovering rest slaves | 
             |
     | notification |  [optional]  --- sending mails
</pre>

### 注 :

1. 

```MHA::ServerManager::validate_slaves() slave检测;  MHA::ServerManager::get_current_alive_master()  当前master;```

2.

```
apply_diff_relay_logs --command=test --slave_user='root' --slave_host=192.168.56.110 --slave_ip=192.168.56.110 --slave_port=3306
MHA::SSHCheck::do_ssh_connection_check()  -- ssh 检测;   MHA::MasterMonitor::check_slave_env() slave环境检测; MHA::ManagerUtil::exec_ssh_cmd()    slave有效性检测;
MHA::HealthCheck::wait_until_unreachable()  -- master 健康检查;
```

3.

```MHA::HealthCheck::wait_until_unreachable()  MHA::SSHCheck::do_ssh_connection_check() ssh 检测;```

4.

```MHA::MasterMonitor::wait_until_master_is_dead()  master失效后的操作； ```

5.

```
MHA::MasterFailover::do_master_failover() 主故障切换; 
force_shutdown -- sshrecheable : stopssh ; sshunreachable : stop mysql server 
       /usr/local/bin/master_ip_failover --orig_master_host=192.168.56.108 --orig_master_ip=192.168.56.108 --orig_master_port=3306 --command=stop		
```
 
6.
```
MHA::MasterFailover::check_set_latest_slaves() ;  选择具有最新relay logs的slave;
MHA::MasterFailover::save_master_binlog() ;   获取旧master的log信息,依赖于sshreachable，如果unreachable,返回warning信息;
MHA::MasterFailover::select_new_master() ;   选择新master;
MHA::MasterFailover::recover_master_internal();  Master Log Apply;
MHA::MasterFailover::recover_master();  启用新master, $new_master->disable_read_only()  新master禁止read_only
MHA::ServerManager::get_new_master_binlog_position() 得到新master的位置信息;
MHA::MasterFailover::recover_slave();   更新所有slave 记录,与新master保持一致;
MHA::Server::reset_slave_on_new_master() , reset_slave_info  and  reset_slave_all  更新所有slave到新master. 
                                                                        /
                                                                       /
MHA::DBHelper::reset_slave_by_change_master   清楚change master信息, change_master() 更新新的change master语句;   
```

7.
```
/usr/local/bin/master_ip_failover --command=start --ssh_user=root --orig_master_host=192.168.56.108 
--orig_master_ip=192.168.56.108 --orig_master_port=3306
--new_master_host=192.168.56.109 --new_master_ip=192.168.56.109 
--new_master_port=3306 --new_master_user='root' --new_master_password='xxxxxx' 
 ```
 
五. 切换日志见 <a href=http://doc.highdb.com/upload/2014/06/case1.txt>case.log</a>