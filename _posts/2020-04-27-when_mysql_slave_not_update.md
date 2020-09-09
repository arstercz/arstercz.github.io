---
layout: post
title: "什么情况下 MySQL slave 不会更新数据"
tags: [mysql, slave]
comments: false
---

### 什么情况下 MySQL slave 的 sql_thread 线程不会更新数据?

目前主从有两个原因:

### 1. 主从 server-id 相同

如果设置以下选项:
```
replicate-same-server-id = 0
``` 
并且主从的 `server-id` 相同, 则 `sql_thread` 线程会忽略更新收到的数据; 我们应该保证主从配置不同的 `server-id` 值.

### 2. 开启 GTID 的时候

如果开启了 `gtid_mode`, 并在 `master` 中执行了 `reset master`, 则会导致中从中断, 同时 slave 中的 `gtid_next` 还是 `reset master` 操作之前的信息. 这种情况下恢复主从需要考虑以下两个方面:
```
重新设置 slave 中的 gtid_next 参数(无论 slave 是否开启 auto_position);
重新设置 slave 的同步参数信息;
```

如果不重置 slave 中的 `gtid_next` 信息, `master` 中更新的 `gtid` 事务集合编号肯定会小于 slave 中已经收到并执行的 `gtid` 集合编号, 这种情况下就会忽略 master 数据的更新, 直到编号大于 slave 中的信息.
