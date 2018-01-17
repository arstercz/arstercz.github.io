---
id: 550
title: '了解 select count(*), count(1) 和 count(field)'
date: 2015-06-30T15:32:26+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=550
permalink: '/%e4%ba%86%e8%a7%a3-select-count-count1-%e5%92%8c-countfield/'
dsq_thread_id:
  - "3891445266"
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - MySQL
  - sql
---
我们以 MySQL 中的聚合函数 count 来说明 count(*), count(1) 和 count(field) 三者之间的关系以及背后的原理. 

<strong>概念</strong>

<a href="http://dev.mysql.com/doc/refman/5.6/en/group-by-functions.html#function_count">http://dev.mysql.com/doc/refman/5.6/en/group-by-functions.html#function_count</a>

COUNT(expr) 函数返回 select 语句中表达式 expr 非 null 值的数量, 返回值类型为 bigint.
<pre>
Returns a count of the number of non-NULL values of expr in the rows retrieved by a SELECT statement. The result is a BIGINT value. 
</pre> 
<!--more-->


<strong>区别</strong>

从概念上理解 COUNT() 函数返回非 null 值的数量, 如果为 null 则不计数, 反之, 开始计数. 比如以下:
<pre>
mysql root@[localhost:s3306 employees] > select count(null) from dual;
+-------------+
| count(null) |
+-------------+
|           0 |
+-------------+
1 row in set (0.00 sec)
</pre>
 
注: dual 为 MySQL 提供的隐含表. 一些数据库查询的时候不能没有 from 子句, Oracle 和 MySQL 都提供了 dual 隐含表用来满足只调用函数的语句, 比如 select now() from dual;

从这点看 count(*) 和 count(1) 实际的意思是获取表中的行数, count(field) 特别些, 因为 field 列可能含有 NULL 值. 下面的对比转换可能更好的说明问题:
<pre>
count(*)     --> select * from ... where ...
count(1)     --> select 1 from ... where ...
count(field) --> select field from ... where ...
</pre>
不要被 MySQL 中的 ORDER BY 1, 2 语句所影响, ORDER by 中的 1 表示select 列中的位置信息, 比如 order by 1 表示按照 select ... from 中的第一个列进行排序, count(1) 中的 1 是一个常量, 如同我们执行 select 1, select 100 本质上没有区别. 上面的转换中, 在相同的 where 条件中, select * 和 select 1 是等同的,都返回该条件下的行数, select field 可能因为 null 值的原因返回数量变小.

对于查询 select count(*) from table, 不同的存储引擎会有什么影响?
在没有 where 条件的情况下:
<pre>
MyISAM表: MyISAM表的索引组织包含的行数信息, MySQL 只需要返回索引最右边的值即可, 这种情况下速度是很快的, count(1)也同理;
InnoDB表: InnoDB索引组织没有行信息, MySQL 需要统计所有的行数, 这点比起 MyISAM差很多. 所以如果表有很多不带 where 条件的 count查询, 可以将表转为 MyISAM引擎来提升性能.
</pre>
在有 where 条件的情况下:
<pre>
MySQL 按条件统计所有的行数, 即便表的所有列都为null, 也会通过行记录中的银行 rowid 进行统计.
</pre>

<strong>执行</strong>

上面描述了 count(*) 和 count(1)等同, 我们使用以下的表进行测试, 看看count 如何执行:
<pre>
CREATE TABLE `employees` (
  `emp_no` int(11) NOT NULL,
  `birth_date` date NOT NULL,
  `first_name` varchar(14) NOT NULL,
  `last_name` varchar(16) NOT NULL,
  `gender` enum('M','F') NOT NULL,
  `hire_date` date NOT NULL,
  PRIMARY KEY (`emp_no`),
  KEY `inx_date` (`birth_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
</pre>

根据上述信息, 我们可以想象对一个没有索引的表进行 count 操作, 只能通过全表扫描来统计行信息.如果表有索引, MySQL首先会使用索引进行行的统计, 也可能直接选择主键进行统计(如果只有主键索引的话), 因为主键本身就是 非 NULL 值,  如下所示, 优化器选择 inx_date索引进行统计:
<pre>
mysql root@[localhost:s3306 employees] > explain select sql_no_cache count(*) from employees\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: employees
         type: index
possible_keys: NULL
          key: inx_date
      key_len: 3
          ref: NULL
         rows: 294478
        Extra: Using index
1 row in set (0.00 sec)
</pre>
另外, innodb表的索引组织方式中, 第二索引包含的主键的指针, 这意味着即便索引列的值可以为 NULL, 但也保存着主键的信息，同样可以用来统计行数, 比如:
<pre>
mysql root@[localhost:s3306 employees] > alter table employees modify column hire_date date;
Query OK, 294025 rows affected (4.30 sec)
Records: 294025  Duplicates: 0  Warnings: 0

mysql root@[localhost:s3306 employees] > insert into employees values(500000, null, 'zhe', 'chen', 'F', '2015-06-30');
Query OK, 1 row affected (0.00 sec)

mysql root@[localhost:s3306 employees] > explain select sql_no_cache count(*) from employees\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: employees
         type: index
possible_keys: NULL
          key: inx_date
      key_len: 3
          ref: NULL
         rows: 293527
        Extra: Using index
1 row in set (0.00 sec)
</pre>
也可以强制指定主键进行统计:
<pre>
mysql root@[localhost:s3306 employees] > explain select sql_no_cache count(*) from employees force index(primary)\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: employees
         type: index
possible_keys: NULL
          key: PRIMARY
      key_len: 4
          ref: NULL
         rows: 293527
        Extra: Using index
1 row in set (0.00 sec)
</pre>

count(filed) 如何执行?
如果 filed 列没有索引, 不带 where 条件的 count(filed) 只能全表扫面,因为主键不包含列是否为 NULL 的信息, 这种情况特别耗时; 反之则使用相关的索引或该列的索引(如果有的话). 如果有where 条件, 条件中最好包含索引行， 否则和全表扫描一样, 如下制定主键为过滤条件:
<pre>
mysql root@[localhost:s3306 employees] > explain select sql_no_cache count(birth_date) from employees\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: employees
         type: index
possible_keys: NULL
          key: inx_date
      key_len: 4
          ref: NULL
         rows: 295146
        Extra: Using index
1 row in set (0.00 sec)

mysql root@[localhost:s3306 employees] > explain select sql_no_cache count(first_name) from employees where emp_no < 300000\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: employees
         type: range
possible_keys: PRIMARY
          key: PRIMARY
      key_len: 4
          ref: NULL
         rows: 147573
        Extra: Using where
1 row in set (0.00 sec)
</pre>

<strong>总结</strong>

coun(*) 和 count(1) 本质上相同, 都返回满足条件的行数, 对不同的存储引擎以及不同的 where 条件得到的响应时间可能有很大差别. 
不同的索引对 count 的执行有很大的影响, 使用索引和全表扫描在结果上一致, 但是响应速度差别很大.
如果要统计行数, 使用 count(*) 和 count(1)都一样, count(filed) 需要保证 filed 没有 NULL 值.
