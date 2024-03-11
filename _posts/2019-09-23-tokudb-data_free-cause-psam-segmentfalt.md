---
layout: post
title: "tokudb 表信息 data_free 引起 psam 崩溃问题处理"
tags: [tokudb, mysql]
comments: false
---

## 问题说明

在之前的文章 [使用 percona-server-auto-manager(psam 缩写) 管理数据库]({{ site.baseurl }}/%e4%bd%bf%e7%94%a8-percona-server-auto-manager-%e7%ae%a1%e7%90%86%e6%95%b0%e6%8d%ae%e5%ba%93/) 中, 我们提到了可以通过 `psam` 工具来管理线上的 MySQL 操作, 其中的 `sql 记录` 和 `sql 过滤` 等特性非常适合在安全审计方面存在需求的管理员. 不过最近在使用该工具管理 `TokuDB` 表的时候出现了如下段错误:

```sql
partition_truncate.sh: line 38: 89891 Segmentation fault      $mysqlcmd -h $HOST -P $PORT -D $DB -u root -p$PAS --skip-sql-filter -Bse "$1"
```
该段错误仅在通过 `psam` 工具执行 `ALTER ..` 语句的时候出现.

## 分析说明

### 通过 `psam` debug 版本分析查看

通过 debug 版本的 `mysql` 来看, `psam` 在用户执行 `ALTER ..` 语句的时候会先从 `information_schema.tables` 中读取对应表的元数据信息以便获取对应表的大小. 如下所示, `psam` 在获取对应表大小的时候出现整型溢出的错误:
```bash
# mysql -h xxxx --debug=d:t:0,/tmp/client.trace --skip-sql-filter -Bse "alter table table_data_invoke truncate partition p3"
......
| >find_command
| | enter: name: 'alter table table_data_invoke truncate partition p3'
| <find_command 2390
......
| >mysql_real_query
| | enter: handle: 0x9f55e0
| | query: Query = 'select round(sum(DATA_LENGTH+INDEX_LENGTH+DATA_FREE)/1024/1024)                       as size from information_schema.tables                       where table_schema = 'data_invoke' and table_name = 'table_data_invoke''
| | >mysql_send_query
......
| | | <vio_read_buff 207
| | | error: Got error: 1690/22003 (BIGINT UNSIGNED value is out of range in '((`information_schema`.`tables`.`DATA_LENGTH` + `information_schema`.`tables`.`INDEX_LENGTH`) + `information_schema`.`tables`.`DATA_FREE`)')
| | <cli_read_rows 1553
......
```

可以看到 `select round ...` 语句在执行的时候出现了结果值大于 `BIGINT UNSIGNED(18446744073709551615)` 的错误, 进而造成 `psam` 异常. 查看对应表信息如下:
```sql
> select * from tables where table_name = 'table_data_invoke'\G 
*************************** 1. row ***************************
  TABLE_CATALOG: def
   TABLE_SCHEMA: data_invoke
     TABLE_NAME: table_data_invoke
     TABLE_TYPE: BASE TABLE
         ENGINE: TokuDB
        VERSION: 10
     ROW_FORMAT: tokudb_zlib
     TABLE_ROWS: 47021349
 AVG_ROW_LENGTH: 389
    DATA_LENGTH: 18309427090
MAX_DATA_LENGTH: 0
   INDEX_LENGTH: 14801570521
      DATA_FREE: 18446744050450745461
 AUTO_INCREMENT: NULL
    CREATE_TIME: 2019-08-14 08:03:09
    UPDATE_TIME: 2019-09-23 02:53:31
     CHECK_TIME: NULL
TABLE_COLLATION: utf8_general_ci
       CHECKSUM: NULL
 CREATE_OPTIONS: partitioned
  TABLE_COMMENT: 
```
可以看到该表为 `TokuDB` 引擎, 其中的 `DATA_FREE` 非常大, 在进行 `sum(DATA_LENGTH+INDEX_LENGTH+DATA_FREE)` 的时候出现了无符号整形溢出的错误. 参考 [percona-PS5704](https://jira.percona.com/browse/PS-5704), 从官方的解释来看, `DATA_FREE` 特别大是由 TokuDB 特性造成的, 归咎于 `FT 索引`的 `message` 特性, `DATA_FREE` 只是一个通过如下公式得到的估计值, 不是准确值, 实际使用中应该忽略该信息:
```c
DATA_FREE = 18446744073709551615(MAX BIGINT UNSIGNED) - Data_length - Index_length
```

### 通过 gdb 查看 `psam` 运行时的错误

如下所示, 通过 gdb 方式运行 mysql 命令, 在执行 `alter` 语句的时候出现同样的错误:

```c
# gdb -ex run -ex bt --args mysql -h xxxxxx --skip-sql-filter data_invoke -p 
GNU gdb (GDB) Red Hat Enterprise Linux 7.6.1-114.el7
Copyright (C) 2013 Free Software Foundation, Inc.
......
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 696428
.....
mysql root@[xxxx:3306 data_invoke ro] > alter table table_data_invoke truncate partition p3;

Program received signal SIGSEGV, Segmentation fault.
0x000000000041b8f3 in mysql_fetch_row (res=0x0) at /usr/local/src/percona-server-auto-manager/sql-common/client.c:4639
4639      if (!res->data)
#0  0x000000000041b8f3 in mysql_fetch_row (res=0x0) at /usr/local/src/percona-server-auto-manager/sql-common/client.c:4639
#1  0x000000000040a38b in com_go (buffer=0x9f5ba0 <glob_buffer>, line=0x0) at /usr/local/src/percona-server-auto-manager/client/mysql.cc:3548
#2  0x0000000000407f84 in add_line (buffer=..., line=0xb6cbe0 "alter table table_data_invoke truncate partition p3;", line_length=52, in_string=0x7fffffffe197 "", ml_comment=0x7fffffffe196, truncated=false)
    at /usr/local/src/percona-server-auto-manager/client/mysql.cc:2575
#3  0x000000000040717e in read_and_execute (interactive=true) at /usr/local/src/percona-server-auto-manager/client/mysql.cc:2242
#4  0x0000000000405f68 in main (argc=11, argv=0x9fd2e8) at /usr/local/src/percona-server-auto-manager/client/mysql.cc:1420
Missing separate debuginfos, use: debuginfo-install glibc-2.17-260.el7.x86_64 libgcc-4.8.5-36.el7.x86_64 libstdc++-4.8.5-36.el7.x86_64 ncurses-libs-5.9-14.20130511.el7_4.x86_64 readline-6.2-10.el7.x86_64 snoopy-2.4.6-1.el7.centos.x86_64

```

可以看到 `src/client/mysql.cc` 3548 行即为出错的代码:
```c
3530     sprintf(sqlSize, "select round(sum(DATA_LENGTH+INDEX_LENGTH+DATA_FREE)/1024/1024) \
3531                       as size from information_schema.tables \
3532                       where table_schema = '%s' and table_name = '%s'",
3533             dbname, tablename);
3534     if (mysql_query(&mysql, sqlSize))
3535     {
3536       fprintf(stderr, "\t[WARN] - cann't get %s.%s size\n",
3537               dbname, tablename);
3538       return 0;
3539     }
3540     MYSQL_RES *result_msg = mysql_store_result(&mysql);
3541     if (result_msg == NULL) {
3542       //fprintf(stderr, "\t[WARN] - cann't find %s.%s\n",
3543       //        mysql.db, TableName);
3544       //return 0;
3545     }
3546     int tableSize = 0;
3547     MYSQL_ROW row_result;
3548     while ((row_result = mysql_fetch_row(result_msg)))
3549     {
3550       if (row_result[0] == NULL)
......
```
因为 `select round ...` 执行错误, 引起执行 `mysql_fetch_row` 函数的时候出现错误. 另外从 [C-API mysql-query](https://dev.mysql.com/doc/refman/8.0/en/mysql-query.html) 来看, `mysql_query` 仅在出现错误的时候返回非 0, 不过从笔者的测试来看, 该函数仅在 **sql 执行错误** 的时候返回非 0. 对于上述的 sql 语句, 本身没有语法错误, 可以正常执行, 只是最终的结果出现了整型溢出, 这种情况函数的返回值依旧为 0, 不过 `mysql_errno` 和 `mysql_error` 已经被修改为适当的错误信息. 鉴于这种原因, 我们修改为通过 `result_msg` 判断上述的 sql 是否执行成功, 具体参考: [git-commit-0217bbd](https://github.com/arstercz/percona-server-auto-manager/commit/0217bbd1e0e57b3ba785978250ab2ad5c2170cca).

## 总结说明

从上述的分析来看, 引起段错误的原因主要为 TokuDB 的特性, 造成 TokuDB 表 `DATA_FREE` 的属性特别大, 在实际的使用中, 我们应该忽略 TokuDB 表的 `DATA_FREE` 属性, 仅通过 `DATA_LENGTH + INDEX_LENGTH` 计算表的大小. `psam` 在后续的使用中会尽量遵循官方版本的行为, 在出现异常的时候仅输出相应的错误. 大家在使用 `psam` 碰到问题的时候可以提交问题到 [github-psam](https://github.com/arstercz/percona-server-auto-manager) 方便笔者及时更新. 更多的 TokuDB 问题可以参考文章 [TokuDB 使用问题汇总]{{ site.baseurl }}/tokudb-%e4%bd%bf%e7%94%a8%e9%97%ae%e9%a2%98%e6%b1%87%e6%80%bb/).
