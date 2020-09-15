---
layout: post
title: "为什么 DISTINCT 返回错误的结果"
tags: [mysql]
comments: true
---

## 问题说明

在通过 `SELECT DISTINCT` 进行查询的时候发现结果一直返回空, 然而通过 `SELECT` 却能返回正常的结果, 如下所示:

```sql
-- Server version: 5.6.38-83.0-log Percona Server

mysql > select distinct(name) from t_web_column where column_id IN (946390, 946391, 946392, 946393);
Empty set (0.00 sec)

mysql > select name from t_web_column where column_id IN (946390, 946391, 946392, 946393);
+------+
| name |
+------+
| Test |
| Test |
| Test |
| Test |
+------+
```

表结构则相对简单, 通过 `EXPLAIN` 查看, `Extra` 列显示 `Using index for group-by` 信息:
```sql
CREATE TABLE `t_web_column` (
  `column_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(200) DEFAULT NULL,
  `column` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`column_id`),
  UNIQUE KEY `index` (`name`,`column`),
  KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8

mysql > explain distinct(name) from t_web_column where column_id IN (946390, 946391, 946392, 946393)\G
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: t_web_column
         type: range
possible_keys: PRIMARY,index
          key: index
      key_len: 603
          ref: NULL
         rows: 13
        Extra: Using where; Using index for group-by
```

从 [mysql-bug-87598](https://bugs.mysql.com/bug.php?id=87598) 来看, 这可能是因为 `Using index for group-by` 特性引起的问题. 下面则简单介绍为什么会出现该问题.

## `Using index for group-by` 是什么

MySQL 的优化器对 `GROUP BY` 相关的优化中, 通过以下方式实现数据的扫描:
```
Loose Index Scan(稀疏索引扫描)
Tight Index Scan(紧凑索引扫描)
```
实际上, `SELECT DISTINCT` 也是隐含的 `GROUP BY` 行为, SQL 检索的数据直接可以从索引获取并且是有序的, 则优化器就只需要检索一部分数据即可得到结果. 这种即为稀疏索引扫描, 使用这种方式, 通过 `EXPLAIN` 查看的时候 `Extra` 列就会显示以下信息:
```
Using index for group-by
``` 

更多见: [mysql-group-by-optimization](https://dev.mysql.com/doc/refman/8.0/en/group-by-optimization.html)  

## 为什么返回空结果

参考官方 [mysql-bug-87207](https://bugs.mysql.com/bug.php?id=87207) 给出的信息来看:

```
Incorrect results could occur on a table with a unique index when the
optimizer chose a loose index scan even though the unique index had
no index extensions.
```

产生此类问题需要满足两个条件:
```
1. 表中含有唯一键;
2. 优化器使用稀疏索引, 并且错误的选择了唯一键;
```

解决该问题也很简单, 参考官方的提交 [git-commit-7352f13](https://github.com/mysql/mysql-server/commit/7352f13a4952691191f31ec2ad4b004d568734e4) 信息, 不再对唯一索引增加索引扩展:
```
Solution:
---------
Index extensions are not applicable to UNIQUE indexes for
loose index scans.

So Field::is_part_of_actual_key should also consider the
HA_NOSAME flag.
``` 

## 如何避免此类问题?

实际的业务中, 可以通过以下两种方式解决:

#### 临时修改参数

可以在查询前关闭索引扩展, 禁止使用 `Using index for group-by`:
```sql
set optimizer_switch='use_index_extensions=off';
```
或者直接关闭全局变量:
```sql
set global optimizer_switch='use_index_extensions=off';
```

当然, 我们同样需要了解关闭 `use_index_extensions` 会产生什么影响? 索引扩展主要用于 InnoDB 引擎中, 其会自动将主键扩展到第二索引中, 加速一些比如 `ref, range, index_merge` 之类的 sql 查询. 我们在实际的业务使用中, 如果存在合适的索引, 关闭索引扩展是不会有任何问题的, 更多可以参考 [mysql-index-extension](https://dev.mysql.com/doc/refman/5.6/en/index-extensions.html).  

#### 升级版本

参考 [mysql-bug-87207](https://bugs.mysql.com/bug.php?id=87207), 可以升级到下述或之上的版本彻底解决此类问题:
```
Fixed in 
  5.6.39
  5.7.21
  8.0.4
```

## 参考

[mysql-bug-87207](https://bugs.mysql.com/bug.php?id=87207)  
[mysql-bug-87598](https://bugs.mysql.com/bug.php?id=87598)  
[percona-PS-1820](https://jira.percona.com/browse/PS-1820)  
