---
layout: post
title: "MySQL 备份引起的主从切换错误"
tags: [mysql]
comments: true
---

## mysqldump 备份说明

在备份 slave 的时候, 以下的 dump-slave 选项, 在执行备份 slave 的时候, 会触发 `FLUSH TABLES` 的执行:
> 严格来讲, 只要没有指定 master-data, 都会执行 `FLUSH TABLES` 语句
```
mysqldum --dump-slave=2 ......
```

对应 mysqldump.c 代码:
```c
# percona-mysql-5.7.28-31
6253 static int do_flush_tables_read_lock(MYSQL *mysql_con)
6254 {
6255   /*
6256     We do first a FLUSH TABLES. If a long update is running, the FLUSH TABLES
6257     will wait but will not stall the whole mysqld, and when the long update is
6258     done the FLUSH TABLES WITH READ LOCK will start and succeed quickly. So,
6259     FLUSH TABLES is to lower the probability of a stage where both mysqldump
6260     and most client connections are stalled. Of course, if a second long
6261     update starts between the two FLUSHes, we have that bad stall.
6262   */
6263   return
6264     ( mysql_query_with_error_report(mysql_con, 0,
6265                                     ((opt_master_data != 0) ?
6266                                         "FLUSH /*!40101 LOCAL */ TABLES" :
6267                                         "FLUSH TABLES")) ||
6268       mysql_query_with_error_report(mysql_con, 0,
6269                                     "FLUSH TABLES WITH READ LOCK") );
6270 }
```

而这类 [flush, optimize, repair 等语句会写到 binary logs](https://dev.mysql.com/doc/refman/5.7/en/replication-features-flush.html) 里, 如下所示:

```
The FLUSH TABLES, ANALYZE TABLE, OPTIMIZE TABLE, and REPAIR TABLE statements are written to the
binary log and thus replicated to replicas. This is not normally a problem because these 
statements do not modify table data.

However, this behavior can cause difficulties under certain circumstances.
```

对应到 binlog 中如下所示:
```sql
#240911  3:10:14 server id 2821353  end_log_pos 391851401 CRC32 0x2c49e727      Query   thread_id=577892        exec_time=0     error_code=0
SET TIMESTAMP=1725995414/*!*/;
SET @@session.sql_mode=0/*!*/;
/*!\C utf8mb4 *//*!*/;
SET @@session.character_set_client=45,@@session.collation_connection=45,@@session.collation_server=45/*!*/;
FLUSH TABLES
```

如果 MySQL 主从开启了 GTID, 这就意味着 slave 做了额外的更新操作, 进而引起主从切换异常, 导致别的实例在执行 `change master` 的时候出现下面的错误:
```
Got fatal error 1236 from master when reading data from binary log: 'The slave is connecting using CHANGE MASTER TO MASTER_AUTO_POSITION = 1, but the mast
er has purged binary logs containing GTIDs that the slave requires.'
```

## 如何避免

对于 flush 语句来讲, 以下语句会有不同的行为:

| flush 语句 | binlog 是否记录 |
| :- | :-: |
| FLUSH TABLES | 是 |
| FLUSH TABLES WITH READ LOCK | 否 |
| FLUSH /*!40101 LOCAL */ TABLES | 否 |
| FLUSH NO_WRITE_TO_BINLOG TABLES | 否 |

所以如果是工具脚本等可以使用下面两种语法来避免此类问题. 如果是 `mysqldump` 则需要考虑以下说明:
```
1. 考虑 xtrabackup 方式备份 slave;

2. 如果一定要 mysqldump 备份 slave(假定 slave 开启了 binlog):
     1) 可以考虑设置 master-data 参数备份;
     2) 如果一定要设置 dump-slave 参数, 那就要保证在切换时, 之前 slave 执行时所有 flush 相关的 binlog 文件都存在;
     3) 或者 MySQL 没有开启 gtid, 虽然会写数据, 但不影响主从切换;

3. 如果 1，2 都不能满足, 只能 mysqldump 备份 master 避免此类问题;
```
