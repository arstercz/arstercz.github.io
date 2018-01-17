---
id: 814
title: mydumper 和 mysqldump 对比使用
date: 2017-05-19T13:47:04+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=814
permalink: '/mydumper-%e5%92%8c-mysqldump-%e5%af%b9%e6%af%94%e4%bd%bf%e7%94%a8/'
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - mydumper
---
<h2>介绍</h2>

详细安装说明见: <a href="https://github.com/maxbube/mydumper">mydumper</a>

如果只是备份几张表或单个库, 相比 innobackup 而言, <code>mysqldump</code> 和 <code>mydumper</code> 更为方便, 不过 mydumper 增加了相对较多的特性, 比如多线程备份, 正则匹配备份, 分组和自检等功能. 另外 <code>mydumper</code> 和 <code>mysqldump</code> 本质上是一样的导出逻辑数据, 不支持在线热备 innodb. 当然我们也可以使用 innobackup 备份部分表数据, 但是它和 <code>mydumper</code> 和 <code>mysqldump</code> 不是一类备份方式, 所以下文只测试 mydumper 和 mysqldump 之间的使用.

<h2>mydumper 导出</h2>

使用 mydumper 工具以 8 个线程导出 test(9.4G) 的数据, 并压缩, 如下所示:

<pre><code>mydumper -B test --regex 'test.*' -c -e -G -E -R --use-savepoints -h 10.0.21.5 -u root -P 3301 -p xxxxxx -t 8 -o /data/mysql_bak/
</code></pre>

在目录 <code>/data/mysql_bak</code> 里, 库中的每个表都保存为表定义和数据两个文件.
整体执行时间如下, 一共耗时 123s

<pre><code># cat metadata 
Started dump at: 2017-05-19 10:48:00
SHOW MASTER STATUS:
    Log: mysql-bin.000406
    Pos: 2165426
    GTID:(null)

SHOW SLAVE STATUS:
    Host: 10.144.127.4
    Log: mysql-bin.000419
    Pos: 506000361
    GTID:(null)

Finished dump at: 2017-05-19 10:50:03
</code></pre>

<h2>mysqldump 导出</h2>

使用默认的 mysqldump 工具导出该库并压缩, 如下所示:

<pre><code># time mysqldump -B test -E -R -h 10.0.21.5 -u root -P 3301 -p | gzip &gt;/data/test.sql.gz
Enter password: 

real    3m19.805s
user    4m47.334s
sys 0m10.395s
</code></pre>

real 一行显示 mysqldump 整个运行的时间为 199.8s

<h2>总结</h2>

整体上看, 由于数据不多, mysqldump 和 mydumper 时间相差并不大, 大多的时间都消耗在数据传输层面, 如果库足够大的话, mydumper 的优势就能体现出来. 另外低版本的 mydumper 由于高版本 MySQL 语法的变更, 会存在导出错误的问题, 比如出现下面错误:

<pre><code>** (mydumper:18758): CRITICAL **: Couldn't execute 'SET OPTION SQL_QUOTE_SHOW_CREATE=1': You have an error in your SQL syntax; 
check the manual that corresponds to your MySQL server version for the right syntax to use near 'OPTION SQL_QUOTE_SHOW_CREATE=1' 
at line 1 (1064)
</code></pre>

处理这种问题可以使用高版本的 <code>mydumper</code>, 如果高版本还有这个问题可以参考 github 官方代码做相应代码修改.