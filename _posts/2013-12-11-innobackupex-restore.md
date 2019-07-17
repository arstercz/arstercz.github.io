---
id: 52
title: innobackupex restore
date: 2013-12-11T00:49:57+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=52
permalink: /innobackupex-restore/
views:
  - "21"
tagline_text_field:
  - ""
dsq_thread_id:
  - "3483502575"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - innobackup
  - MySQL
---
<b>innobackupex恢复原理见</b> <a href="http://www.arstercz.com/how-innobackupex-works/">http://www.arstercz.com/how-innobackupex-works/</a>

<b>以下重做slave过程为prepare和apply-log之后的过程。</b><br/>

创建新从库

移除旧目录：
```
[root@bigdb node3303]# pwd
/srv/mysql/node3303
[root@bigdb node3303]# mv data data_20130221
[root@bigdb node3303]# mkdir data;chown mysql.root data
```
<!--more-->
恢复数据：
```
避免错误：innobackupex: fatal error: no 'mysqld' group in MySQL options
声明xtrabackup/bin目录：PATH=$PATH:$HOME/bin:/opt/xtrabackup/bin/
[root@bigdb node3303]# pwd
/srv/mysql/node3303
[root@bigdb node3303]# innobackupex --defaults-file="my.node.cnf" --copy-back /srv/mysql/mdx/var3/
...
...
innobackupex: Finished copying back files.
130221 14:51:03  innobackupex: completed OK!
```
注意data权限(innobackupex恢复操作保持备份时文件及目录的权限)：
```
[root@bigdb node3303]# chown mysql.mysql data -R
```
查看data目录：
```
[root@bigdb node3303]# ls data
me_thread  ibdata1  mysql  xtrabackup_slave_info
启动实例(注意my.node.cnf文件的skip-slave-start选项)
[root@bigdb node3303]# ./start
waiting node start . node on pid=30374 port=3303 hostid=121
```
启动slave；
     查看master_log信息:注意xtrabackup_binlog_info和xtrabackup_slave_info两个文件的区别：前者为当前备份执行到的位置，  后者为slave对应master执行的位置，如果更换了master，需要查看xtrabackup_binlog_info 或 xtrabackup_binlog_pos_innodb信息以确定master位置；
xtrabackup 备份的时候观察日志信息:出现如下notice:
```
...
 [notice (again)]
 If you use binary log and do not use any hack of group commit,
 the binary log position seems to be:
 InnoDB: Last MySQL binlog file position 0 793902275, file name ./mysql-bin.000025
...

This output can also be found in the xtrabackup_binlog_pos_innodb file, but it is only correct when no other than XtraDB or InnoDB are used as storage engines.

If other storage engines are used (i.e. MyISAM), you should use the xtrabackup_binlog_info file to retrieve the position.

The message about hacking group commit refers to an early implementation of emulated group commit in Percona Server.
```
如果库中只使用了innodb或者XtraDB引擎，恢复的时候使用xtrabackup_binlog_pos_innodb文件确定pos信息;
如果还有其他引擎(如MyISAM)，恢复的时候使用xtrabackup_binlog_info确定pos信息;

<b>恢复操作:</b>
```
[root@bigdb var3]# cat xtrabackup_binlog_info 
mysql-bin.000003 33960805

mysql root@[localhost:s3303 (none)] > reset slave;
Query OK, 0 rows affected (0.00 sec)

mysql root@[localhost:s3303 (none)] > CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000003', MASTER_LOG_POS=33960805, MASTER_HOST='127.0.0.1', MASTER_PORT=13303, MASTER_USER='repl', MASTER_PASSWORD='xxxx', MASTER_CONNECT_RETRY=10;
Query OK, 0 rows affected (0.01 sec);

mysql root@[localhost:s3303 (none)] > start slave;
Query OK, 0 rows affected (0.01 sec);

mysql root@[localhost:s3303 (none)] > show slave status\G
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: 127.0.0.1
                  Master_User: replica
                  Master_Port: 13303
                Connect_Retry: 10
              Master_Log_File: mysql-bin.000003
          Read_Master_Log_Pos: 33969274
               Relay_Log_File: relay-bin.000002
                Relay_Log_Pos: 8720
        Relay_Master_Log_File: mysql-bin.000003
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB: 
          Replicate_Ignore_DB: mysql,test,information_schema,performance_schema
    ......
    ......
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 33969274
              Relay_Log_Space: 8869
    ......
        Seconds_Behind_Master: 0
```

至此完成恢复过程，并恢复主从关系。

<strong>MySQL 5.6 GTID恢复说明</strong>

xtrabackup 从 2.0.7开始支持GTID(5.6复制模式)的复制模式, 开启GTID特性需要以下操作:
```
1. 使用5.6版本;
2. 实例需要开启 gtid_mode = 1
3. 实例需要开启 auto_position
```

GTID恢复类似传统的恢复, 不过在innobackupex备份的时候会输出详细的信息,如下:
```
innobackupex: Backup created in directory '/web/xtrabackup/2014-11-26_11-14-26'
innobackupex: MySQL binlog position: filename 'mysql-bin.000001', position 421, gtid_executed 62f821d2-7453-11e4-bebb-fa163e43bfe5:1
```
gtid_executed为当前master执行的信息;

备份完成后查看文件信息如下:
```
# cat /web/xtrabackup/2014-11-26_11-14-26/xtrabackup_binlog_info 
mysql-bin.000001	421		62f821d2-7453-11e4-bebb-fa163e43bfe5:1
```

新起slave的时候使用以下操作:
```
slave1 > SET GLOBAL gtid_purged="62f821d2-7453-11e4-bebb-fa163e43bfe5:1";
slave1 > CHANGE MASTER TO MASTER_HOST="10.0.1.1", master_user="msandbox", master_password="msandbox", MASTER_AUTO_POSITION = 1;
```