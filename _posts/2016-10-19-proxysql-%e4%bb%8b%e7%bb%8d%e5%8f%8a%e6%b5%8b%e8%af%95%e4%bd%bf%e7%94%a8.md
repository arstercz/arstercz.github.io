---
id: 692
title: proxysql 介绍及测试使用
date: 2016-10-19T14:58:45+08:00
author: arstercz
layout: post
guid: http://highdb.com/?p=692
permalink: '/proxysql-%e4%bb%8b%e7%bb%8d%e5%8f%8a%e6%b5%8b%e8%af%95%e4%bd%bf%e7%94%a8/'
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
  - performance
tags:
  - MySQL
  - proxy
  - proxysql
---
[proxysql](http://www.proxysql.com/) 是一个 MySQL 中间层的代理, 其源代码 [github-proxysql](https://github.com/sysown/proxysql) 在github 上托管, 兼容 MySQL 协议, 所以同样支持 Percona 和 MariaDB 分之版本. 同类的产品有 [Atlas](https://github.com/Qihoo360/Atlas) 和 [kingshard](https://github.com/flike/kingshard), 三者相比较起来, Atlas 和 kingshard 的功能类似, 仅能代理指定的库, 同样都支持表分区处理; proxysql 则可以代理整个实例, 配置方便则是 `cnf 文件 + sqlite3 + runtime` 的方式实现, 特别灵活, 不过目前还没有实现表分区功能, 其它功能可以在官网介绍中查找.

proxysql 的简单配置使用可以参考 [consul-proxysql-mysql-ha](https://www.percona.com/blog/2016/09/16/consul-proxysql-mysql-ha/)
管理接口参见 [admin-interface](https://github.com/sysown/proxysql/wiki/Tables-in-Admin-interface)

下面部分主要介绍笔者在测试环境中的运行情况, 侧重于 proxysql 连接和直连之间的数据对比, 编码方面也会简单说明.

## 以下为测试环境的配置

系统环境:

```
Centos 6.5 final, Linux cz-test1 2.6.32-431.3.1.el6.x86_64
proxysql-1.4.3-1.x86_64.rpm
```

MySQL 主从配置:

```
version: Percona-Server-5.5.36
repl :
    10.0.21.5:3303(current master: read_only = 0)
       +-- 10.0.21.7:3303(current slave: read_only = 1)
```

proxysql 配置:

/etc/proxysql.cnf 中的主要配置:

```
admin_variables=
{
        admin_credentials="admin:admin"
        mysql_ifaces="0.0.0.0:6032"
}

mysql_variables=
{
        threads=4
        max_connections=4096
        interfaces="0.0.0.0:6033"
        ......
        connect_retries_on_failure=10
}
mysql_servers =
(
    {
            address = "10.0.21.5"
            port = 3303
            hostgroup = 1
            max_connections = 2000
            weight = 1000
    },
    {
            address = "10.0.21.5"
            port = 3303
            hostgroup = 20
            max_connections = 2000
            weight = 1000
    },
    {
            address = "10.0.21.7"
            port = 3303
            hostgroup = 20
            max_connections = 2000
            weight = 1000
            max_replication_lag = 10
    }
)

mysql_users:
(
        {
                username = "percona"
                password = "xxxxxxxxx"
                default_hostgroup = 1     # 默认情况下分配请求到组 1
                max_connections=2000
                default_schema="percona"
                transaction_persistent = 1
                active = 1
        }
)

#查询规则, select 类型的查询发送到主从, 其它类型的查询只发送到 master.
mysql_query_rules:
(
    {
        rule_id=1
        active=1
        match_pattern="SELECT.+FOR.+UPDATE$"
        destination_hostgroup=1
        apply=1
        re_modifiers="CASELESS"
    },
    {
        rule_id=2
        active=1
        match_pattern="^SELECT"
        destination_hostgroup=2
        apply=1
        re_modifiers="CASELESS"
    }
)

mysql_replication_hostgroups=
(
        {
                writer_hostgroup=1
                reader_hostgroup=20
                comment="percona repl 1"
        }
)
```

`/etc/init.d/proxysql start` 启动后进行相关的测试.

#### 先来看看 proxysql 的整个实例代理, 连接 proxysql 等同连接 mysql server:

```
mysql -h 10.0.21.5 -P 6033 -u percona per2 -e "select database()"
+------------+
| database() |
+------------+
| per2       |
+------------+
mysql -h 10.0.21.5 -P 6033 -u percona percona -e "select database()"
+------------+
| database() |
+------------+
| percona    |
+------------+
```

#### centos7 系统中使用 mysql 自带的 sql_bench 工具 test-insert 进行测试

下面结果为连接 proxysql 接口的信息:

```
[root@cz-centos7 sql-bench]# ./test-insert --host 10.0.21.5:6033 --user=percona --database=percona 
Testing server 'MySQL 5.5.36 34.1 rel34.1 log' at 2016-10-18 22:33:55

Testing the speed of inserting data into 1 table and do some selects on it.
The tests are done with a table that has 100000 rows.

Generating random keys
Creating tables
Inserting 100000 rows in order
Inserting 100000 rows in reverse order
Inserting 100000 rows in random order
Time for insert (300000): 559 wallclock secs (15.26 usr 26.04 sys +  0.00 cusr  0.00 csys = 41.30 CPU)

Test of prepared+execute/once prepared many execute selects
Time for prepared_select (100000): 99 wallclock secs (11.38 usr  7.64 sys +  0.00 cusr  0.00 csys = 19.02 CPU)
Time for once_prepared_select (100000): 93 wallclock secs ( 5.72 usr  7.04 sys +  0.00 cusr  0.00 csys = 12.76 CPU)
Retrieving data from the table
Time for select_big (10:3000000):  5 wallclock secs ( 3.08 usr  0.00 sys +  0.00 cusr  0.00 csys =  3.08 CPU)
Time for order_by_big_key (10:3000000):  6 wallclock secs ( 3.23 usr  0.04 sys +  0.00 cusr  0.00 csys =  3.27 CPU)
Time for order_by_big_key_desc (10:3000000):  7 wallclock secs ( 3.27 usr  0.12 sys +  0.00 cusr  0.00 csys =  3.39 CPU)
Time for order_by_big_key_prefix (10:3000000):  6 wallclock secs ( 3.04 usr  0.09 sys +  0.00 cusr  0.00 csys =  3.13 CPU)
Time for order_by_big_key2 (10:3000000):  6 wallclock secs ( 3.08 usr  0.11 sys +  0.00 cusr  0.00 csys =  3.19 CPU)
Time for order_by_big_key_diff (10:3000000):  6 wallclock secs ( 3.09 usr  0.10 sys +  0.00 cusr  0.00 csys =  3.19 CPU)
Time for order_by_big (10:3000000):  8 wallclock secs ( 3.13 usr  0.14 sys +  0.00 cusr  0.00 csys =  3.27 CPU)
Time for order_by_range (500:125750):  1 wallclock secs ( 0.21 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.25 CPU)
Time for order_by_key_prefix (500:125750):  1 wallclock secs ( 0.21 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.26 CPU)
Time for order_by_key2_diff (500:250500):  1 wallclock secs ( 0.33 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.37 CPU)
Time for select_diff_key (500:1000):  0 wallclock secs ( 0.07 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.11 CPU)
Time for select_range_prefix (5010:42084):  9 wallclock secs ( 1.07 usr  0.47 sys +  0.00 cusr  0.00 csys =  1.54 CPU)
Time for select_range_key2 (5010:42084):  8 wallclock secs ( 1.15 usr  0.45 sys +  0.00 cusr  0.00 csys =  1.60 CPU)
Time for select_key_prefix (200000): 202 wallclock secs (25.89 usr 15.12 sys +  0.00 cusr  0.00 csys = 41.01 CPU)
Time for select_key (200000): 194 wallclock secs (26.79 usr 14.05 sys +  0.00 cusr  0.00 csys = 40.84 CPU)
Time for select_key_return_key (200000): 191 wallclock secs (27.72 usr 13.55 sys +  0.00 cusr  0.00 csys = 41.27 CPU)
Time for select_key2 (200000): 204 wallclock secs (28.27 usr 13.40 sys +  0.00 cusr  0.00 csys = 41.67 CPU)
Time for select_key2_return_key (200000): 197 wallclock secs (28.15 usr 12.89 sys +  0.00 cusr  0.00 csys = 41.04 CPU)
Time for select_key2_return_prim (200000): 196 wallclock secs (28.13 usr 13.17 sys +  0.00 cusr  0.00 csys = 41.30 CPU)

Test of compares with simple ranges
Time for select_range_prefix (20000:43500): 11 wallclock secs ( 1.56 usr  0.65 sys +  0.00 cusr  0.00 csys =  2.21 CPU)
Time for select_range_key2 (20000:43500): 12 wallclock secs ( 1.59 usr  0.60 sys +  0.00 cusr  0.00 csys =  2.19 CPU)
Time for select_group (111): 12 wallclock secs ( 0.03 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.04 CPU)
Time for min_max_on_key (15000): 14 wallclock secs ( 1.83 usr  1.07 sys +  0.00 cusr  0.00 csys =  2.90 CPU)
Time for min_max (60):  8 wallclock secs ( 0.02 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.03 CPU)
Time for count_on_key (100):  9 wallclock secs ( 0.02 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.03 CPU)
Time for count (100): 17 wallclock secs ( 0.02 usr  0.02 sys +  0.00 cusr  0.00 csys =  0.04 CPU)
Time for count_distinct_big (20): 13 wallclock secs ( 0.01 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.01 CPU)

Testing update of keys with functions
Time for update_of_key (50000):  102 wallclock secs ( 2.99 usr  3.88 sys +  0.00 cusr  0.00 csys =  6.87 CPU)
Time for update_of_key_big (501):  8 wallclock secs ( 0.02 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.07 CPU)

Testing update with key
Time for update_with_key (300000):  583 wallclock secs (14.32 usr 26.64 sys +  0.00 cusr  0.00 csys = 40.96 CPU)
Time for update_with_key_prefix (100000):  201 wallclock secs ( 9.05 usr  8.70 sys +  0.00 cusr  0.00 csys = 17.75 CPU)

Testing update of all rows
Time for update_big (10):  16 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Testing left outer join
Time for outer_join_on_key (10:10):   9 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)
Time for outer_join (10:10):  12 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for outer_join_found (10:10):  10 wallclock secs ( 0.01 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.01 CPU)
Time for outer_join_not_found (500:10):   9 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Testing SELECT ... WHERE id in (10 values)
Time for select_in (500:5000)  1 wallclock secs ( 0.10 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.14 CPU)

Time for select_join_in (500:5000)  0 wallclock secs ( 0.08 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.13 CPU)

Testing SELECT ... WHERE id in (100 values)
Time for select_in (500:50000)  2 wallclock secs ( 0.17 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.22 CPU)

Time for select_join_in (500:50000)  1 wallclock secs ( 0.13 usr  0.07 sys +  0.00 cusr  0.00 csys =  0.20 CPU)

Testing SELECT ... WHERE id in (1000 values)
Time for select_in (500:500000)  9 wallclock secs ( 0.77 usr  0.06 sys +  0.00 cusr  0.00 csys =  0.83 CPU)

Time for select_join_in (500:500000)  4 wallclock secs ( 0.79 usr  0.06 sys +  0.00 cusr  0.00 csys =  0.85 CPU)


Testing INSERT INTO ... SELECT
Time for insert_select_1_key (1):   3 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for insert_select_2_keys (1):   2 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for drop table(2):  0 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Testing delete
Time for delete_key (10000): 19 wallclock secs ( 0.42 usr  0.89 sys +  0.00 cusr  0.00 csys =  1.31 CPU)
Time for delete_range (12):  3 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Insert into table with 16 keys and with a primary key with 16 parts
Time for insert_key (100000): 231 wallclock secs ( 7.27 usr  8.10 sys +  0.00 cusr  0.00 csys = 15.37 CPU)

Testing update of keys
Time for update_of_primary_key_many_keys (256): 46 wallclock secs ( 0.02 usr  0.03 sys +  0.00 cusr  0.00 csys =  0.05 CPU)

Deleting rows from the table
Time for delete_big_many_keys (128): 14 wallclock secs ( 0.00 usr  0.02 sys +  0.00 cusr  0.00 csys =  0.02 CPU)

Deleting everything from table
Time for delete_all_many_keys (1): 14 wallclock secs ( 0.00 usr  0.02 sys +  0.00 cusr  0.00 csys =  0.02 CPU)

Inserting 100000 rows with multiple values
Time for multiple_value_insert (100000):  2 wallclock secs ( 0.20 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.20 CPU)

Time for drop table(1):  0 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Total time: 3385 wallclock secs (263.76 usr 175.71 sys +  0.00 cusr  0.00 csys = 439.47 CPU)
```

下面的结果为直连 MySQL 的信息:

```
[root@cz-centos7 sql-bench]# ./test-insert --host 10.0.21.5:3303 --user=percona --database=percona 
Testing server 'MySQL 5.5.36 34.1 rel34.1 log' at 2016-10-18 23:36:54

Testing the speed of inserting data into 1 table and do some selects on it.
The tests are done with a table that has 100000 rows.

Generating random keys
Creating tables
Inserting 100000 rows in order
Inserting 100000 rows in reverse order
Inserting 100000 rows in random order
Time for insert (300000): 513 wallclock secs (14.47 usr 26.47 sys +  0.00 cusr  0.00 csys = 40.94 CPU)

Test of prepared+execute/once prepared many execute selects
Time for prepared_select (100000): 64 wallclock secs (11.26 usr  6.35 sys +  0.00 cusr  0.00 csys = 17.61 CPU)
Time for once_prepared_select (100000): 54 wallclock secs ( 4.92 usr  6.25 sys +  0.00 cusr  0.00 csys = 11.17 CPU)
Retrieving data from the table
Time for select_big (10:3000000):  5 wallclock secs ( 2.92 usr  0.11 sys +  0.00 cusr  0.00 csys =  3.03 CPU)
Time for order_by_big_key (10:3000000):  5 wallclock secs ( 3.15 usr  0.30 sys +  0.00 cusr  0.00 csys =  3.45 CPU)
Time for order_by_big_key_desc (10:3000000):  6 wallclock secs ( 3.10 usr  0.35 sys +  0.00 cusr  0.00 csys =  3.45 CPU)
Time for order_by_big_key_prefix (10:3000000):  5 wallclock secs ( 2.87 usr  0.16 sys +  0.00 cusr  0.00 csys =  3.03 CPU)
Time for order_by_big_key2 (10:3000000):  5 wallclock secs ( 3.00 usr  0.17 sys +  0.00 cusr  0.00 csys =  3.17 CPU)
Time for order_by_big_key_diff (10:3000000):  4 wallclock secs ( 2.88 usr  0.20 sys +  0.00 cusr  0.00 csys =  3.08 CPU)
Time for order_by_big (10:3000000):  6 wallclock secs ( 2.94 usr  0.18 sys +  0.00 cusr  0.00 csys =  3.12 CPU)
Time for order_by_range (500:125750):  1 wallclock secs ( 0.21 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.26 CPU)
Time for order_by_key_prefix (500:125750):  1 wallclock secs ( 0.18 usr  0.06 sys +  0.00 cusr  0.00 csys =  0.24 CPU)
Time for order_by_key2_diff (500:250500):  1 wallclock secs ( 0.33 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.37 CPU)
Time for select_diff_key (500:1000):  0 wallclock secs ( 0.08 usr  0.03 sys +  0.00 cusr  0.00 csys =  0.11 CPU)
Time for select_range_prefix (5010:42084):  6 wallclock secs ( 0.98 usr  0.38 sys +  0.00 cusr  0.00 csys =  1.36 CPU)
Time for select_range_key2 (5010:42084):  6 wallclock secs ( 0.89 usr  0.42 sys +  0.00 cusr  0.00 csys =  1.31 CPU)
Time for select_key_prefix (200000): 126 wallclock secs (23.30 usr 14.38 sys +  0.00 cusr  0.00 csys = 37.68 CPU)
Time for select_key (200000): 121 wallclock secs (25.24 usr 13.27 sys +  0.00 cusr  0.00 csys = 38.51 CPU)
Time for select_key_return_key (200000): 119 wallclock secs (24.83 usr 13.13 sys +  0.00 cusr  0.00 csys = 37.96 CPU)
Time for select_key2 (200000): 127 wallclock secs (24.35 usr 13.95 sys +  0.00 cusr  0.00 csys = 38.30 CPU)
Time for select_key2_return_key (200000): 122 wallclock secs (24.08 usr 13.53 sys +  0.00 cusr  0.00 csys = 37.61 CPU)
Time for select_key2_return_prim (200000): 126 wallclock secs (24.84 usr 13.48 sys +  0.00 cusr  0.00 csys = 38.32 CPU)

Test of compares with simple ranges
Time for select_range_prefix (20000:43500):  7 wallclock secs ( 1.41 usr  0.51 sys +  0.00 cusr  0.00 csys =  1.92 CPU)
Time for select_range_key2 (20000:43500):  6 wallclock secs ( 1.39 usr  0.55 sys +  0.00 cusr  0.00 csys =  1.94 CPU)
Time for select_group (111):  7 wallclock secs ( 0.02 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.03 CPU)
Time for min_max_on_key (15000):  8 wallclock secs ( 1.83 usr  0.99 sys +  0.00 cusr  0.00 csys =  2.82 CPU)
Time for min_max (60):  4 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)
Time for count_on_key (100):  4 wallclock secs ( 0.02 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.03 CPU)
Time for count (100):  7 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)
Time for count_distinct_big (20): 10 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)

Testing update of keys with functions
Time for update_of_key (50000):  94 wallclock secs ( 2.65 usr  4.15 sys +  0.00 cusr  0.00 csys =  6.80 CPU)
Time for update_of_key_big (501):  9 wallclock secs ( 0.03 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.07 CPU)

Testing update with key
Time for update_with_key (300000):  530 wallclock secs (15.42 usr 25.10 sys +  0.00 cusr  0.00 csys = 40.52 CPU)
Time for update_with_key_prefix (100000):  184 wallclock secs ( 8.10 usr  9.76 sys +  0.00 cusr  0.00 csys = 17.86 CPU)

Testing update of all rows
Time for update_big (10):  14 wallclock secs ( 0.00 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.01 CPU)

Testing left outer join
Time for outer_join_on_key (10:10):   6 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for outer_join (10:10):   9 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for outer_join_found (10:10):   8 wallclock secs ( 0.01 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.01 CPU)
Time for outer_join_not_found (500:10):   8 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Testing SELECT ... WHERE id in (10 values)
Time for select_in (500:5000)  0 wallclock secs ( 0.08 usr  0.05 sys +  0.00 cusr  0.00 csys =  0.13 CPU)

Time for select_join_in (500:5000)  0 wallclock secs ( 0.09 usr  0.02 sys +  0.00 cusr  0.00 csys =  0.11 CPU)

Testing SELECT ... WHERE id in (100 values)
Time for select_in (500:50000)  2 wallclock secs ( 0.20 usr  0.03 sys +  0.00 cusr  0.00 csys =  0.23 CPU)

Time for select_join_in (500:50000)  0 wallclock secs ( 0.15 usr  0.04 sys +  0.00 cusr  0.00 csys =  0.19 CPU)

Testing SELECT ... WHERE id in (1000 values)
Time for select_in (500:500000)  6 wallclock secs ( 0.74 usr  0.08 sys +  0.00 cusr  0.00 csys =  0.82 CPU)

Time for select_join_in (500:500000)  4 wallclock secs ( 0.69 usr  0.10 sys +  0.00 cusr  0.00 csys =  0.79 CPU)


Testing INSERT INTO ... SELECT
Time for insert_select_1_key (1):   2 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for insert_select_2_keys (1):   4 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)
Time for drop table(2):  0 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Testing delete
Time for delete_key (10000): 17 wallclock secs ( 0.46 usr  0.85 sys +  0.00 cusr  0.00 csys =  1.31 CPU)
Time for delete_range (12):  3 wallclock secs ( 0.01 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.01 CPU)

Insert into table with 16 keys and with a primary key with 16 parts
Time for insert_key (100000): 220 wallclock secs ( 6.11 usr  9.50 sys +  0.00 cusr  0.00 csys = 15.61 CPU)

Testing update of keys
Time for update_of_primary_key_many_keys (256): 44 wallclock secs ( 0.02 usr  0.03 sys +  0.00 cusr  0.00 csys =  0.05 CPU)

Deleting rows from the table
Time for delete_big_many_keys (128): 13 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)

Deleting everything from table
Time for delete_all_many_keys (1): 13 wallclock secs ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)

Inserting 100000 rows with multiple values
Time for multiple_value_insert (100000):  1 wallclock secs ( 0.20 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.20 CPU)

Time for drop table(1):  0 wallclock secs ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)

Total time: 2658 wallclock secs (240.54 usr 175.23 sys +  0.00 cusr  0.00 csys = 415.77 CPU)
```

从上面结果看, 所有的更新操作所耗的时间差别不太大, proxysql 额外增加了大约 10% 左右的开销, select 差别较大, 不同的 select 类型, 开销也各不相同, 简单按key 查询的话开销也在 10% 左右, range 查询则开销很大, 有些 sql 达到了 50% 的额外开销.

#### 下面使用 mysqlslap 进行简单的测试

下面为连接 proxysql 的结果:

```
[root@cz-centos7 sql-bench]# /opt/Percona-Server-5.5.33-rel31.1-566.Linux.x86_64/bin/mysqlslap -h 10.0.21.5 -P 6033 -upercona percona -a --auto-generate-sql-execute-number=3000 --auto-generate-sql-load-type=read --auto-generate-sql-secondary-indexes=3 --auto-generate-sql-unique-query-number=1 --auto-generate-sql-write-number=1000 -c 10
Benchmark
    Average number of seconds to run all queries: 38.865 seconds
    Minimum number of seconds to run all queries: 38.865 seconds
    Maximum number of seconds to run all queries: 38.865 seconds
    Number of clients running queries: 10
    Average number of queries per client: 3000
```

下面为直连 MySQL 结果:

```
[root@cz-centos7 sql-bench]# /opt/Percona-Server-5.5.33-rel31.1-566.Linux.x86_64/bin/mysqlslap -h 10.0.21.5 -P 3303 -upercona percona -a --auto-generate-sql-execute-number=3000 --auto-generate-sql-load-type=read --auto-generate-sql-secondary-indexes=3 --auto-generate-sql-unique-query-number=1 --auto-generate-sql-write-number=1000 -c 10
Benchmark
    Average number of seconds to run all queries: 37.446 seconds
    Minimum number of seconds to run all queries: 37.446 seconds
    Maximum number of seconds to run all queries: 37.446 seconds
    Number of clients running queries: 10
    Average number of queries per client: 3000
```

从这点看混合读写的结果相差不大, 多余一点开销可能是由于 proxysql 查询规则的匹配引起的.

#### 编码方面

可以查询管理接口的 mysql_collations 表查看 proxysql 支持的字符集:

```
mysql> select * from mysql_collations where charset like '%utf8%';
+-----+-----------------------+---------+---------+
| Id  | Collation             | Charset | Default |
+-----+-----------------------+---------+---------+
| 33  | utf8_general_ci       | utf8    | Yes     |
| 45  | utf8mb4_general_ci    | utf8mb4 | Yes     |
| 46  | utf8mb4_bin           | utf8mb4 |         |
| 83  | utf8_bin              | utf8    |         |
| 119 | utf8_spanish_ci       | utf8    |         |
| 192 | utf8_general_ci       | utf8    |         |
| 193 | utf8_icelandic_ci     | utf8    |         |
......
......
```

使用 utf8 编码简单测试:

```
$ export LANG="en_US.UTF-8"
$ mysql -h 10.0.21.5 -P 6033 -u percona -p -Bse "create table tags(id int(10) auto_increment primary key, name varchar(50), msg text)"
$ mysql -h 10.0.21.5 -P 6033 -u percona -p -Bse "insert into tags(name, msg) values(\"测试啊\", \"hello 每个人都有的bbbb\")"
$ mysql -h 10.0.21.5 -P 6033 -u percona -p percona -e "select * from tags"
+----+-----------+-------------------------------+
| id | name      | msg                           |
+----+-----------+-------------------------------+
|  1 | 测试啊    | hello 每个人都有的            |
|  2 | 测试啊    | hello 每个人都有的            |
|  3 | 测试啊    | hello 每个人都有的aaaaa       |
|  4 | 测试啊    | hello 每个人都有的bbbb        |
+----+-----------+-------------------------------+
```

相比 360 的 atlas, 编码方面更全面, 另外 proxysql 的 replication_lag_action 接口对主从情况进行监控, 主从出现问题后会自行下线操作, 主从回复后也会自行上线, 监控的频率可以在 proxysql.cnf 中进行配置, 详见 <a href="https://github.com/sysown/proxysql/wiki/Tables-in-Admin-interface">wiki admin</a>

#### FAQ

*proxysql 部署问题*
为防止单点故障, 需要多机部署 proxysql, 可以用 `keepalive` 做冗余, 也可以参考文章开始处的 `consul + dnsmasq + proxysql` 方式构建高可用架构.

*主从故障后 proxysql 如何处理*
可以在配置文件中的 mysql_variables 部分配置 [proxysql-monitor](https://github.com/sysown/proxysql/blob/v1.2.4/doc/monitor.md)  和 ping 相关的参数, 尽管控制的不是很精细但比起手工和脚本操作来好了不少.

*多少人使用?*
最近一年多可以在 [percona](https://www.percona.com) 中看到 percona 对 proxysql 做了很多的推广, 国外公司用的人较多, 国内用的人较少.

#### 其它问题

	管理端口远程连接问题: proxysql 中强制管理接口的 `admin` 用户名只能本地登录, 即通过 `127.0.0.1` 或 `localhost` 等方式连接, 如果要远程登录可以指定管理的用户名不是 `admin` 即可, 详见 [issue1212](https://github.com/sysown/proxysql/issues/1212)

	1.4.1版本后 `query rule` 的正则实现从 `re2` 变为 `pcre`,  规则的大小写可以指定 `CASELESS` 选项进行忽略设置

	新增了集群和 [clickhouse](https://clickhouse.yandex/)

	事务处理问题. 应用程序最好使用 `begin` 或 `start transaction` 显示开启一个事务, 这样事务中的sql 都会发送到写组中. 很多 Spring 框架的 java 程序都使用 `set autocommit = 0; xxxx; commit` 这种方式操作事务, `proxysql` 认为 `set autocommit = 0` 不是开启事务, 所以会出现 [issue1256](https://github.com/sysown/proxysql/issues/1256) 的问题. 可以等待 1.4.4 版本解决该类问题

#### FYI

<p><a href="https://github.com/sysown/proxysql/">github</a>
<p><a href="https://www.percona.com/live/plam16/sessions/proxysql-tutorial">percona live</a>
<p><a href="https://www.percona.com/blog/2016/08/30/mysql-sharding-with-proxysql/">percona blog</a>
<p><a href="http://highdb.com/360-atlas%e4%b8%ad%e9%97%b4%e4%bb%b6-%e6%b5%8b%e8%af%95%e5%8f%8a%e4%bd%bf%e7%94%a8%e8%af%b4%e6%98%8e/">atlas 测试使用</a>
<p><a href="http://highdb.com/mysql-router-%e6%b5%8b%e8%af%95%e4%bd%bf%e7%94%a8/">mysql router 测试使用</a>
