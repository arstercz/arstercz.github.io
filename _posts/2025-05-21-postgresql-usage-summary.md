---
layout: post
title: "postgrepsql 要点汇总"
tags: [postgresql]
comments: true
---

## 通用参数

| 选项 | 默认值 | 说明 |
| :- | :- | :- |
| max_connections | 100 | 允许客户端连接的最大数目 |
| fsync | 	on | 强制把数据同步更新到磁盘 |
| shared_buffers | 24MB | 决定有多少内存可以被PostgreSQL用于缓存数据（推荐内存的1/4) |
| work_mem | 1MB | 使内部排序和一些复杂的查询都在这个buffer中完成 |
| effective_cache_size | 128MB | 优化器假设一个查询可以用的最大内存，和shared_buffers无关（推荐内存的1/2) |
| maintenance_work_mem | 16MB | 这里定义的内存只是被VACUUM等耗费资源较多的命令调用时使用 |
| wal_buffer | 	768kB | 日志缓存区的大小 |
| checkpoint_segments | 3 | 设置wal log的最大数量数（一个log的大小为16M） |
| checkpoint_completion_target | 0.5 | 	表示checkpoint的完成时间要在两个checkpoint间隔时间的N%内完成 |
| commit_delay | 0 | 事务提交后，日志写到wal log上到wal_buffer写入到磁盘的时间间隔。需要配合commit_sibling |
| commit_siblings | 5 | 设置触发commit_delay的并发事务数，根据并发事务多少来配置 |
| autovacuum_naptime | 1min | 下一次vacuum任务的时间 |
| autovacuum_analyze_threshold | 50 | 与autovacuum_analyze_scale_factor配合使用，来决定是否analyze |
| autovacuum_analyze_scale_factor | 0.1 | 当update,insert,delete的tuples数量超过autovacuum_analyze_scale_factor \* table_size+autovacuum_analyze_threshold时，进行analyze。 |

## 插入更新

1、关闭自动提交（autocommit=false）
如果有多条数据库插入或更新等，最好关闭自动提交，这样能提高效率
 
2、多次插入数据用copy命令更高效
有的处理中要对同一张表执行很多次insert操作。这个时候我们用copy命令更有效率。因为insert一次，其相关的index都要做一次，比较花费时间。

## 内核参数调整

postgresql 通过共享缓存及信号量实现多进程之间数据的操作, 所以需要注意以下几个内核参数, 不要设置太小, 避免 postgresql 出现 `No Space` 相关的错误, 如下参考设置:

```c
kernel.shmmax = 68719476736
kernel.shmall = 42949672960
kernel.sem = 4096   2097152 1024  512

/*           SEMMSL SEMMNS SEMOPM SEMMNI

	SEMMSL: maximum number of semaphores per array
	SEMMNS: maximum semaphores system-wide
	SEMOPM: maximum operations per semop call
    SEMMNI: maximum arrays
*/
```

更多见: [postgresql-kernel-resources](https://www.postgresql.org/docs/current/kernel-resources.html).  

## 开启慢查询

配置文件设置:

```sql
log_min_duration_statement=5000
```
sql 查看:
```
postgres=# select pg_reload_conf()
postgres=# show log_min_duration_statement;
```

**备注**: 9.4 之后的版本, postgresql.auto.conf 的优先级比 postgresql.conf 的优先级高, 如果同时存在同名的选项, 系统会优先选择优先级高的配置文件. 9.4 版本之后支持以下语法修改配置:

```sql
ALTER SYSTEM set work_mem = 16MB;
```

记录更改是在 postgresql.auto.conf 的替代文件中通过 `ALTER SYSTEM` 所做出的, 不是直接对 postgresql.conf 修改.


## 查看执行计划

```sql
explain analyze select …
explain (analyze,verbose,buffers) select …

begin;
explain analyze insert/update/delete … ;
rollback;
```

## 安全配置

`pg_hba.conf` 文件可以指定允许哪些用户以何种方式连接, 该文件的修改可动态生效.

新版本使用 `可登录角色`, `组角色` 术语描述用户权限的关系, 支持 `CREATE ROLE` 语法. 旧版以 `用户`, `组` 描述. 不过新版也支持 `CREATE USER`, `CREATE GROUP` 语法.
```sql
CREATE ROLE leo LOGIN PASSWORD 'password' SUPERUSER VALID UNTIL 'infinity'
```

#### 用户及权限

```sql
CREATE ROLE user_percona LOGIN PASSWORD 'xxxxxx';

# admin
CREATE ROLE user_db LOGIN PASSWORD 'xxxxxx';
CREATE DATABASE dbtest WITH owner  = 'user_db';

CREATE SCHEMA db_percona;

# grant privielges
GRANT ALL ON ALL TABLES IN SCHEMA public TO user_test WITH GRANT OPTION;
GRANT SELECT, UPDATE, DELETE, INSERT ON ALL TABLES IN SCHEMA my_schema TO PUBLIC; # PUBLIC 为授予所有人;
GRANT ALL ON SCHEMA db_percona TO user_percona;
```

在 postgresql 中, 一个 database 的所有者仅对自己在本库中所创建的对象拥有控制权, 对其它角色在本库中所创建的对象没有访问权限. 不过所有者却有权限删掉整个库.

更多见: [sql-grant](https://www.postgresql.org/docs/current/sql-grant.html)

## 编码

可以通过以下方式设置编码, 如果没有指定, 则继承上级的设置. postgresql 中 `UTF8` 编码支持 `1 - 4` 字节长度, 是真正的 `UTF8`, 不像 MySQL 仅支持 3 字节.

#### 初始化时指定

initdb 默认以 `UTF8` 编码初始化:
```sql
initdb -E UTF8
```

#### 创建库时指定

```sql
# command line
$ createdb -E UTF8 -T template0 --lc-collate=en_US.UTF-8 --lc-ctype=en_US.UTF-8 dbtest

# with SQL 
CREATE DATABASE dbtest WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;
```
上述两种方式等同.

#### 查看编码

```sql
$ psql -l
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
-----------+----------+----------+-------------+-------------+-----------------------
 percona   | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
(4 rows)
```

#### 修改当前会话的编码

```
# 修改会话编码
\encoding LATIN1

SET CLIENT_ENCODING TO 'LATIN1';
SET NAMES 'LATIN1';

# 查看当前会话编码
SHOW client_encoding;

# 重置编码
RESET client_encoding;
```

## 模板说明

template0 为原始的干净模板, 如果其它模板有问题, 可以基于 template0 再创建. 如果需要定制模板数据库, 最好基于 template1 修改. 如果需要默认的编码字符集等, 需要基于 template0 模板, template1 不会生效.

```
# 指定模板创建库
CREATE DATABASE dbtest TEMPLATE template1;

# 指定一个库为模板
UPDATE pg_database SET datistemplate = TRUE WHERE datname = 'dbtest';
```

## 常用 SQL

与 MySQL 对比如下:

| MySQL | PostgreSQL 快捷命令 | PostgreSQL 查询 | 
| :- | :- | :- |
| 无 | \\l | select datname from pg_database |
| show databases | \\dn |  select catalog_name, schema_name from information_schema.schemata; |
| show tables |  \\dt schema_name.* | SELECT table_name FROM information_schema.tables WHERE table_schema = 'schema_name' |
| describe table_name | \\d schema_name.able_name | SELECT column_name FROM information_schema.columns WHERE table_name ='table_name' |
| show processlist | 无 | select \* from pg_stat_activity |
| kill query <id> | 无 | select pg_cancel_backend(<pid>) |
| kill connection <id> | 无 |  select pg_terminate_backend(<pid>) |
| select \* from information_schema.INNODB_LOCKS | 无 | select \* from pg_locks |


**备注**

postgresql 管理函数可以用在 select 语句中, 如下所示:
```sql
# 9.1 之前的版本为 procid, 新版为 pid 
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'user_name'
```

## DDL 操作与锁


目前 postgresql 并不支持在线的 DDL 操作, 从 `9.5` 版本之后一些 `ALTER` 操作可能会很快, 存在默认值的 ALTER 语句通常都会锁表, 耗时较长, 如下所示:
```
Some lock-strength reductions for ALTER TABLE have been added to PostgreSQL 9.5. You can't do anything that requires a full table 
rewrite without an exclusive lock though, in 9.5 or below.

Some operations, like ALTER TABLE ... DROP COLUMN or ALTER TABLE ... ADD COLUMN ... without a DEFAULT and NOT NULL can be done with
 a very short exclusive lock even in older versions. A brief moment is needed where queries don't run, but it's almost instantaneous, 
since no table rewrite is required.

There are some things that could be optimised, like ALTER TABLE ... ADD COLUMN ... DEFAULT ... NOT NULL, by storing the default for
 old rows in the table metadata and looking it up when reading old rows. This has not been implemented in PostgreSQL.
```

从 `postgresql 11` 版本开始, postgresql 支持 `ALTER TABLE ADD COLUMN ... DEFAULT ... NOT NULL` 操作, 不会长时间锁表.

参考:

  [Fast Column Creation with Defaults](https://brandur.org/postgres-default)  
  [postgresql-ddl-stackexchange](https://dba.stackexchange.com/questions/105847/does-postgresql-support-online-schema-modification-ddl)  
  [sql-altertable](https://www.postgresql.org/docs/9.4/sql-altertable.html)  
  [release-11-E.10.3.3. Utility Commands](https://www.postgresql.org/docs/11/release-11.html)  
  

## 备份

主要两个备份工具:

| 工具 | 说明 |
: -: | :- |
| pg_dump | 备份指定的 database |
| pg_dumpall | 备份数据库中的所有 database |

两个工具都不支持在命令行中设定登录密码. 可以在账号目录下新增 `.pgpass` 文件存储密码, 或设置 `PGPASSWORD` 环境变量;

如下所示, 备份单独的库:
```
# 生成 insert 语句的文本格式
pg_dump -F p --column-inserts -b -v -f percona.insert.sql
```

#### 备份时需要注意的问题

pg_dump 备份时不会影响 DML 操作, 本身使用重复读隔离级别, 但是会阻塞 DDL 操作. 更多见 [pg_dump_and_DDL](https://blog.dbi-services.com/when-we-do-a-pg_dump-and-right-afterwards-truncate-a-table-which-is-in-the-dump-what-happens/).

## 监控

> 详细监控见 [telegraf.postgresql](https://github.com/arstercz/telegraf/tree/influx/plugins/inputs/postgresql), [telegraf.postgresql_extensible](https://github.com/arstercz/telegraf/tree/influx/plugins/inputs/postgresql_extensible).  

### 获取事务信息

```sql
SELECT
    pg_database.datname,
    REPLACE(tmp.state, ' ', '_'),
    COALESCE(count,0) as count,
    COALESCE(max_tx_duration,0) as max_tx_duration
FROM
  (
    VALUES ('active'),
     ('idle'),
     ('idle in transaction'),
     ('idle in transaction (aborted)'),
     ('fastpath function call'),
     ('disabled')
) AS tmp(state) CROSS JOIN (select * from pg_database where datname NOT IN ('postgres', 'template0', 'template1')) AS pg_database
LEFT JOIN
  (
    SELECT
        datname,
        state,
        count(*) AS count,
        MAX(EXTRACT(EPOCH FROM now() - xact_start))::float AS max_tx_duration
FROM pg_stat_activity
GROUP BY datname,state) AS tmp2
  ON tmp.state = tmp2.state AND pg_database.datname = tmp2.datname;
```

### 获取锁数量

```sql
    SELECT pg_database.datname,tmp.mode,COALESCE(count,0) as count
     FROM
    (
        VALUES ('accesssharelock'),
               ('rowsharelock'),
               ('rowexclusivelock'),
               ('shareupdateexclusivelock'),
               ('sharelock'),
               ('sharerowexclusivelock'),
               ('exclusivelock'),
               ('accessexclusivelock'),
               ('sireadlock')
     ) AS tmp(mode) CROSS JOIN (select *, oid from pg_database where datname NOT IN ('postgres', 'template0', 'template1')) AS pg_database
     LEFT JOIN
     (SELECT database, lower(mode) AS mode,count(*) AS count
       FROM pg_locks WHERE database IS NOT NULL
       GROUP BY database, lower(mode)
     ) AS tmp2
     ON tmp.mode=tmp2.mode and pg_database.oid = tmp2.database ORDER BY 1
```

### 主从信息

#### pg_stat_replication - master 执行

```sql
SELECT *,
    (case pg_is_in_recovery() when 't' then null else pg_current_xlog_location() end) AS pg_current_xlog_location,
    (case pg_is_in_recovery() when 't' then null else pg_xlog_location_diff(pg_current_xlog_location(), replay_location)::float end) AS pg_xlog_location_diff
FROM pg_stat_replication
```

#### pg_replication_slots - slave 执行

```sql
SELECT slot_name, database, active, pg_xlog_location_diff(pg_current_xlog_location(), restart_lsn)
  FROM pg_replication_slots
```

#### pg_stat_archiver - slave 执行

```sql
SELECT *, extract(epoch from now() - last_archived_time) AS last_archive_age 
  FROM pg_stat_archiver
```

#### 判断主从

```sql
select pg_is_in_recovery()
```

If it's true, you're on a slave; if false, master.

## 安装 postgresql

更多安装见: [postgresql-install](https://www.postgresql.org/download/linux/redhat/), 下面简单介绍源码和 rpm 的安装方式.
在实际的安装中, 可以通过 pg_config 查看编译的参数, 如下所示:
```
# /usr/bin/pg_config --configure \
  '--build=x86_64-redhat-linux-gnu' '--host=x86_64-redhat-linux-gnu' '--program-prefix=' \
  '--disable-dependency-tracking' '--prefix=/usr' '--exec-prefix=/usr' '--bindir=/usr/bin' \
  '--sbindir=/usr/sbin' '--sysconfdir=/etc' '--datadir=/usr/share' '--includedir=/usr/include' \
  '--libdir=/usr/lib64' '--libexecdir=/usr/libexec' '--localstatedir=/var' '--sharedstatedir=/var/lib' \
  '--mandir=/usr/share/man' '--infodir=/usr/share/info' '--disable-rpath' '--with-perl' '--with-tcl' \
  '--with-tclconfig=/usr/lib64' '--with-python' '--with-ldap' '--with-openssl' '--with-pam' '--with-krb5' \
  '--with-gssapi' '--with-ossp-uuid' '--with-libxml' '--with-libxslt' '--enable-nls' '--enable-dtrace' \
  '--with-selinux' '--with-system-tzdata=/usr/share/zoneinfo' '--datadir=/usr/share/pgsql' \ 
  'build_alias=x86_64-redhat-linux-gnu' 'host_alias=x86_64-redhat-linux-gnu' \ 
  'CFLAGS=-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -m64 -mtune=generic -DLINUX_OOM_SCORE_ADJ=0' \
  'LDFLAGS=-Wl,-z,relro '
```

#### 源码安装

可以通过 `pg_config` 查看默认发行版的参数, 源码安装的时候可以依照这些参数进行编译:
```
yum -y install perl-ExtUtils-Embed openssl openssl-devel pam pam-devel \ 
  libxml2 libxml2-devel libxslt libxslt-devel openldap openldap-devel \
  python-devel readline-devel tcl tcl-devel

cd /usr/local/src/postgresql-9.6.19
./configure --prefix=/opt/postgresql-9.6.19 --build=x86_64-redhat-linux-gnu \ 
  --host=x86_64-redhat-linux-gnu --with-perl --with-python --with-tcl --with-ldap \
  --with-openssl --with-pam --enable-thread-safety --with-system-tzdata=/usr/share/zoneinfo \
  --with-libxml --with-ossp-uuid --with-libxslt --with-libedit-preferred \
  --with-gssapi CFLAGS='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions \
  -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches \
  -m64 -mtune=generic -DLINUX_OOM_SCORE_ADJ=0' LDFLAGS='-Wl,-z,relro'
```

#### rpm 安装

```
# Install the repository RPM:
yum install -y \
  https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Install PostgreSQL:
yum install -y postgresql96-server

# Optionally initialize the database and enable automatic start:
/usr/pgsql-9.6/bin/postgresql96-setup initdb
systemctl enable postgresql-9.6
systemctl start postgresql-9.6
```

## 扩展安装

安装一些扩展的时候可能出现不匹配的问题, 这种时候需要我们单独安装匹配的包. 比如安装 plperl 扩展的时候可能出现以下错误:

```
postgres=# create extension plperl;
ERROR:  could not load library "/opt/pgsql/lib/postgresql/plperl.so": \
  libperl.so: cannot open shared object file: No such file or directory

postgres=# create extension plperl;
ERROR:  could not load library "/opt/pgsql/lib/postgresql/plperl.so": \
  /opt/pgsql/lib/postgresql/plperl.so: undefined symbol: Perl_xs_handshake
```

可以从 plperl.so 文件中获取到对应的 perl 版本:
```
# strings /opt/pgsql/lib/postgresql/plperl.so | grep v5
v5.26.0
```

这可能是因为本地主机 `libperl.so` 版本过低的原因引起, 需要安装对应版本的文件, 如下所示安装 `perl-5.26.0` 版本:

```
mkdir /usr/local/perl5.26
cd perl-5.26.0

# 以共享库的方式编译
./Configure -des -Dprefix=/usr/local/perl5.26 -Dversion=5.26.0 \
  -Duseshrplib -Dusethreads -Uversiononly
make -j 4 && make install
```

重启 postgres 服务:

```sql
export LD_LIBRARY_PATH=/usr/local/perl5.26/lib/5.26.0/x86_64-linux-thread-multi/CORE:$LD_LIBRARY_PATH
pg_ctl restart

# 再安装扩展
postgres=# create extension plperl;                        
CREATE EXTENSION

# 查看对应扩展的函数
postgres=# \dx+ plperl
      Objects in extension "plperl"
            Object Description            
------------------------------------------
 function plperl_call_handler()
 function plperl_inline_handler(internal)
 function plperl_validator(oid)
 language plperl
(4 rows)
```

