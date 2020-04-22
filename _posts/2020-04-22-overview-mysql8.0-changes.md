---
layout: post
title: "MySQL 8.0 特性概览"
tags: [MySQL, feature]
comments: false
---

MySQL `8.0` 版本比之 `5.7` 做了很大的变化, 比较明显的主要有去掉了查询缓存, 密码验证方式变更, 默认编码变更等方面, 部分特性随着 8.0 最新版的发布也会存在小幅度的改变, 更多变化可以参考 [what-is-new-in-mysql8.0](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/mysql-nutshell.html#mysql-nutshell-removals) 了解更多. 如果是从 `5.7` 升级到 `8.0` 可以参考 [upgrading-from-previous-series.html](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/upgrading-from-previous-series.html) 了解更多的不同. 下面则主要介绍 MySQL 常用特性的一些变化.

* [常用参数变更](#常用参数变更)
* [X plugin](#X-plugin)
* [binlog 相关](#binlog-相关)
* [权限与密码](#权限与密码)
* [日志设置](#日志设置)
* [表变更](#表变更)
* [SQL 语法变更](#SQL-语法变更)
* [索引变更](#索引变更)
* [编码](#编码)
* [时区](#时区)
* [初始化与启动](#初始化与启动)
* [监控](#监控)
* [mysqldump 备份](#mysqldump-备份)
* [innodb 变更](innodb-变更)
* [主从复制](主从复制)


## 常用参数变更

#### 弃用以下参数:
```
# variables
innodb_stats_sample_pages
innodb_locks_unsafe_for_binlog
innodb_file_format   
innodb_file_format_check
innodb_file_format_max
innodb_large_prefix
ignore_builtin_innodb
skip-symbolic-links  # 默认即 skip-symbolic-links.
sync_frm             # 8.0 版本去掉了 .frm 文件, 内置在 ibd 文件中
sql_log_bin          # 仅支持会话级别设置
query_cache_xxx      # 缓存相关的系统变量
metadata_locks_cache_size
metadata_locks_hash_instances
date_format
datetime_format
time_format
max_tmp_tables

# status
Qcache_xxx_xxxx      # 缓存相关的状态参数
```

**备注:** 8.0 版本废弃了 query cache 特性


#### 参数变更:

```
expire-logs-days  =>  binlog_expire_logs_seconds # 替换 expire-logs-days
tx_isolation      =>  transaction_isolation
tx_read_only      =>  transaction_read_only
innodb_undo_logs  =>  innodb_rollback_segments
have_query_cache  = no      # 永远为 NO
```

#### information_schema 变更

```
INNODB_LOCKS      =>  data_locks
INNODB_LOCK_WAITS => data_lock_waits
```

## X plugin

`X plugin` 主要用于增强 `MySQL document` 的特性, 在 5.7 中为可选项, 需要单独安装插件, 在 8.0 中已经是默认开启, 可以设置 `xplugin=off` 禁用.

更多见:

[x-plugin](https://dev.mysql.com/doc/refman/8.0/en/x-plugin.html)   
[understanding-mysql-x-all-flavors](https://www.percona.com/blog/2019/01/07/understanding-mysql-x-all-flavors/)   

## binlog 相关

#### binlog 过期设置

expire-logs-days 后续可能废弃, 使用 binlog_expire_logs_seconds 进行设置, 默认 30 天. 

#### binlog 查看

通过 mysqlbinlog 工具查看, 额外指定 `--base64-output` 参数避免解析乱码:
```
mysqlbinlog --verbose --base64-output=decode-rows mysql-bin.0000xx
```

binlog 头信息中增加了一些时间及版本信息:
```
# original_commit_timestamp=1587435300248124 (2020-04-21 10:15:00.248124 CST)
# immediate_commit_timestamp=1587435300248124 (2020-04-21 10:15:00.248124 CST)
/*!80001 SET @@session.original_commit_timestamp=1587435300248124*//*!*/;
/*!80014 SET @@session.original_server_version=80019*//*!*/;
/*!80014 SET @@session.immediate_server_version=80019*//*!*/;
```

## 权限与密码

#### 权限

- 新版可能会废弃 SUPER 权限, 更多见 [dynamic-privileges-migration-from-super](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/privileges-provided.html#dynamic-privileges-migration-from-super), 如果需要管理 slave, 可以赋予  REPLICATION_SLAVE_ADMIN 权限;
- 增加角色设置, 不同用户可以分配不同的角色连接数据库, 更多见 [create-role](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/create-role.html);
- 默认加密插件变更为 caching_sha2_password;

更多权限见 [8.0-privileges-provided](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/privileges-provided.html).  

#### 密码

8.0 中默认的密码以 caching_sha2_password 插件加密, 不兼容 8.0 以下的版本. 各编程语言的驱动需要查看官方信息确定. 可以对单个用户指定以前的 `mysql_native_password` 认证插件.
```
mysql > show global variables like '%auth%plugin%';                            
+-------------------------------+-----------------------+
| Variable_name                 | Value                 |
+-------------------------------+-----------------------+
| default_authentication_plugin | caching_sha2_password |
+-------------------------------+-----------------------+

mysql > alter user 'user'@'xxx' identified width mysql_native_password by 'pass';
```

如下所示, 默认低版本连接出现的错误:
```
# mysql -h infodb6 -P 3397 -u root -p
Enter password: 
ERROR 2059 (HY000): Authentication plugin 'caching_sha2_password' cannot be loaded: /usr/local/mysql/lib/mysql/plugin/caching_sha2_password.so: cannot open shared object file: No such file or directory
```

低版本的驱动, 可以通过修改默认的加密插件来连接 DB:
```
[mysqld]
default_authentication_plugin = mysql_native_password
```

**说明:** 如果编程语言的驱动还不支持 `caching_sha2_password` 方式, 建议修改默认的验证为 `mysql_native_password`;

## 日志设置

8.0 中不支持 log-syslog 选项.

尽管从 `mysqld_safe` 脚本来看依旧支持 syslog, 不过在实际启动的时候, 如果指定了 syslog 相关选项, mysqld 在启动的时候会出现以下错误:
```
2020-04-17T09:06:33.027601Z 0 [ERROR] [MY-000067] [Server] unknown variable 'log-syslog=1'.
2020-04-17T09:06:33.028684Z 0 [ERROR] [MY-010119] [Server] Aborting
```

从官方手册来看, 8.0 版本不支持 `log-syslog` 选项.

## 表变更

#### 没有 frm 文件

8.0 开始去掉了 frm 文件, 表结构定义默认内置到 innodb 的 ibd 文件中, 可以通过 `ibd2sdi  ..table.ibd` 获取详细的字段信息.

更多见:

  [8.0-ibd2sdi](https://dev.mysql.com/doc/refman/8.0/en/ibd2sdi.html)   
  [mysql-8-frm-drop-how-to-recover-table-ddl]https://www.percona.com/blog/2018/12/07/mysql-8-frm-drop-how-to-recover-table-ddl/)   


#### 没有整形宽度

表结构中去掉了整数类型宽度的声明, 只能看到类型:

```
mysql root@[localhost:s3397 percona] > show warnings\G
*************************** 1. row ***************************
  Level: Warning
   Code: 1681
Message: Integer display width is deprecated and will be removed in a future release.

mysql root@[localhost:s3397 percona] > show create table tests\G
*************************** 1. row ***************************
       Table: tests
Create Table: CREATE TABLE `tests` (
  `id` int NOT NULL AUTO_INCREMENT,
  `host` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `port` smallint NOT NULL DEFAULT '3306',
  `tag` varchar(100) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  `location` varchar(50) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `unq_hostmark` (`host`,`port`,`tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
```

#### 大小写敏感

8.0 版本中, 初始化和启动的时候, 选项 `lower_case_table_names` 的值必须相同. 更多见 [sysvar_lower_case_table_names](https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_lower_case_table_names).  

## SQL 语法变更

- 废弃了 `GROUP BY` 分组的排序 `ASC` 和 `DESC`, 存储过程中包含此语法的无法正常执行;
- 关键字变更, 变更了部分关键字, 执行 SQL 的时候可能执行失败, 需要通过引号避免错误, 更多见 [8.0-keywords](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/keywords.html);
- 最新版可能不支持 `&&`, `||`, `!` 的语法, 需要使用标准 SQL 的 `AND`, `OR`, `NOT` 进行替换;
- 外键的名字在整个 schema 中必须唯一;
- 支持公共表表达式(common table expression), 窗口函数(window function);
- 支持备份锁(backup lock), 更多见 [backup-lock](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/lock-instance-for-backup.html);
- 使用 `select xxx into outfile xx from xxx` 语法导出数据, `select xx from xxx into outfile ..` 语法可能废弃;
- 使用 `set password for ... = ''` 修改用户密码, `password(..)` 语法已经废弃;
- 不支持 `SELECT SQL_NO_CACHE ...` 语法;
-  sql_log_bin 仅支持会话级别的设置;
- 使用 `EXPLAIN` 时, 不支持于 `EXTENDED` 和 `PARTITIONS` 关键字一起使用;

## 索引变更

- 增加 invisible index(隐藏索引), 一个索引被设置为 invisible 后, 优化器会忽略该索引. 适合性能调试;
- 支持 descending index(降序索引);
- 支持 functional index(函数索引), 更多见 [8.0-functional-key](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/create-index.html#create-index-functional-key-parts);
- 索引命中优化, 更多见 [optimizer hints](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/optimizer-hints.html#optimizer-hints-index-level);

## 编码

去掉了 UTF8 编码, 使用 UTF8MB3 代替以前的 UTF8, 8.0 中建议使用 UTF8MB4 编码. 默认的编码亦从 latin1 改为 utf8mb4, 默认的编码排序规则从 latin1_swedish_ci 改为 utf8mb4_0900_ai_ci;

## 时区

从 8.0.19 版本开始, `TIMESTAMP` 和 `DATETIME` 两个时间类型都支持时区相关的设置. 以前仅有 `TIMESTAMP` 支持, `DATETIME` 支持后时间转换方便不少.

## 初始化与启动

同 `5.7` 版本, 初始化的时候生产随机密码, 启动后的第一件事为修改密码.

## 监控

一些监控工具需要参考 `常用参数变更` 部分, 对系统变量做一些调整. 如果使用 8.0 默认的验证方式, 需要确保编程语言依赖的驱动支持 `caching_sha2_password` 验证, 如果不支持, 可以考虑单独将 MySQL 中的监控用户的验证方式修改为 `mysql_native_password`.

## mysqldump 备份

使用较低的 `5.7.x` 或 `8.0.x` 版本进行 mysqldump 备份的时候, 默认指定了 sql 模式 `NO_AUTO_CREATE_USER`, 包含此模式的 `dump` 文件在恢复的时候都会失败, 需要手动删除该模式.

## innodb 变更

- 一个库中的表可以共用一个 ibd 表空间文件, 也可以一个表一个 idb 文件;  
- undo log 不再存放在字典信息中, 单独出来在 undo log 文件中;  
- 默认在 data/#innodb_temp 目录中创建 10 个 ibt 文件被 innodb 内部和用户空间的临时表使用;  
- information_schema 中表的列名存在变化, 更多见 [8.0-information_schema](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/information-schema.html).  


## 主从复制

- 8.0 版本开始去掉了不少的 sql 模式, 如果主从使用不同的版本(比如一个 5.7, 一个 8.0), 则会引起主从中断;
- 8.0 版本开始对临时表进行了额外的处理, 如果主从存在处理临时表的会话, 修改 binlog_format 则无法生效;
- slave 通过 `caching_sha2_password` 插件连接 master 的时候需要指定安全选项;
- group 复制同 slave, 如果使用 `caching_sha2_password` 需要指定安全选项;

#### slave 连接错误
在使用默认的 caching_sha2_password 插件时, slave 出现错误:
```
Master_SSL_Verify_Server_Cert: No
                Last_IO_Errno: 2061
                Last_IO_Error: error connecting to master 'user_replica@10.1.1.6:3397' - retry-time: 10 retries: 1 message: Authentication plugin 'caching_sha2_password' reported error: Authentication requires secure connection.
```

通过以下方式修复:
```
change master to master_ssl=1, get_master_public_key=1, master_public_key_path='public_key.pem';
```

更多选项见: [8.0-change-master-option](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/change-master-to.html).  
