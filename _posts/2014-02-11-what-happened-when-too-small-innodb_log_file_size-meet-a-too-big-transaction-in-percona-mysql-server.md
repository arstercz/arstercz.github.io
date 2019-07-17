---
id: 59
title: 'What happened when too small innodb_log_file_size  meet a too big transaction in Percona MySQL server.'
date: 2014-02-11T00:57:41+08:00
author: arstercz
layout: post
guid: http://www.zhechen.me/?p=59
permalink: /what-happened-when-too-small-innodb_log_file_size-meet-a-too-big-transaction-in-percona-mysql-server/
views:
  - "18"
grid:
  - triple
ribbon:
  - featured
dsq_thread_id:
  - "3557441658"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - innodb
  - log
---
<b>ENV</b>
```
# Percona Toolkit System Summary Report ######################
    Platform | Linux
     Release | CentOS release 5.5 (Final)
      Kernel | 2.6.35.5.R610.CentOS5.5-x64.OpenBeta.KVM.MPT
Architecture | CPU = 64-bit, OS = 64-bit
   Threading | NPTL 2.5
    Compiler | GNU CC version 4.1.2 20080704 (Red Hat 4.1.2-48).
# Processor ##################################################
  Processors | physical = 2, cores = 4, virtual = 4, hyperthreading = no
      Speeds | 4x1595.883
      Models | 4xIntel(R) Xeon(R) CPU 5110 @ 1.60GHz
      Caches | 4x4096 KB
# Memory #####################################################
       Total | 3.9G
# Mounted Filesystems ########################################
  Filesystem  Size Used Type  Opts Mountpoint
  /dev/sda1    20G  35% xfs   rw   /
  /dev/sda3   115G  33% xfs   rw   /web
  tmpfs       2.0G   0% tmpfs rw   /dev/shm

Sandbox
  MySQL-Sandbox-3.0.43

Percona MySQL
  Percona-Server-5.1.63-rel13.4-443.Linux.x86_64.tar.gz
  Percona-Server-5.5.30-rel30.2-500.Linux.i686.tar.gz
```
<!--more-->
<b>The following steps are the test case in sandbox.</b>

<b>step 1:</b>
```
when Server start:
-rw-rw---- 1 zhechen zhechen  10M Feb 13 16:33 ibdata1
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 16:33 ib_logfile0
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 16:31 ib_logfile1
```

<b>step 2:</b>
```
create table and make a big transaction:
as follows:
mysql [localhost] {msandbox} (test) > create table ts(name char(20),year int(3),des varchar(100));
Query OK, 0 rows affected (0.01 sec)

mysql [localhost] {msandbox} (test) > set autocommit = 0;
Query OK, 0 rows affected (0.00 sec)

mysql [localhost] {msandbox} (test) > insert into ts values ('czls-me',30,'wo de idejdie innodb statistics mind me redminezongheng.com');
Query OK, 1 row affected (0.00 sec)

mysql [localhost] {msandbox} (test) > insert into ts select * from ts;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0

mysql [localhost] {msandbox} (test) > insert into ts select * from ts;
Query OK, 2 rows affected (0.00 sec)
Records: 2  Duplicates: 0  Warnings: 0
....
mysql [localhost] {msandbox} (test) > insert into ts select * from ts;
Query OK, 4194304 rows affected (1 min 2.49 sec)
Records: 4194304  Duplicates: 0  Warnings: 0

mysql [localhost] {msandbox} (test) > commit;
Query OK, 0 rows affected (0.04 sec)
# There is no errors in msandbox.err file.

step 3:
Watch the ibdata and ib_logfile files.
as follows:
-rw-rw---- 1 zhechen zhechen  74M Feb 13 16:36 ibdata1
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 16:36 ib_logfile0
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 16:36 ib_logfile1
-rw-rw---- 1 zhechen zhechen 94371840 Feb 13 16:37 ibdata1
-rw-rw---- 1 zhechen zhechen  2097152 Feb 13 16:37 ib_logfile0
-rw-rw---- 1 zhechen zhechen  2097152 Feb 13 16:37 ib_logfile1

-rw-rw---- 1 zhechen zhechen 146M Feb 13 17:03 ibdata1
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 17:03 ib_logfile0
-rw-rw---- 1 zhechen zhechen 2.0M Feb 13 17:03 ib_logfile1
```

<b>Conclusion:</b>
```
Percona MySQL occupy the share tablespace (ibdata) when there is too small innodb_log_file_size meet a big transaction, both the ibdata (undo log contained in share space) and ib_logfile (roundrobin checkpoints) are frequently modified (negative effects on MySQL Performace).

The error that like "InnoDB: ERROR: the age of the last checkpoint is 241588252, InnoDB: which exceeds the log group capacity 241588224." is not present in msandbox.err file.
```