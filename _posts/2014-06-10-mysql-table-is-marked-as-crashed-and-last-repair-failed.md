---
id: 161
title: MySQL table is marked as crashed and last repair failed
date: 2014-06-10T10:45:37+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=161
permalink: /mysql-table-is-marked-as-crashed-and-last-repair-failed/
views:
  - "20"
dsq_thread_id:
  - "3525146426"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - MySQL
---
1.Problem description.
One table in my database was crashed, and automatic repair of the MySQL system failed. error message occured when I use desc table:
<pre>
(root:cz:)[foot]> desc others_ipstat;
ERROR 144 (HY000): Table './foot/others_cz' is marked as crashed and last (automatic?) repair failed
(root:cz:)[foot]> show create table others_ipstat\G
ERROR 144 (HY000): Table './foot/others_cz' is marked as crashed and last (automatic?) repair failed
</pre>
<!--more-->
alter disable keys failed:
<pre>
(root:cz:)[foot]> alter table others_cz disable keys;
ERROR 144 (HY000): Table './foot/others_cz' is marked as crashed and last (automatic?) repair failed
</pre>

The following lists the table's info, it identified the index file others_cz.MYI may be the reason of the repair failed, because frm and MYD file had a long time no update. 
<pre>
-rw-rw---- 1 mysql mysql 8.6K 2011-07-12 others_cz.frm
-rw-rw---- 1 mysql mysql  17G 03-15 23:00 others_cz.MYD
-rw-rw---- 1 mysql mysql  16G 06-05 19:38 others_cz.MYI
</pre>

2. The error message was presented when I use myisamchk to recovry:
<pre>
[root@cz foot]# /usr/local/mysql/bin/myisamchk -r others_cz
- recovering (with sort) MyISAM-table 'others_cz'
Data records: 0
- Fixing index 1
- Fixing index 2
- Fixing index 3
myisamchk: error: myisam_sort_buffer_size is too small
MyISAM-table 'others_cz' is not fixed because of errors
Try fixing it by using the --safe-recover (-o), the --force (-f) option or by not using the --quick (-q) flag
</pre>

Modify the tmpdir variables value:
<pre>
+-------------------+--------------+
| Variable_name     | Value        |
+-------------------+--------------+
| max_tmp_tables    | 32           |
| slave_load_tmpdir | /data/tmp |
| tmp_table_size    | 257949696    |
| tmpdir            | /data/tmp |
+-------------------+--------------+
4 rows in set (0.00 sec)
</pre>

Error was still there:
<pre>
[root@bigfoot02 bigfoot]# /usr/local/mysql/bin/myisamchk -r others_ipstat
- recovering (with sort) MyISAM-table 'others_ipstat'
Data records: 0
- Fixing index 1
- Fixing index 2
- Fixing index 3
myisamchk: error: myisam_sort_buffer_size is too small
MyISAM-table 'others_cz' is not fixed because of errors
Try fixing it by using the --safe-recover (-o), the --force (-f) option or by not using the --quick (-q) flag
</pre>

3.note
Repair table in mysql client is equal to 'myisamchk -r' in shell env, the difference is that repair command use the value of variables relay on MySQL Server parameters， so tmpdir and sort_buffer_size should be set relevantly. myisamchk need extra specified, because myisamchk allocate memory does not relay on MySQL Server. read more from:<a href="http://dev.mysql.com/doc/refman/5.5/en/myisamchk-memory.html">http://dev.mysql.com/doc/refman/5.5/en/myisamchk-memory.html</a>

<pre>
[root@cz foot]# /usr/local/mysql/bin/myisamchk --sort_buffer_size=2G --key_buffer_size=512M --read_buffer_size=32M --write_buffer_size=32M --tmpdir=/data/tmp/ -r others_cz
- recovering (with sort) MyISAM-table 'others_cz'
Data records: 0
- Fixing index 1
- Fixing index 2
- Fixing index 3
- Fixing index 4
Data records: 491792780
</pre>

Resource used durning the myisamchk repair:
<pre>
  PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND                                                                                                                          
 7025 root      18   0 2108m 2.0g 1012 D 62.9 13.0  18:28.51 myisamchk                                                                                                          
</pre>

In addition to there maybe lossing records or mistake, you can check table frequently by use mysqlcheck.