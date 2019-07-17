---
id: 641
title: PERCOBA XTRADB CLUSTER介绍及使用(五)
date: 2016-05-09T12:07:18+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=641
permalink: '/percoba-xtradb-cluster%e4%bb%8b%e7%bb%8d%e5%8f%8a%e4%bd%bf%e7%94%a8%e4%ba%94/'
ultimate_sidebarlayout:
  - default
dsq_thread_id:
  - "4810959795"
categories:
  - database
tags:
  - XtraDB
---
Galera cluster 限制

Galera cluster 由于自身设计的原因存在几个限制, 开发者或 DBA 应该需要注意在标准的 MySQL Server 中(包括 MariaDB 和 Percona) 一些特性在 Galera cluster 中并不可用.

1. Galera cluster 只能运行在 Linux/Unix 系统中, Windows Server 并不支持, 二进制版本不支持 FreeBSD, Mac OS 和 Solaris.

2. Galera 是被设计为和 InnoDB 引擎使用的, MyISAM 引擎还在实现测试阶段, 由 wsrep_replicate_myisam 参数控制, 默认为 OFF. Galera 团队也不建议在生产环境中启用该参数. 对于 mysql.* 中的表, Galera 支持 create user, grant .. 等 DDL 语句, 但不支持使用 insert, delete 等创建和删除用户.两者之外的其它存储引擎都不支持.

3. binary log 必须启用, 而且 binlog_format 也必须设置为 ROW, Galera 不支持 statement-based 和 mixed 格式的复制. 不要使用 binlog-do-db 和 binlog-ignore-db, Galera 只支持这两个选项的 DML 语句, 不支持 DDL 语句.

4. character_set_server 的值不支持字符集  UTF-16, UTF-32 以及 UCS-2, 当 SST 使用 rsync 方式时, 设置上述的编码可能会引起 Server 崩溃.

5. 表必须有主键. 如果没有主键, 一些奇怪的问题就会发生, 比如不支持 DELETE, 不支持 XA 事务, InnoDB 的两次写(double write) 缓存会被禁用, 也不会支持 query cache 等. 

6. 不支持下面显示的指定锁的语句, 因为它们和多主复制冲突: SELECT ... FOR UPDATE, SELECT ... LOCK IN SHARE MODE, LOCK TABLES, FLUSH TABLES ... FOR EXPORT, GET_LOCK() 和 RELEASE_LOCK()等, 基于此特性, Galera 支持 MyISAM 的需求就特别少.

7. 不支持将 query log 写到系统表中, 只能指定到 FILE.

8. 不支持 XA 事务;

9. Galera 本身没有显示的限制事务大小, 特别大的事务会影响节点的性能. wsrep_max_ws_rows 和 wsrep_max_ws_size 系统变量可以限制事务的大小(128K 行记录 和 1G 事务大小), 后续的版本可能会加大限制的值.


参考: 
   <a href="http://galeracluster.com/documentation-webpages/limitations.html">http://galeracluster.com/documentation-webpages/limitations.html</a>
   <a href="https://mariadb.com/kb/en/mariadb/mariadb-galera-cluster-known-limitations/">https://mariadb.com/kb/en/mariadb/mariadb-galera-cluster-known-limitations/</a>