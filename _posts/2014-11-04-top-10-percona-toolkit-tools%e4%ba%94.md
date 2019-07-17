---
id: 385
title: top 10 percona toolkit tools(五)
date: 2014-11-04T17:21:45+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=385
permalink: '/top-10-percona-toolkit-tools%e4%ba%94/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3471933994"
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - MySQL
  - percona
---
9. pt-table-checksum
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-table-checksum.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-table-checksum.html</font></a>
主从表数据一致校验: 该工具通过分组(chunk)方式以hash, md5, cac32或自定义函数生成每个分组数据的检验串, 分别在master和slave端执行, 如果每个分组的校验串一致, 则认为该分组的数据在master和slave一致。详见: <a href="http://arstercz.com/mysql%E4%B8%BB%E4%BB%8E%E6%95%B0%E6%8D%AE%E4%B8%80%E8%87%B4%E6%80%A7%E6%A0%A1%E9%AA%8C/"><font color="green">http://arstercz.com/mysql%E4%B8%BB%E4%BB%8E%E6%95%B0%E6%8D%AE%E4%B8%80%E8%87%B4%E6%80%A7%E6%A0%A1%E9%AA%8C/</font></a>, 这种方式可以相对有效的找出主从中哪个chunk组的数据不一致, 进而再继续细分chunk, 找出具体的行。 不过分组校验不一定能够严格校验主从的不一致, 这依赖校验函数的冲突率有多大, 默认的crc32函数的冲突率还是偏大的, 如果恰好有几个字符串算出的结果一样, 则该工具出现漏报的可能性, 误报的可能性不能完全杜绝。
<!--more-->

该工具由以下限制:
(1) 校验数据是假设主从的schema和table结构在master和slave上一致.
(2) 主从复制格式需要为statement格式, 该工具默认检测binlog_format参数, 如果想忽略检测可以指定 --nocheck-binlog-format

该工具默认情况下创建percona.checksums表用于保存校验的结果, 该表有2个作用:
(1) 方面查看哪些信息不一致, 可以使用以下语句:
<pre>
SELECT db, tbl, SUM(this_cnt) AS total_rows, COUNT(*) AS chunks FROM checksums WHERE ( master_cnt <> this_cnt OR master_crc <> this_crc OR ISNULL(master_crc) <> ISNULL(this_crc)) GROUP BY db, tbl;
</pre>
(2) 方便pt-table-sync(数据纠错)的增量使用.

举例如下:
<pre>
[root@cz ~]# pt-table-checksum h=10.3.254.110,u=root,p=xxxxxx,P=30587 --databases="part1" --tables="book" --nocheck-replication-filters 
            TS ERRORS  DIFFS     ROWS  CHUNKS SKIPPED    TIME TABLE
04-11T12:09:46      0      1   168949       4       0   1.218 part1.book
</pre>
diffs列显示主从约有1个分组的记录不一致, book表一共检测了168949行记录, 分4次校验完.

参数信息也可以写到文件里,通过--config参数指定,比如对test表进行校验, 将参数写到pt-table.cnf文件中:
<pre>
host           = 127.0.0.1
user           = root
password       = xxxxxxxx
port           = 3306
databases      = test
tables         = test
chunk-size     = 3000
max-lag        = 5
check-interval = 3
recursion-method=processlist
recurse        = 1
#resume
#replicate-check-only
</pre>
# pt-table-checksum --config pt-table.cnf  即可开始校验test.test表, 不指定tables参数, 则检测test库的所有表;

其它参数:
<pre>
--[no]check-binlog-format： 默认情况下该工具检测所有server的binlog_format, 该参数用来控制是否检测.

--check-interval: 如果指定了 --max-log参数， 则每次检测的时候sleep指定的时间,默认为1s.

--[no]check-plain: 出于安全方面的因素，需要检测query的查询执行计划(EXPLAIN), 默认为yes.

--[no]check-replication-filters:出于一些原因slave可能会配置binlog_ignore_db或replicate_do_db这些参数, 默认情况下该工具检测到有过滤规则则返回error并推出.

--check-slave-lag: 如果指定了max-lag参数,并且slave延迟的值大于max-lag则暂停校验, 待恢复后继续执行.

--chunk-index: 默认情况下该工具选择最有可能的索引进行chunk, 该参数用来指定索引进行chunk分组.

--columns: 用于指定只检测表的指定列的信息.

--explain: 只显示却不执行校验的语句.

--function: 用于指定校验数据时用的函数, 默认为crc32, 可以是FNV1A_64, MURMUR_HASH, SHA1, MD5, CRC32等.

--resume: 从上一次校验完成后的chunk开始执行本次的校验, 该参数可用于增量校验大表数据. 如果应用有很多update或delete操作, 则不应该启用该参数.
</pre>

10. pt-table-sync
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-table-sync.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-table-sync.html</font></a>
数据同步工具: 该工具主要用不同MySQL的表之间的数据同步, 可以是master->slave, master->master或一个instance到另一个instance. 同步功能会做一些数据的修改操作, 如果表信息很重要, 操作前可以备份好相关的表. 这里主要介绍指定replicate或sync-to-master参数时, pt-table-sync工具如何工作. 
以下为该工具的处理逻辑:
<pre>
if DSN has a t part, sync only that table:
   if 1 DSN:
      if --sync-to-master:
         The DSN is a slave.  Connect to its master and sync.
   if more than 1 DSN:
      The first DSN is the source.  Sync each DSN in turn.
else if --replicate:
   if --sync-to-master:
      The DSN is a slave.  Connect to its master, find records
      of differences, and fix.
   else:
      The DSN is the master.  Find slaves and connect to each,
      find records of differences, and fix.
else:
   if only 1 DSN and --sync-to-master:
      The DSN is a slave.  Connect to its master, find tables and
      filter with --databases etc, and sync each table to the master.
   else:
      find tables, filtering with --databases etc, and sync each
      DSN to the first.
</pre>
按照手册页的例子来说明:
<pre>
(1) pt-table-sync --execute --sync-to-master slave1
</pre>
如果指定了sync-to-master选项, DSN应该为slave的连接信息, 这时pt-table-sync会连接该slave的master, 并将master的数据同步到该slave.
<pre>
(2) pt-table-sync --execute --replicate test.checksum master1
</pre>
replicate选项用到了上一个工具pt-table-checksum, 其读取pt-table-checksum生成的checksum表信息， 然后进行同步操作, master1表示同步master1的数据到所有的slave节点.
<pre>
(3) pt-table-sync --execute --replicate test.checksum --sync-to-master slave1
</pre>
同上面的命令, 但是只同步master1的数据到slave1节点.
在同步方面, 安全的方式是在master上更新数据(比如,delete或replace等), 通过主从复制来完成同步, 这种方式和其它正常的更新一样,通过主从机制完成. 
同步的过程:
同步过程主要包括以下操作:
(1) 如果没有指定replicate选项, 则先对数据进行分组(在master和slave端)校验, 校验的方式同pt-table-checksum, 找到不同的chunk组之后, 再对该组进行细分进行校验直到找到相关的行记录; 找到记录后, 在master中进行数据的更改, 通过主从复制来实现数据的同步.
(2) 如果指定了replicate选项, 则读取checksums表, 该步骤免去了校验过程, 可以得到不同的chunk组信息, 后续的过程同(1)的操作.

pt-table-sync的校验过程举例如下:
<pre>
[root@cz rsandbox_Percona-Server-5_6_15]# pt-table-sync --databases percona --execute --sync-to-master  h=localhost,P=19681,u=root,p=xxxxxx,S=/tmp/mysql_sandbox19681.sock --verbose --print --recursion-method=hosts --chunk-size=1
# Syncing P=19681,S=/tmp/mysql_sandbox19681.sock,h=localhost,p=...,u=root
# DELETE REPLACE INSERT UPDATE ALGORITHM START    END      EXIT DATABASE.TABLE
REPLACE INTO `percona`.`dept`(`id`, `name`) VALUES ('30', 'insert test') /*percona-toolkit src_db:percona src_tbl:dept src_dsn:P=19680,S=/tmp/mysql_sandbox19681.sock,h=127.0.0.1,p=...,u=root dst_db:percona dst_tbl:dept dst_dsn:P=19681,S=/tmp/mysql_sandbox19681.sock,h=localhost,p=...,u=root lock:1 transaction:1 changing_src:1 replicate:0 bidirectional:0 pid:9674 user:root host:z10*/;
#      0       1      0      0 Chunk     15:37:33 15:37:33 2    percona.dept
</pre>
上述信息描述了同步percona.dept表的信息过程, master比slave多了一条记录('30', 'insert test'), pt-table-checksum检测到后通过在master上使用replace这条sql实现了两边的同步, 打开master或slave的general log参数, 可以看到以下信息:
<pre>
                   67 Query     START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */
                   67 Query     SELECT /*percona.dept:18/20*/ 17 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `name`, CONCAT(ISNULL(`id`), ISNULL(`name`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `percona`.`dept` FORCE INDEX (`id_idx`) WHERE (`id` >= '28' AND `id` < '29') FOR UPDATE
                   68 Query     SHOW MASTER STATUS
                   67 Query     SET @crc := '', @cnt := 0
                   67 Query     commit
                   67 Query     START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */
                   67 Query     SELECT /*percona.dept:19/20*/ 18 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `name`, CONCAT(ISNULL(`id`), ISNULL(`name`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `percona`.`dept` FORCE INDEX (`id_idx`) WHERE (`id` >= '29') FOR UPDATE
                   68 Query     SHOW MASTER STATUS
                   67 Query     SET @crc := '', @cnt := 0
                   67 Query     SELECT /*rows in chunk*/ `id`, `name`, CRC32(CONCAT_WS('#', `id`, `name`, CONCAT(ISNULL(`id`), ISNULL(`name`)))) AS __crc FROM `percona`.`dept` FORCE INDEX (`id_idx`) WHERE (`id` >= '29') ORDER BY `id` FOR UPDATE
                   67 Query     SELECT `id`, `name` FROM `percona`.`dept` WHERE `id`='30' LIMIT 1
                   67 Query     REPLACE INTO `percona`.`dept`(`id`, `name`) VALUES ('30', 'insert test') /*percona-toolkit src_db:percona src_tbl:dept src_dsn:P=19680,S=/tmp/mysql_sandbox19681.sock,h=127.0.0.1,p=...,u=root dst_db:percona dst_tbl:dept dst_dsn:P=19681,S=/tmp/mysql_sandbox19681.sock,h=localhost,p=...,u=root lock:1 transaction:1 changing_src:1 replicate:0 bidirectional:0 pid:9674 user:root host:cz*/
                   67 Query     SET @crc := '', @cnt := 0
                   67 Query     commit
                   67 Query     START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */
                   67 Query     SELECT /*percona.dept:20/20*/ 19 AS chunk_num, COUNT(*) AS cnt, COALESCE(LOWER(CONV(BIT_XOR(CAST(CRC32(CONCAT_WS('#', `id`, `name`, CONCAT(ISNULL(`id`), ISNULL(`name`)))) AS UNSIGNED)), 10, 16)), 0) AS crc FROM `percona`.`dept` FORCE INDEX (`id_idx`) WHERE (`id` IS NULL) FOR UPDATE
</pre>
可以看到校验的过程和pt-table-checksum是类似的, 通过chunk(chunk-size=1)的方式分组校验master和slave的数据, 上述信息的where id >= ? 信息可以看到此变化, 找到id=30的记录后(slave没有id=30的记录), 在master上执行replace语句, 通过主从复制保证了两边表数据的最终一致.

其它参数:
<pre>
--algorithms：使用什么算法来发现两边数据的不同, 默认为chunk, 详细可以参见手册页algorithms部分.

--[no]bin-log: pt-table-sync在执行更新操作的时候(如上面的replace语句), 是否需要记录到binlog日志里, 默认为记录.

--[no]check-child-tables: 如果待同步的表存在外键约束, 比如 ON DELETE CASCADE, ON UPDATE CASCADE, 该工具会打印错误并退出, 该参数用户指定是否需要检测外键约束.

--[no]check-slave: 是否检测目的Server是一个slave.

--[no]check-triggers: 检测表没有trigger信息.

--columns: 只校验指定列的信息.

--[no]foreign-key-checks: 是否检测外键, 默认为检测.

--function: 用于指定校验的函数, 同pt-table-checksum工具的该选项.

--[no]hex-blob: 如果表字段有二进制(blob,binary等)字段信息, 则用hex()函数进行封装处理,以避免产生一个无效的sql语句.

--lock: 在校验数据的时候是否进行锁表操作.

--print: 打印更新操作的sql语句信息.
</pre>