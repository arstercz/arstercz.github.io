---
id: 366
title: top 10 percona toolkit tools (四)
date: 2014-10-19T13:17:33+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=366
permalink: '/top-10-percona-toolkit-tools-%e5%9b%9b/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3572366638"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - MySQL
  - percona
---
7. pt-query-digest
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-query-digest.html"><font color='green'>http://www.percona.com/doc/percona-toolkit/2.2/pt-query-digest.html</font></a>
分析query 语句: 该工具可用于统计分析 slow log, processlist, binary log 和 tcpdump 相关的sql 语句信息, 生成详细的报表供管理员查看或排错。我们最长用的可能是分析 slow log 和 tcpdump 文件, 基于以下几种场景: 
(1) 想详细了解过去一段时间慢查询的整体状况，比如哪类的 sql, 这类 sql 主要的时间分布(us, ms, 还是 s 级别的居多), 主要的行数检查, 数据发送量等；
(2) 一些执行时间短的 sql 不会出现在 slow log 或 processlist 列表中,管理员也难以全部抓取相关的sql, 可以使用该工具分析tcpdump监听MySQL端口的日志信息, 得到较为全面的报告列表, 包括的列表同(1)中的信息;
(3)该工具早期的版本支持sql重放等工具, 对InnoDB的预热需求是一个不错的手段, 详见 <a href="http://arstercz.com/keep-your-slave-warm/"><font color="green">http://arstercz.com/keep-your-slave-warm/</font></a>, 也支持统计分析tcpdump监听memcached生成的日志文件。
<!--more-->

生成报告举例如下:
# pt-query-digest query_slow.log
<pre>
# Query 5: 0 QPS, 0x concurrency, ID 0x84B3C3C1C1C732F4 at byte 37257 ____
# This item is included in the report because it matches --limit.
# Scores: V/M = 0.00
# Time range: all events occurred at 2014-10-17 09:42:28
# Attribute    pct   total     min     max     avg     95%  stddev  median
# ============ === ======= ======= ======= ======= ======= ======= =======
# Count          0       1
# Exec time      5     23s     23s     23s     23s     23s       0     23s
# Lock time      0   165us   165us   165us   165us   165us       0   165us
# Rows sent      0   2.23k   2.23k   2.23k   2.23k   2.23k       0   2.23k
# Rows examine   0   2.23k   2.23k   2.23k   2.23k   2.23k       0   2.23k
# Rows affecte   0       0       0       0       0       0       0       0
# Rows read      0   2.23k   2.23k   2.23k   2.23k   2.23k       0   2.23k
# Bytes sent     0 135.71k 135.71k 135.71k 135.71k 135.71k       0 135.71k
# Merge passes   0       0       0       0       0       0       0       0
# Tmp tables     0       1       1       1       1       1       0       1
# Tmp disk tbl   2       1       1       1       1       1       0       1
# Tmp tbl size   0       0       0       0       0       0       0       0
# Query size     0     220     220     220     220     220       0     220
# Boolean:
# Full scan    100% yes,   0% no
# Tmp table    100% yes,   0% no
# Tmp table on 100% yes,   0% no
# String:
# Databases    log
# Hosts
# Last errno   0
# Users        cacti
# Query_time distribution
#   1us
#  10us
# 100us
#   1ms
#  10ms
# 100ms
#    1s
#  10s+  ################################################################
# Tables
#    SHOW TABLE STATUS FROM `information_schema` LIKE 'tables'\G
#    SHOW CREATE TABLE `information_schema`.`tables`\G
# EXPLAIN /*!50100 PARTITIONS*/
SELECT CONCAT(table_schema,'.',table_name,',',engine,',',IFNULL(create_time,'0000-00-00 00:00:00')) 
     FROM information_schema.tables 
     WHERE table_schema NOT IN ('mysql','information_schema','performance_schema')\G
</pre>
时间分布， 数据发送量， 行数检查等都非常详细.
tcpdump监听举例如下:
<pre>
tcpdump -s 65535 -x -nn -q -tttt -c 500000 -i any port 3305 > mysql.3305.txt
pt-query-digest --type tcpdump --watch-server='10.0.10.10:3305' mysql.3305.txt >3301.log
</pre>
报告列表同上述的slow log分析。

其它参数:
<pre>
--attribute-aliases: query语句中可能会出现alias相关的信息, 比如 tb1 as a, 该参数为没有主属性的事件添加一个alias属性, 如果有主属性，则移除alias相关的属性；

--[no]continue-on-error: 用于指定在分析的时候出现错误， 是否停止继续分析， 默认为继续分析；

--[no]create-history-table： 用于指定是否创建历史表,由--history指定, 存储历史的分析记录；归档功能很不错；

--daemonize：作为daemon进程进行运行, 要持续的分析query信息可以使用该参数；

--filter：可以指定perl相关的表达式或函数，来过滤需要的信息；

--history： 创建历史表， 列包括生成报告的很多属性信息，保存query的属性信息;

--interval：多场时间获取一次processlist信息, 单位为s；

--logz：打印报告信息，该参数在指定daemonize参数的时候有用；

--processlist：获取processlist相关的列表信息；

--set-vars：连接MySQL时候需要设置的参数变量信息,比如wait_timeout=300；多个参数以,分隔；

--type：用于指定来源query的类型, 包括binlog(binary log), genlog(general log), slowlog(slow query logs), tcpdump(tcp监听的文件信息), rawlog(一行一条sql的文本文件)；

--watch-server：如果MySQL通过vip对外服务, 可以指定该参数指定实际服务的ip和port, 如上述的tcpdump示例；
</pre>

8. pt-stalk
<a href=http://www.percona.com/doc/percona-toolkit/2.2/pt-stalk.html><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-stalk.html</font></a>
pt-stalk: 该工具用于在发生问题时， 采集相关的取证分析数据,没有发生问题时一直等待直到触发的条件满足则进行相关信息的搜集工作，包括出问题时磁盘的使用,gdb信息, 内存，cpu, MySQL执行语句的镜像, 相关的参数和状态信息, 基本包括了所有能搜集的信息;该工具被设计为使用root权限作为daemon进行运行。触发的条件可以是 --function, --variable, --threshold, 和 --cycles, 默认情况下该工具监控MySQL直到满足触发条件则进行数据收集, 通常的执行逻辑如下:
<pre>
while true; do
   if --variable from --function > --threshold; then
      cycles_true++
      if cycles_true >= --cycles; then
         --notify-by-email
         if --collect; then
            if --disk-bytes-free and --disk-pct-free ok; then
               (--collect for --run-time seconds) &
            fi
            rm files in --dest older than --retention-time
         fi
         iter++
         cycles_true=0
      fi
      if iter < --iterations; then
         sleep --sleep seconds
      else
         break
      fi
   else
      if iter < --iterations; then
         sleep --interval seconds
      else
         break
      fi
   fi
done
rm old --dest files older than --retention-time
if --collect process are still running; then
   wait up to --run-time * 3 seconds
   kill any remaining --collect processes
fi
</pre>
相关的数据被写到以timestamp开头的文件,可以使用pt-sift帮助我们查看和分析生成的数据；
常用的示例见: <a href="http://www.percona.com/blog/2013/01/03/percona-toolkit-by-example-pt-stalk/"><font color="green">http://www.percona.com/blog/2013/01/03/percona-toolkit-by-example-pt-stalk/</font></a>
举例如下:
<pre>
#pt-stalk --sleep=10 --function=processlist --variable Host --match localhost --threshold=1 --defaults-file=./my.node.cnf --host=127.0.0.1 --user=root --password=xxxxxx --socket=data/s3306
2014_10_19_12_41_19 Starting /usr/bin/pt-stalk --function=processlist --variable=Threads_running --threshold=25 --match= --cycles=5 --interval=1 --iterations= --run-time=30 --sleep=10 --dest=/var/lib/pt-stalk --prefix= --notify-by-email= --log=/var/log/pt-stalk.log --pid=/var/run/pt-stalk.pid --plugin=
2014_10_19_12_50_58 Check results: processlist(Host)=2, matched=yes, cycles_true=1
2014_10_19_12_50_59 Check results: processlist(Host)=2, matched=yes, cycles_true=2
2014_10_19_12_51_00 Check results: processlist(Host)=2, matched=yes, cycles_true=3
2014_10_19_12_51_01 Check results: processlist(Host)=2, matched=yes, cycles_true=4
2014_10_19_12_51_02 Check results: processlist(Host)=2, matched=yes, cycles_true=5
2014_10_19_12_51_02 Collect 1 triggered
2014_10_19_12_51_02 Collect 1 PID 28678
2014_10_19_12_51_02 Collect 1 done
2014_10_19_12_51_02 Sleeping 10 seconds after collect
</pre>
本地连接数超过达到预警值1得时候开始收集信息, /var/lib/pt-stalk目录列表如下:
<pre>
[root@cz ~]# ls /var/lib/pt-stalk/
2014_10_19_12_51_02-df              2014_10_19_12_51_02-netstat_s       2014_10_19_12_51_21-df              2014_10_19_12_51_21-netstat_s
2014_10_19_12_51_02-disk-space      2014_10_19_12_51_02-opentables1     2014_10_19_12_51_21-disk-space      2014_10_19_12_51_21-opentables1
2014_10_19_12_51_02-diskstats       2014_10_19_12_51_02-output          2014_10_19_12_51_21-diskstats       2014_10_19_12_51_21-output
2014_10_19_12_51_02-innodbstatus1   2014_10_19_12_51_02-pmap            2014_10_19_12_51_21-innodbstatus1   2014_10_19_12_51_21-pmap
2014_10_19_12_51_02-interrupts      2014_10_19_12_51_02-processlist     2014_10_19_12_51_21-interrupts      2014_10_19_12_51_21-processlist
2014_10_19_12_51_02-iostat          2014_10_19_12_51_02-procstat        2014_10_19_12_51_21-iostat          2014_10_19_12_51_21-procstat
2014_10_19_12_51_02-iostat-overall  2014_10_19_12_51_02-procvmstat      2014_10_19_12_51_21-iostat-overall  2014_10_19_12_51_21-procvmstat
2014_10_19_12_51_02-lock-waits      2014_10_19_12_51_02-ps              2014_10_19_12_51_21-lock-waits      2014_10_19_12_51_21-ps
2014_10_19_12_51_02-log_error       2014_10_19_12_51_02-slabinfo        2014_10_19_12_51_21-log_error       2014_10_19_12_51_21-slabinfo
2014_10_19_12_51_02-lsof            2014_10_19_12_51_02-sysctl          2014_10_19_12_51_21-lsof            2014_10_19_12_51_21-sysctl
2014_10_19_12_51_02-meminfo         2014_10_19_12_51_02-top             2014_10_19_12_51_21-meminfo         2014_10_19_12_51_21-top
2014_10_19_12_51_02-mpstat          2014_10_19_12_51_02-transactions    2014_10_19_12_51_21-mpstat          2014_10_19_12_51_21-transactions
2014_10_19_12_51_02-mpstat-overall  2014_10_19_12_51_02-trigger         2014_10_19_12_51_21-mpstat-overall  2014_10_19_12_51_21-trigger
2014_10_19_12_51_02-mutex-status1   2014_10_19_12_51_02-variables       2014_10_19_12_51_21-mutex-status1   2014_10_19_12_51_21-variables
2014_10_19_12_51_02-mysqladmin      2014_10_19_12_51_02-vmstat          2014_10_19_12_51_21-mysqladmin      2014_10_19_12_51_21-vmstat
2014_10_19_12_51_02-netstat         2014_10_19_12_51_02-vmstat-overall  2014_10_19_12_51_21-netstat         2014_10_19_12_51_21-vmstat-overall
</pre>
使用pt-sift来查看生成的报告:
<pre>
[root@cz pt-stalk]# pt-sift .

  2014_10_19_12_51_02  2014_10_19_12_51_21

Select a timestamp from the list [2014_10_19_12_51_21] 
======== z6 at 2014_10_19_12_51_21 DEFAULT (2 of 2) ========
--diskstats--
  #ts device    rd_s rd_avkb rd_mb_s rd_mrg rd_cnc   rd_rt    wr_s wr_avkb wr_mb_s wr_mrg wr_cnc   wr_rt busy in_prg    io_s  qtime stime
 {29} sda1       0.0     0.0     0.0     0%    0.0     0.0     4.7    27.1     0.1    85%    0.0     0.2   0%      0     4.7    0.1   0.1
 sda1  0% . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--vmstat--
 r b swpd     free   buff   cache si so bi  bo   in  cs us sy  id wa st
13 0    0 28597700 382308 1004200  0  0  0   0    0   0  0  0 100  0  0
 0 0    0 28597448 382308 1007972  0  0  0 122 1887 657  0  1  98  0  0
wa 0% . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--innodb--
    txns: 1xnot (0s)
    0 queries inside InnoDB, 0 queries in queue
    Main thread: flushing log, pending reads 0, writes 0, flush 0
    Log: lsn = 42061953781, chkp = 42061953781, chkp age = 0
    Threads are waiting at:
    Threads are waiting on:
--processlist--
    State
      5  
      2  NULL
      1  Waiting for next activation
    Command
      5  Sleep
      1  Query
      1  Killed
      1  Daemon
--stack traces--
    No stack trace file exists
--oprofile--
    No opreport file exists
</pre>
其它参数:
<pre>
--collect-gdb： 搜集MySQL线程相关的堆栈信息, 在非常繁忙的主机中频繁搜集gdb信息可能会引起MySQL崩溃, 该参数默认关闭;

--collect-oprofile： 搜集oprofile相关的信息, 该参数默认开启oprofile会话，详细可参考系统相关的oprofile文档；

--collect-strace： 搜集堆栈信息, 该参数不能和collect-gdb同时使用;

--collect-tcpdump： 如果指定了改参数, 则会开始tcpdump监听MySQL端口相关的流量；

--cycles：用于指定满足触发条件多少次才会进行数据搜集；

--dest：存放搜集信息的目录， 默认为/var/lib/pt-stalk, pt-stalk 默认删除指定目录下超过一定时间的文件(retention-time指定时间天数), 这里可能会误删我们指定的目录下的文件. --dest 参数的值要尽量设成单一的目录.

--function： 满足触发的参数信息, 可以指定status(show global status)和processlist(show processlist), 默认为status；

--plugin：函数相关的扩展, 不一定非要指定, 可用于扩展相关的需要的信息, 包括: before_stalk, before_collect, after_collect, after_collect_sleep, after_interval_sleep, after_stalk, 比如以下信息:
    before_collect() {
       touch /tmp/foo
    }
  在执行collect之前，会先指定before_collect扩展, 创建/tmp/foo文件;
</pre>