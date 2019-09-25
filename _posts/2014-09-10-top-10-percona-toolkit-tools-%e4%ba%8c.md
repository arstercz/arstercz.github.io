---
id: 324
title: top 10 percona toolkit tools (二)
date: 2014-09-10T17:11:13+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=324
permalink: '/top-10-percona-toolkit-tools-%e4%ba%8c/'
dsq_thread_id:
  - "3469228787"
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - percona
  - tool
---
3. pt-show-grants

[pt-show-grants](http://www.percona.com/doc/percona-toolkit/2.2/pt-show-grants.html) 导出权限表信息:以sql语句的形式列出mysql.user表的权限信息，方便管理员进行批量修改, 该功能在迁移数据库, 尤其是不同网段的情况下非常有用; 如下为导出的权限信息:

```sql
# pt-show-grants -S /data/mysql/3306.sock --password=xxxxxxxx
-- Grants for 'root'@'10.0.0.%'
GRANT ALL PRIVILEGES ON *.* TO 'root'@'10.0.0.%' IDENTIFIED BY PASSWORD '*4661D72F443CFC758BECA246B5FA89525BF23E91';
-- Grants for 'root'@'127.0.0.1'
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY PASSWORD '*4661D72F443CFC758BECA246B5FA89525BF23E91' WITH GRANT OPTION;
-- Grants for 'root'@'localhost'
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY PASSWORD '*4661D72F443CFC758BECA246B5FA89525BF23E91' WITH GRANT OPTION;
GRANT PROXY ON ''@'' TO 'root'@'localhost' WITH GRANT OPTION;
```
可以修改导出的信息, 再导入到迁移的新库中。
其它参数:

```
--drop: 输出信息中增加drop user语句;
--flush: 输出信息后，执行flush privileges语句;
--revoke:输出信息中增加revoke语句;
--only:仅输出show grants相关的语句;
```

4. pt-mysql-summary

[pt-mysql-summary](http://www.percona.com/doc/percona-toolkit/2.2/pt-mysql-summary.html) 收集 MySQL 信息, 这不是一个调优或分析的工具，只是搜集了很多Server端的详细信息, 方便管理员查看。 pt-mysql-summary生成的报告可以很方便的进行diff或编辑操作; 该脚本以bash shell编写.

输出信息包括:

```bash
# pt-mysql-summary -S /web/mysql/3306.sock --password=xxxxxxxx

# Instances ##################################################
  Port  Data Directory             Nice OOM Socket
  ===== ========================== ==== === ======
   3306 /web/mysql/data   0    0   /web/mysql/3306.sock
# MySQL Executable ###########################################
  ..... (basedir)
# Report On Port 3306 ########################################
                     User | root@localhost
                     Time | 2014-09-10 16:56:11 (CST)
                 Hostname | cz
                  Version | 5.5.23-rel25.3-log Percona Server with XtraDB (GPL), Release rel25.3, Revision 240 
                 Built On | Linux x86_64
# Processlist ################################################
  Query ...
  User ...
# Status Counters (Wait 10 Seconds) ##########################
  (MySQL status ...)
# Table cache ################################################
....
# InnoDB #####################################################
....
# Configuration File #########################################
....
....
```

几乎囊括了所有相关的信息, 也可以作为一个简单的镜像状态报告， 中间的一些导出schema信息可以自由选择。
其它参数:

```
--save-samples: 将数据信息保存到指定的空目录下,比如在sample空目录下生成以下文件, 分别对应上述输出的区域信息:
                collect.err    mysql-config-file  mysqld-executables  mysql-master-logs    mysql-plugins
                mysql-slave    mysql-status-defer  mysql-variables innodb-status  mysql-databases    
                mysqld-instances    mysql-master-status  mysql-processlist  mysql-status  mysql-users
        
--read-samples: 读取指定目录下的文件，生成报告信息，比如读取上面--save-samples选项生成的文件生成相应的报告:
                pt-mysql-summary --read-samples=sample

--sleep: 搜集status计数信息的时候sleep的秒数时长;
```
