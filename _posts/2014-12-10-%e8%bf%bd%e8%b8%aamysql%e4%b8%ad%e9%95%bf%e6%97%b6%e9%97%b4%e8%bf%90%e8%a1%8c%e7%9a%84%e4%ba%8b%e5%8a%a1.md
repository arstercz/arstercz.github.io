---
id: 451
title: 追踪MySQL中长时间运行的事务
date: 2014-12-10T18:42:50+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=451
permalink: '/%e8%bf%bd%e8%b8%aamysql%e4%b8%ad%e9%95%bf%e6%97%b6%e9%97%b4%e8%bf%90%e8%a1%8c%e7%9a%84%e4%ba%8b%e5%8a%a1/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3468419661"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - innodb
  - MySQL
  - Transaction
---
<a href="https://github.com/yoshinorim/MySlowTranCapture">https://github.com/yoshinorim/MySlowTranCapture</a>
获取执行时间超过<n> milliseconds事务语句的工具;

很多时候我们需要追踪事务的执行情况以判定应用程序的操作行为, 比如启了事务, 却忘记提交而造成InnoDB事务的History List不断增大. 这是很复杂的场景, 因为很难找到一个有效的方式来识别是那种sql引起的这种问题, 追踪一个长时间运行的事务不像记录一条慢查询语句, 比如执行以下事务语句:
<pre>
ysql root@[localhost:s3306 test] > begin;
Query OK, 0 rows affected (0.00 sec)

mysql root@[localhost:s3306 test] > insert into b1 values('a','a');
Query OK, 1 row affected (0.00 sec)

mysql root@[localhost:s3306 test] > commit;
Query OK, 0 rows affected (0.00 sec)
</pre>
<!--more-->

这条事务可能在执行insert后过了10s才执行commit提交, 但insert语句实际上却是非常快的执行完成,这种情况不会记录到slow log中, 所以传统的分析慢查询的方法不适用于该场景.

如果开启general log, 所有的query会会记录, 不过在读写频繁的情况下这种方式可能对DB性能产生影响, 记录的日志文件也会增长的很大, 不利于分析统计.另外事务的执行时间和thread信息不会记录到general log中, 所以单纯的分析general log并不能达到追踪的目的;

binlog更不用说了, 它不会记录select相关的记录.

SHOW ENGINE INNODB STATUS可以打印事务的信息, 但没有哪条SQL持有锁的信息, 在执行时间方面也没有更详细的描述.

MySlowTranCapture工具则通过抓取MySQL Server端的流量以下步骤获取需要的事务信息:
<pre>
1. 检查事务的开始时间t1;
2. 将事务相关的语句放到内存队列中;
3. 检查事务的结束时间t2;
4. 如果 t2 - t1 超过了指定的 <n> milliseconds, 则输出语句;
5. 删除队列中的语句;
</pre>

比如:
<pre>
From 10.0.0.1:51745
2014/12/10 17:27:06.871938 ->
begin 
2014/12/10 17:27:06.872041 <-
GOT_OK 
2014/12/10 17:27:09.314936 ->
insert into b1 values('a','a') 
2014/12/10 17:27:09.315149 <-
GOT_OK 
2014/12/10 17:27:19.906396 ->
select * from b1 
2014/12/10 17:27:19.906569 <-
GOT_RES 
2014/12/10 17:27:23.130841 ->
commit
</pre>
可以看到从10.0.0.1过来的事务执行时间较长,整条事务共执行了17s左右. 如果要分析应用程序是否忘记提交可以通过工具的输出来对比 begin(start transaction) 和 commit的数量, commit应该略少于begin或start transaction的数量, 因为很多语句,比如alter table, creat, drop语句都会有一个隐含的提交, 如果二者数量相差过大, 极有可能是因为应用程序未提交引起的.

<a href="http://yoshinorimatsunobu.blogspot.com/2011/04/tracking-long-running-transactions-in.html">http://yoshinorimatsunobu.blogspot.com/2011/04/tracking-long-running-transactions-in.html</a>

该工具依赖: libpcap, libpcap-devel, boost, and boost-devel

选项说明:
<pre>
Usage: smtc -t <alert_millis> -i <interface> -f <filter_rule> -o (set if using older MySQL protocols)
  -i "interface name" to listen to specific NIC, such as -i eth0
  -f "filtering rules" to listen to specific IP addresses/ports, such as -f "tcp port 3301"
  -t milliseconds to change printing criteria
  -o when your MySQL server speaks old MySQL protocols
</pre>

目前的缺陷包括:
<pre>
1. 不支持DDL相关的语句引起的隐式提交.
2. 不支持MySQL Server端的Prepared Statement.
3. 依赖libpcap抓包, 所以会存在丢包的可能, 不能100%的抓取到需要的数据.
</pre>

类似工具:
mysqlpcap 是一个基于 pcap 用于观察 sql 语句执行情况的工具
<a href="https://github.com/hoterran/tcpcollect">https://github.com/hoterran/tcpcollect</a>