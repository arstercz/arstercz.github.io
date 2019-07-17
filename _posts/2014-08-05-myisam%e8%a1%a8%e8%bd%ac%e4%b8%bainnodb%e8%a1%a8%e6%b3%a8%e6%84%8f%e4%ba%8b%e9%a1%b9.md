---
id: 280
title: MyISAM表转为InnoDB表注意事项
date: 2014-08-05T11:28:59+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=280
permalink: '/myisam%e8%a1%a8%e8%bd%ac%e4%b8%bainnodb%e8%a1%a8%e6%b3%a8%e6%84%8f%e4%ba%8b%e9%a1%b9/'
dsq_thread_id:
  - "3477619836"
ultimate_sidebarlayout:
  - default
dsq_needs_sync:
  - "1"
categories:
  - database
tags:
  - innodb
  - MySQL
---
MyISAM转InnoDB表注意事项

基于引擎存储格式和索引组织方式的不同, 表从MyISAM引擎转换到InnoDB引擎需要注意以下事项:
```
1. AUTO_INCREMENT列不在多列索引的首位的MyISAM表不能转换
```
见 <a href="http://dev.mysql.com/doc/refman/5.5/en/replication-features-auto-increment.html">http://dev.mysql.com/doc/refman/5.5/en/replication-features-auto-increment.html</a> , 包含AUTO_INCREMENT列的InnoDB表, innodb 表中只能设置1个auto 属性的列, 且 auto 列必须定义为 key, 可以是单 key, 也可以是组合 key, 如果是组合key, auto 列必须在最左边; 比如 MyISAM 支持 idx_name_id(`name`, `auto_id`) 的组合索引, 但是 InnoDB 不支持 idx_name_id(`name`, `auto_id`), 却可以支持 auto 列在最左边的情况: idx_id_name(`auto_id`, `name`);
<!--more-->
```
since an InnoDB table with an AUTO_INCREMENT column requires at least one key where the auto-increment column is the only or leftmost column. 
```
```
2. FULLTEXT 全文索引
```
5.6版本以下的MySQL基于InnoDB表还不支持FULLTEXT索引, 此前的版本仅MyISAM支持FULLTEXT索引, 所以存在FULLTEXT索引的MyISAM表不能转换。比如转换时出现以下错误: ERROR 1214 (HY000) at line 1: The used table type doesn't support FULLTEXT indexes. 开发人员可以采用sphix, lucence等第三方的工具实现全文索引，避免在DB端的操作。
```
3. 行记录过大不能转换
```
比如一个表中有很多列, 转为InnoDB的时候出现以下错误:
```
ERROR 1118 (42000) at line 1: Row size too large (> 8126). Changing some columns to TEXT or BLOB or using ROW_FORMAT=DYNAMIC or ROW_FORMAT=COMPRESSED may help. In current row format, BLOB prefix of 768 bytes is stored inline.
```
表列的限制见 <a href="https://dev.mysql.com/doc/refman/5.5/en/column-count-limit.html">https://dev.mysql.com/doc/refman/5.5/en/column-count-limit.html</a> , 因为BLOB和TEXT类型的数据是和其它列分开存放的, errror信息中会提示可以将一些列转为TEXT或BLOB类型, 或者更改行的存储格式也可能会起作用。
```
4. InnoDB不支持Insert delayed语法
```
引自官网: INSERT DELAYED works only with MyISAM, MEMORY, ARCHIVE, and BLACKHOLE tables. For engines that do not support DELAYED, an error occurs.
比如出现错误：
```
ERROR 1616 (HY000): DELAYED option not supported for table 'test'
```
Innodb表在并发和锁方面不像MyISAM,Memory表存在诸多限制, INSERT DELAYED没必要使用到InnoDB表中，诸如delayed的语句可以在应用中改为标准的INSERT语句。
