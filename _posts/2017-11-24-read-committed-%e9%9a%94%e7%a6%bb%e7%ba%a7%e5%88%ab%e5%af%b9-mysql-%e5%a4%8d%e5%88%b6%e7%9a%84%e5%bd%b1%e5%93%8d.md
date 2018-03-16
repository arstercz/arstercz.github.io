---
id: 901
title: read-committed 隔离级别对 MySQL 复制的影响
date: 2017-11-24T12:24:40+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=901
permalink: '/read-committed-%e9%9a%94%e7%a6%bb%e7%ba%a7%e5%88%ab%e5%af%b9-mysql-%e5%a4%8d%e5%88%b6%e7%9a%84%e5%bd%b1%e5%93%8d/'
categories:
  - bugs-report
  - database
tags:
  - replication
  - repl_discovery
  - Transaction
---
## read-committed 隔离级别对 MySQL 复制的影响

近期碰到了一个 mysql slave 正常接收 relay log, 但是不执行更新的情况, 更准确的说是不执行 row 格式的所有更新, DDL 和 statement 格式的都正常更新, 主从环境配置见下文.

#### 环境配置

```bash
OS:     CentOS release 6.7 (Final)
Kernel: 2.6.32-573.18.1.el6.x86_64
MySQL:  Percona-Server-5.5.33-rel31.1-566.Linux.x86_64
```

#### 主从环境

使用 [repl_discovery](https://github.com/arstercz/mysql_repl_discovery)检查如下:
```bash
# repl_discovery -h 10.0.21.7 -P 3308 -u monitor --askpass
Enter password : 
+-10.0.21.7:3308
version             5.5.33-rel31.1-log
server_id           2690331
has_gtid            Not Support
tx_isolation        READ-COMMITTED
binlog_enable       1
filter              binlog_ignore_db: information_schema,mysql,performance_schema,test; 
binlog_format       MIXED
max_packet          32MB
read_only           0
  +-10.0.21.17:3308
  version             5.5.33-rel31.1-log
  server_id           2362651
  has_gtid            Not Support
  tx_isolation        REPEATABLE-READ
  binlog_enable       1
  filter              replicate_ignore_db: information_schema,mysql,performance_schema,test; 
  binlog_format       MIXED
  max_packet          32MB
  read_only           1
  repl_check          OK
```

一般我们认为以下 3 种情况可能会引起 slave 不会更新 relay log:
```
1. 关闭了 replicate-same-server-id 选项, 并且两者的 server id 相同;
2. 使用了 replicate-do-db 等过滤;
3. 非默认隔离级别(REPEATABLE-READ);
```

第一种情况可能在环形复制的结构中会碰到, 不过现实中使用这种架构的不多; 第二种情况则相对较多, 操作人员没有按具体的[过滤规则](https://dev.mysql.com/doc/refman/5.5/en/replication-rules-db-options.html)操作, 则容易出现 slave 不执行更新的情况.

第三种情况则相对特殊些, 按照 [read-committed](https://dev.mysql.com/doc/refman/5.5/en/innodb-transaction-isolation-levels.html#isolevel_read-committed) 中的介绍:
```
If you use READ COMMITTED, you must use row-based binary logging.
```
因为`READ COMMITTED` 和 `REPEATABLE-READ` 事务级别下, 两者的加锁机制稍有不同(read-committed 下 InnoDB 仅对要更新或删除的行加锁), 所以会特别强调使用 `READ COMMITTED` 的时候必须用 row 格式复制.
 
当然我们的环境都使用了默认的配置 `REPEATABLE-READ`, 所以一开始并没有意识到 master 的事务隔离级别被改成了 `read-committed`, 进而一直在前两种情况排查, 以至我们在重新编译了对应 mysql 版本号的 debug 版本也没找到明显的线索. 

在发现 master 的事务隔离级别是 `read-committed` 后, 我们找到了类似的情况[bug-23051](https://bugs.mysql.com/bug.php?id=23051), 不同的是我们的版本为 5.5 版本, 且在测试环境下测试 MySQL 并未同 5.1 版本一样提出任何警告信息, 另外在 5.5.33 版本中也没有复现上面所描述的现象. 在重新以 `set global tx_isolation` 的方式在线调整 `master` 的隔离级别后, 并未解决此问题, 新加一个同版本的 slave 也未解决该问题. 不过重启 master 的 MySQL 实例后, 主从恢复正常, 这可能是重启 master 后改变了 binlog 中相关的锁模式. 另外 DDL 和 `statement`(在 MyISAM 引擎表插入记录会生成 statement 格式的 relay log) 在 sql_thread 解析的时候是放到单独的链表队列中的, row 格式的更新则是放到另一个链表队列中处理, 所以会出现我们上面描述的没有执行 row 格式的更新语句, 仅执行了 DDL 和 statement 相关的语句. 

参照 [is the read-committed isolation level safe with mixed binary](https://dba.stackexchange.com/questions/125809/mysql-is-the-read-committed-isolation-level-safe-with-mixed-binary-log-format), 我们看到[官方手册](https://dev.mysql.com/doc/refman/5.5/en/binary-log-setting.html)也对这种状况进行了说明: 
```
If you are using InnoDB tables and the transaction isolation level is READ COMMITTED or READ UNCOMMITTED, 
only row-based logging can be used. It is possible to change the logging format to STATEMENT, but doing 
so at runtime leads very rapidly to errors because InnoDB can no longer perform inserts.
```

从这点看, 可能是 `MIXED` 格式下 `row` 和 `statement` 都存在的情况引起的. 当然只是可能出现, 并不是一定会出现, 在实际的验证中我们确实没有复现这种情况. 基于此可以将这种问题当做隐含的 `bug`. 要避免这个问题可以选用下面的一种方式处理:
```
1. 使用 READ-COMMITTED 隔离级别的时候设置 binlog_format 为 row 模式(主从设置都一样);
2. 如果 binlog_format 为 statement 或 MIXED 模式, 确保程序没有使用 READ-COMMITTED 或 READ UNCOMMITTED 隔离级别;
3. 升级到最新的 5.5 分支版本(我们使用 Percona-Server-5.5.57 版本作为原来 master 的 slave 也没有复现该问题);
```
