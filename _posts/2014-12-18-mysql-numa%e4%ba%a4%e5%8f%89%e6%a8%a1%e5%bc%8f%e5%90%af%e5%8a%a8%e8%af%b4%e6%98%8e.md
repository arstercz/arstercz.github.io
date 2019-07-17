---
id: 456
title: MySQL numa交叉模式启动说明
date: 2014-12-18T12:26:34+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=456
permalink: '/mysql-numa%e4%ba%a4%e5%8f%89%e6%a8%a1%e5%bc%8f%e5%90%af%e5%8a%a8%e8%af%b4%e6%98%8e/'
tagline_text_field:
  - ""
dsq_thread_id:
  - "3468414940"
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - MySQL
  - numa
---
numa交叉模式说明:
<a href="http://www.percona.com/doc/percona-server/5.5/performance/innodb_numa_support.html">http://www.percona.com/doc/percona-server/5.5/performance/innodb_numa_support.html</a>

db01: 开启numa interleave; RAM 64G;
db02: 关闭numa interleave; RAM 64G;
两台db均分配48G内存buffer pool; Percona Server 5.5.33版本;
<!--more-->


mysqld_safe部分配置增加numa参数:
<pre>
#NUMA support
numa_interleave = 1
innodb_buffer_pool_populate = 1
flush_caches=1
</pre>

innodb_buffer_pool_populate: 如果服务器为NUMA架构，且内存的选择策略为selected, 在buffer pool分配的内存大小大于节点的可用内存时,系统则会进行swap交换操作,即便其它节点还有可用的内存。该选项功能引用自Twitter's的MySQL补丁, 启用的该选项在buffer cache还是clean的时候(即空机) 启动实例后为InnoDB进行预分配页空间以强制决定NUMA分配的策略;
<a href="http://www.ibm.com/developerworks/cn/linux/l-numa/">http://www.ibm.com/developerworks/cn/linux/l-numa/</a>

swap对numa架构的影响见:
<a href="http://blog.jcole.us/2010/09/28/mysql-swap-insanity-and-the-numa-architecture/">http://blog.jcole.us/2010/09/28/mysql-swap-insanity-and-the-numa-architecture/</a>

db01:
<pre>
available: 2 nodes (0-1)
node 0 cpus: 0 2 4 6 8 10 12 14 16 18 20 22
node 0 size: 32722 MB
node 0 free: 16432 MB
node 1 cpus: 1 3 5 7 9 11 13 15 17 19 21 23
node 1 size: 32768 MB
node 1 free: 19543 MB
node distances:
node   0   1 
  0:  10  20 
  1:  20  10
</pre>

db02:
<pre>
available: 2 nodes (0-1)
node 0 cpus: 0 2 4 6 8 10 12 14 16 18 20 22
node 0 size: 32722 MB
node 0 free: 27778 MB
node 1 cpus: 1 3 5 7 9 11 13 15 17 19 21 23
node 1 size: 32768 MB
node 1 free: 31067 MB
node distances:
node   0   1 
  0:  10  20 
  1:  20  10
</pre>


可以看到 db01启用interleave模式后, node1, node2同时对外服务, 尽管对于内存而言存在本地和远端模式的访问, 但比起swap操作, 开销更少;
db02主机的node1节点是空闲的; 