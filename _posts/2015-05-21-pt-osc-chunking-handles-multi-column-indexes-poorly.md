---
id: 535
title: pt-osc chunking handles multi-column indexes poorly
date: 2015-05-21T12:07:36+08:00
author: arstercz
layout: post
guid: http://zhechen.me/?p=535
permalink: /pt-osc-chunking-handles-multi-column-indexes-poorly/
dsq_thread_id:
  - "3781358332"
categories:
  - database
  - percona
tags:
  - MySQL
  - percona
---
最近使用工具 pt-osc (pt-online-schema-change) 对一张约200w记录多列组成的唯一索引的表进行更改索引操作, 在第一条 chunk 操作的时候就开始报错(版本 pt 2.2.7 和 pt 2.2.11), 如下所示:
```
[root@cz table_check]# pt-online-schema-change --alter="drop key idx_guux, add unique key idx_ugux(user_id,goods_id,updatetime,keycode)" 

A=utf8,h=cz1,P=3306,D=mybase,t=test --ask-pass --execute --nocheck-replication-filters
Enter MySQL password: 
Found 1 slaves:
  cz2
Will check slave lag on:
  cz2
Operation, tries, wait:
  copy_rows, 10, 0.25
  create_triggers, 10, 1
  drop_triggers, 10, 1
  swap_tables, 10, 1
  update_foreign_keys, 10, 1
Altering `mybase`.`test`...
Creating new table...
Created new table mybase._test_new OK.
Waiting forever for new table `mybase`.`_test_new` to replicate to cz2...
Altering new table...
Altered `mybase`.`_test_new` OK.
2015-05-21T10:10:05 Creating triggers...
2015-05-21T10:10:05 Created triggers OK.
2015-05-21T10:10:05 Copying approximately 1957925 rows...
2015-05-21T10:10:05 Dropping triggers...
2015-05-21T10:10:05 Dropped triggers OK.
2015-05-21T10:10:05 Dropping new table...
2015-05-21T10:10:06 Dropped new table OK.
`mybase`.`test` was not altered.
2015-05-21T10:10:05 Error copying rows from `mybase`.`test` to `mybase`.`_test_new`: 2015-05-21T10:10:05 Error copying rows at chunk 1 of mybase.test because MySQL used 

only 306 bytes of the idx_ugux index instead of 505.  See the --[no]check-plan documentation for more information.
```
<!--more-->


表的结构如下, idx_guux 为4个列组成的唯一索引:
```
CREATE TABLE `test` (
  `user_id` varchar(100) NOT NULL DEFAULT '',
  `dispname` varchar(100) DEFAULT NULL,
  `type` tinyint(4) NOT NULL DEFAULT '1',
  `key_id` int(11) NOT NULL DEFAULT '0',
  `goods_id` int(11) NOT NULL DEFAULT '0',
  `updatetime` int(11) DEFAULT NULL,
  `ip` varchar(20) NOT NULL DEFAULT '',
  `keycode` varchar(64) NOT NULL DEFAULT '',
  KEY `idx_goods_uptime` (`goods_id`,`updatetime`),
  UNIQUE KEY `idx_guux` (`goods_id`,`user_id`,`updatetime`,`keycode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8
```

加上 --print 参数看下 pt-osc 到底做了哪些 sql:
```
2015-05-21T10:48:53 Created triggers OK.
2015-05-21T10:48:53 Copying approximately 1964857 rows...
INSERT LOW_PRIORITY IGNORE INTO `mybase`.`_test_new` (`user_id`, `dispname`, `type`, `key_id`, `goods_id`, `updatetime`, `ip`, `keycode`) SELECT `user_id`, `dispname`, `type`, `key_id`, `goods_id`, `updatetime`, `ip`, `keycode` FROM `mybase`.`test` FORCE INDEX(`idx_guux`) WHERE ((`goods_id` > ?) OR (`goods_id` = ? AND `user_id` > ?) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NULL AND `updatetime` IS NOT NULL) OR (`updatetime` > ?))) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NULL AND `updatetime` IS NULL) OR (`updatetime` = ?)) AND `keycode` >= ?)) AND ((`goods_id` < ?) OR (`goods_id` = ? AND `user_id` < ?) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NOT NULL AND `updatetime` IS NULL) OR (`updatetime` < ?))) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NULL AND `updatetime` IS NULL) OR (`updatetime` = ?)) AND `keycode` <= ?)) LOCK IN SHARE MODE /*pt-online-schema-change 7135 copy nibble*/ SELECT /*!40001 SQL_NO_CACHE */ `goods_id`, `goods_id`, `user_id`, `goods_id`, `user_id`, `updatetime`, `updatetime`, `goods_id`, `user_id`, `updatetime`, `updatetime`, `keycode` FROM `mybase`.`test` FORCE INDEX(`idx_guux`) WHERE ((`goods_id` > ?) OR (`goods_id` = ? AND `user_id` > ?) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NULL AND `updatetime` IS NOT NULL) OR (`updatetime` > ?))) OR (`goods_id` = ? AND `user_id` = ? AND ((? IS NULL AND `updatetime` IS NULL) OR (`updatetime` = ?)) AND `keycode` >= ?)) ORDER BY `goods_id`, `user_id`, `updatetime`, `keycode` LIMIT ?, 2 /*next chunk boundary*/
2015-05-21T10:48:53 Dropping triggers...
DROP TRIGGER IF EXISTS `mybase`.`pt_osc_mybase_test_del`;
DROP TRIGGER IF EXISTS `mybase`.`pt_osc_mybase_test_upd`;
DROP TRIGGER IF EXISTS `mybase`.`pt_osc_mybase_test_ins`;
```

这里的 select 查询用到了 FORCE INDEX(`idx_ggux`), pt-osc 默认情况下为保证数据安全使用 --check-plan参数检查 query的执行计划(优先选择能够对表进行 chunk 分组的索引), 提示信息  See the --[no]check-plan documentation for more information, 告诉我们可以指定 --nocheck-plan 跳过检测query的执行, 选用其它的索引, 如果其它索引不能满足 chunk 分组的条件, 也会执行失败(或者执行特别慢), 本例中指定 -nocheck-plan 参数后的sql 为:
```
2015-05-21T10:51:36 Created triggers OK.
2015-05-21T10:51:36 Copying approximately 1964857 rows...
INSERT LOW_PRIORITY IGNORE INTO `mybase`.`_test_new` (`user_id`, `dispname`, `type`, `key_id`, `goods_id`, `updatetime`, `ip`, `keycode`) SELECT `user_id`, `dispname`, `type`, `key_id`, `goods_id`, `updatetime`, `ip`, `keycode` FROM`mybase`.`test` FORCE INDEX(`idx_goods_uptime`) WHERE ((`goods_id` > ?) OR (`goods_id` = ? AND (? IS NULL OR `updatetime` >= ?))) AND ((`goods_id` < ?) OR (`goods_id` = ? AND (? IS NULL OR `updatetime` <= ?))) LOCK IN SHARE MODE /*pt-online-schema-change 23939 copy nibble*/SELECT /*!40001 SQL_NO_CACHE */ `goods_id`, `goods_id`, `updatetime`, `updatetime` FROM `mybase`.`test` FORCE INDEX(`idx_goods_uptime`) WHERE ((`goods_id` > ?) OR (`goods_id` = ? AND (? IS NULL OR `updatetime` >= ?))) ORDER BY `goods_id`, `updatetime` LIMIT ?, 2 /*next chunk boundary*/
```

这里选用了 FORCE INDEX(`idx_goods_uptime`) 进行分组处理.

为什么会出现这种情况?, 作者 Daniel Nichter做了以下解释:
pt-osc 工具采用了分组迭代(NibbleIterator)的方法进行实现, 虽然早就发现了这个问题, 但是一直没有处理, 因为分组(nibbling/chunking)实现很复杂, 不好修改. 3个原因可能会引起上述的问题:

1. 使用分组迭代需要拆分 where 条件中多列索引, 有3个列以上的索引, pt-osc工具大部分情况下会对where 条件做多余的预测(--[no]check-plan选项);
2. MySQL的查询计划或优化器会忽略掉多余的部分, 并且只是用索引的前缀部分, 只使用部分索引就是引起 "only 306 bytes of the idx_ugux index instead of 505" 的原因, pt-osc 增加了 --[no]check-plan 来检测这种情况的发生，因为这种情况不会总是发生(这也是第三个原因);

这种情况有时会让 MySQL 感到迷惑, 1,2种情况类似在 pt-osc 工具中指定了 --chunk-index-columns选项; 当使用了索引的一部分的时候, 就成了索引扫描(index scan), 这种情况对大表有很大的影响, 因为 index scan 操作代价很大, 这也是使用 --nocheck-plan 参数可能会出现 "Row are copying very slowly"的情况. 当然这种问题出现的几率较少, 作者更倾向于在 pt 3.0版本进行处理.

所以到目前为止, 最好使用 pt-osc工具对简单的索引或只有 1,2列的索引进行修改, 如果有3列以上的索引需要修改, 需要保证表中还有其它索引满足 chunk 分组的条件, 这时就可以使用 --nocheck-plan 选项处理, 或使用 --chunk-index 指定优先选择的索引.

详见: <a href="https://bugs.launchpad.net/percona-toolkit/+bug/1130498">https://bugs.launchpad.net/percona-toolkit/+bug/1130498</a>