---
id: 294
title: top 10 percona toolkit tools (一)
date: 2014-08-28T14:25:21+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=294
permalink: '/top-10-percona-toolkit-tools-%e4%b8%80/'
dsq_thread_id:
  - "3568713322"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - percona
tags:
  - percona
  - tool
---
Manual page: <a href="http://www.percona.com/doc/percona-toolkit/2.2/"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/</font></a>

<strong>介绍</strong>
percona toolkit是针对MySQL, Percona Server和MariaDB的一套命令工具集, 包括搜集统计信息, 在线更改表结构, 归档数据等等方面; 其是由Percona( <a href="http://www.percona.com/"><font color="green">http://www.percona.com/</font></a> )公司维护和开发,且对外开源(perl|shell)。对于DBA来讲， 熟悉这些工具可以极大方便的处理DB相关的工作和任务。

toolkit中的命令集合随版本的更新而出现少许变化, 本文以笔者的percona-toolkit-2.1.5-1版本说明, 目前该版本共计36个工具, 本文介绍最常用的10个命令,包括:
<!--more-->


<pre>
 1. pt-archiver
 2. pt-duplicate-key-checkers
 3. pt-show-grants
 4. pt-mysql-summary
 5. pt-summary
 6. pt-online-schema-change
 7. pt-query-digest
 8. pt-stalk
 9. pt-table-checksum
10. pt-table-sync
</pre>

<strong>使用</strong>
1. pt-archiver
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-archiver.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-archiver.html</font></a>
归档表数据: 对于一个大表尤其是更新频繁的表来讲, 如果要归档或清理表中的数据需要考虑到执行时间和锁的问题; 直接delete或select大范围的记录可能会占有长时间的锁, 更新频繁的话可能引起线程吃满的问题; pt-archiver采用分片(nibbles records)的方式，即一次取一点(chunk size指定)记录的方式进行归档; 这里的归档分两种方式: (1)清理表记录; 可以一点点清理过期或不用的记录, 但是清理完成后需要管理员操作释放表空间(也可以pt-online-schema-change操作,见下),也可以指定--optimize选项,但optimize对大表而言可能需要较长的时间, 同样会对表加较长时间的锁 ; (2)转移记录; 即将A主机表的记录移到B主机中的表,表的结构需要一致。
如下:
清理本地数据库test.user_log的id<=10000000数据记录, where条件指定了要清理的范围,pt-archiver分组来进行删除
<pre>
pt-archiver --source h=127.0.0.1,D=test,t=user_log --purge  --where 'id <= 10000000' --limit 3000 --txn-size 3000 --statistics --ask-pass
</pre>
将本地user_log的记录以1000行每次的行记录大小发送到10.1.1.2的user_log表中,即select ... from source.user_log和insert ... into dest.user_log, limit值越小, 查询时对源表的影响越小。--no-delete不删除源表的记录。
<pre>
pt-archiver --why-quit --source h=127.0.0.1,D=test,t=user_log --dest h=10.1.1.2,D=test,t=user_log \
--where 'id < 10000001' --limit 1000  --txn-size 100 --no-delete --statistics
</pre>
其它参数:
<pre>
--max-lag： 如果给定了--check-slave-lag选项，则slave延迟超过1s(默认的max-lag)的时候, pt-archiver不在执行,进入sleep状态;
--low-priority-[insert|delete]: 低优先级插入和删除;
--limit： 分组行记录的大小, 默认为1;
--dry-run: 只打印queries语句;
--txn-size: 事务语句中记录的行数目大小;
--set-vars: 设置MySQL变量参数;
</pre>

2. pt-duplicate-key-checkers
<a href="http://www.percona.com/doc/percona-toolkit/2.2/pt-duplicate-key-checker.html"><font color="green">http://www.percona.com/doc/percona-toolkit/2.2/pt-duplicate-key-checker.html</font></a>
检测冗余索引: 可能由于不太了解索引相关的信息(比如单列索引于前缀索引)，开发人员或管理员会创建多余的索引; 又或者测试和线上环境的表结构有所差异，而造成了多余索引的创建; 比如下面的索引:
<pre>
Key definitions:
  KEY `emp_no` (`emp_no`),
  PRIMARY KEY (`emp_no`,`from_date`)
</pre>
对于张更新频繁的表, 因为引擎需要维护索引组织的原因，过多的索引意味着过多的性能开销, 空间资源也会有一定影响。从上面的示例来看前缀索引(PRIMARY KEY)等同于emp_no索引, 所以emp_no可以清理掉;
pt-duplicate-key-checkers工具可以检测指定表的索引情况，并打印出清楚冗余索引的SQL;
比如:
(root:#) # pt-duplicate-key-checker h=127.0.0.1,u=root,P=3306,p=XXXXXX,D=test
<pre>
# ########################################################################
# employees.titles                                                        
# ########################################################################

# emp_no is a left-prefix of PRIMARY
# Key definitions:
#   KEY `emp_no` (`emp_no`),
#   PRIMARY KEY (`emp_no`,`title`,`from_date`),
# Column types:
#	  `emp_no` int(11) not null
#	  `title` varchar(50) not null
#	  `from_date` date not null
# To remove this duplicate index, execute:
ALTER TABLE `employees`.`titles` DROP INDEX `emp_no`;
</pre>
其它参数:
<pre>
--[no]sql: 是否打印出ALTER TABLE .. DROP INDEX相关的语句, 默认打印;
--[no]summary: 是否打印汇总信息，默认打印;
--engine: 仅检测指定引擎的表;
</pre>