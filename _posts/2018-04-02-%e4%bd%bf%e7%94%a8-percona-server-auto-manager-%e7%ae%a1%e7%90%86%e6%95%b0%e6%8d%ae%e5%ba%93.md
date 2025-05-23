---
id: 966
title: 使用 Percona Server auto manager 管理数据库
date: 2018-04-02T12:03:01+08:00
author: arstercz
layout: post
guid: https://highdb.com/?p=966
permalink: '/%e4%bd%bf%e7%94%a8-percona-server-auto-manager-%e7%ae%a1%e7%90%86%e6%95%b0%e6%8d%ae%e5%ba%93/'
categories:
  - code
  - database
  - percona
tags:
  - manage
  - MySQL
comments: true
---
## 介绍

[Percona Server auto manager](https://github.com/arstercz/percona-server-auto-manager) 是基于 `percona-server-5.6.39.83.1` 的一个分支版本, 其增加了 memcached 记录和 sql 过滤的功能, 用来降低管理员操作数据库的风险. 不同于 [inception](https://github.com/mysql-inception/inception) 的深度修改, `Percona Server auto manager` 仅修改客户端的 `client/mysql.cc` 和 `client/mysqldump.c`, 不影响 server 端的功能.

*说明*:

  * memcached 功能用来记录用户输入的用户名及密码, 这点在一次一密登录 mysql 的时候比较有用, 由于 mysql 命令行是将最终的密码哈希结果传给 server, 所以中间件等软件无法得知用户输入的验证信息, 如果一次一密是有状态的则可以通过时间等方式算出验证信息 比如 [google totp]({{ site.baseurl }}/%E5%A6%82%E4%BD%95%E5%AE%9E%E7%8E%B0-mysql-%E7%9A%84%E4%B8%80%E6%AC%A1%E4%B8%80%E5%AF%86%E7%99%BB%E5%BD%95/), 如果是无状态的则中间件代理等工具无法得知验证信息. 当然我们也可以在 client 代码层完成验证, 不过这种方式存在局限性, 不够通用;

  * sql 过滤功能则主要用来限制开发者或管理员对数据库表的修改, 可以使用 `--skip-sql-filter` 选项忽略此功能, 具体的限制规则见下文.

  * 记录 sql 功能主要用来记录通过 `mysql` 工具执行过的 sql 语句, 同时也包含部分上下文环境信息.

## 如何编译

具体的编译可以参考 percona 的官方文档 [percona-source-install](https://www.percona.com/doc/percona-server/5.6/installation.html#installing-percona-server-from-a-source-tarball), memcached 功能默认关闭, 可以使用以下选项开启 memcached 功能:
```
cmake . -DWITH_MEMCACHED_RECORD=ON
```

如果开启此选项, 需要安装依赖 `libmemcached-devel`.

sql 过滤功能默认集成到 `client/mysql.cc` 工具中, 详见 `--sql-filter` 选项, 可以使用 `--skip-sql-filter` 选项禁用 sql 过滤功能;

`--table-threshold` 选项则用来控制允许修改表结构的一个阈值, 比如表大小超过 1G, 则不允许执行 `alter table` 语句, 默认为 200MB.


## 如何工作

### memcached 选项

我们在 `src/client/mysql.cc` 和 `src/client/mysqldump.c` 代码中增加了 `store_userpass_mem` 函数用来存储用户输入的用户名和密码, 条目在memcached 中存储 30s. 可以使用 `--memcached-server` 选项指定 memcached 信息:
```
# /opt/percona5.6.39/bin/mysql --help|grep -P 'memcached|threshold|filter'
  --memcached-server=name 
  --table-threshold=# table size(MB) threshold for disabled alter syntax, default
  --sql-filter        whether enable sql filter, default is true(1)
                      (Defaults to on; use --skip-sql-filter to disable.)
memcached-server                  localhost:11211
table-threshold                   200
sql-filter                        TRUE
```

mysql 命令在连接到 mysql server 之前会将用户名和密码存到指定的 memcached server 中. 如果 memcached 无效, 则打印警告信息, 不影响client 的正常使用.


### sql 过滤

同样的我们在 `src/client/mysql.cc` 中增加了过滤条件, 所有的 sql 在发送到真实的 `mysql server` 之前都需要进行以下匹配:
```
1. select 语句必须包含 where 或 limit 关键字;
2. update 或 delete 语句必须包含 where 关键字;
3. 禁止 'update/delete ... where .. (order by 或 limit)' 等不安全语句;
4. 禁止 'drop database 或 drop schema' 语句;
5. 禁止 'create index' 语句;
6. 禁止减少相关的 alter 语句, 这意味着只能 add 列, 不能 'drop|change|modify|rename' 列;
7. 禁止 'grant all' 语句;
8. 禁止 'revoke' 语句;
9. 禁止 'load' 语句;
10. 禁止减少相关的 DDL 语句, 即不能执行 'purge table, truncate table, drop table' 等操作；
11. 禁止 'set ...' 语句, 不过可以执行 'set names ...' 修改编码语句;
12. 禁止更改表大小超过 --table-threshold 选项的表, 默认为 200MB; 
```

## 如何使用

### memcached 记录

使用正确或错误的密码登录 mysql server:
```
# /opt/percona5.6.39/bin/mysql -h 10.0.21.5 -u arstercz -P 3305 -p --memcached-server "10.0.21.5:11211"
Enter password: 
ERROR 2003 (HY000): Can't connect to MySQL server on '10.0.21.5' (113)
```
再从 memcached 中读取信息, memcached 记录保存 30s:
```
# memcached-tool 10.0.21.5:11211 dump
Dumping memcache contents
  Number of buckets: 1
    Number of items  : 1
    Dumping bucket 1 - 1 total items
    add arstercz 0 1520839412 10
    xxxx123456
```

### sql 过滤
```
mysql arstercz@[10.0.21.5:3305 (none)] > alter table checksums add column sss varchar(50);                   

        [WARN] - Must 'use <database>' before alter table, current database is null.

mysql arstercz@[10.0.21.5:3305 (none)] > use percona
Database changed
mysql arstercz@[10.0.21.5:3305 percona] > alter table checksums drop column sss varchar(50);   

        [WARN]
         +-- alter table checksums drop column sss varchar(50)
         Caused by: disable descreased ALTER syntax.
this sql syntax was disabled by administrator

mysql arstercz@[10.0.21.5:3305 percona] > select * from checksums;

        [WARN]
         +-- select * from checksums
         Caused by: no where/limit for select clause
this sql syntax was disabled by administrator

mysql arstercz@[10.0.21.5:3305 percona] > delete from checksums;

        [WARN]
         +-- delete from checksums
         Caused by: no where for delete/update clause
this sql syntax was disabled by administrator

mysql arstercz@[10.0.21.5:3305 percona] > alter table test.user_info add column sss varchar(50);

        [WARN] - the test.user_info size is 4240MB, disallowed by administrator
```

### 记录 sql

增加了 `--record-file` 选项来记录所有通过 `mysql` 工具执行过的 sql 语句, 默认 /tmp/.mysql_record_all, 每个用户执行的 sql 单独记录到 `$record_file.$user` 文件里, 每个用户一个文件, 如果不想记录 sql 可以指定 `--record-file=""` 跳过, 该选项指定的路径及文件需要保证对应的用户有足够的权限写入. 另外不记录 `use <db>` 语句,  日志文件里有 `db:xxxx` 标识当前的 db:
```
# less /tmp/.mysql_record_all.root 
[2018-10-08T12:50:55 login:root user:root shell:/bin/bash cwd:/home/mysql/percona-server-auto-manager/client db:(null)] show databases
[2018-10-08T12:50:59 login:root user:root shell:/bin/bash cwd:/home/mysql/percona-server-auto-manager/client db:test] show tables
```

## 其它特性支持

### audit_log 插件

我们增加了 audit_log_timezone 选项开关用来设置输出的日期时间戳的时区, 默认为 UTC 时区, 可以指定 LOCAL 值以支持本地时区:
```
set global audit_log_timezone = LOCAL;
```

### readonly 提示

我们在 prompt 选项中增加了 `\i` 值用来提示当前连接的 MySQL 实例是否开启了 `readonly`, `ro` 表示 `read only`(可能该实例为 slave), `rw` 表示 `read write`(该实例可能为 master):
```
[mysql]
prompt = 'mysql \u@[\h:\p \d \i] > '
```

编译的时候不管是不是指定了 WITH_MEMCACHED_RECORD, 都会开启 readonly 功能:
```
mysql root@[localhost:s3301 (none) rw] > select @@read_only;
+-------------+
| @@read_only |
+-------------+
|           0 |
+-------------+
1 row in set (0.00 sec)

mysql root@[localhost:s3301 (none) rw] > set global read_only = 1;
Query OK, 0 rows affected (0.07 sec)

mysql root@[localhost:s3301 (none) ro] > set global read_only = 0;
Query OK, 0 rows affected (0.00 sec)

mysql root@[localhost:s3301 (none) rw] > 
```

## 总结

`Percona Server auto manager` 目前还仅局限于 client 端的使用, 其它版本的 `mysql client` 或程序驱动(如 jdbc) 等不受此限制约束, 比起原生的 `--safe-update` 选项, `Percona Server auto manager` 的限制更完善, 但是也更繁琐, 不过可以使用 `--skip-sql-filter` 选项禁用过滤功能. 另外 `Percona Server auto manager` 仅在 client 端增加功能, 并不影响 server 端的特性, 线上使用和 percona 官方的版本没有其它区别;
