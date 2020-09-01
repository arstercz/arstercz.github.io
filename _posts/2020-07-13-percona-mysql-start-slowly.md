---
layout: post
title: "为什么 Percona MySQL 开启 NUMA 选项后启动很慢"
tags: [mysql]
comments: true
---


最近在使用新版本 [Percona MySQL](https://www.percona.com/software/mysql-database/percona-server) 的时候, 发现启动巨慢, 且启动时间随 `innodb_buffer_pool_size` 的大小成正比, 配置的 `innodb_buffer_pool_size` 值越大, 启动时间就越长, 所耗时间约为 `T = innodb_buffer_pool_size(GB)`, 如下所示, 我们将 `innodb_buffer_pool_size` 配置的足够大, 就会发现实例启动耗时约 `440s`: 

```
Jul  7 12:00:44 mysqld-3301[95109]: InnoDB: Initializing buffer pool, total size = 432G, instances = 24, chunk size = 256M
Jul  7 12:00:44 mysqld-3301[95109]: InnoDB: Setting NUMA memory policy to MPOL_INTERLEAVE
Jul  7 12:08:04 mysqld-3301[95109]: InnoDB: Setting NUMA memory policy to MPOL_DEFAULT
Jul  7 12:08:04 mysqld-3301[95109]: InnoDB: Completed initialization of buffer pool
```

可以看到消耗的时间主要在设置 NUMA 策略这步:
```
InnoDB: Setting NUMA memory policy to MPOL_INTERLEAVE
```

## 为什么要修改 NUMA 策略?

目前主流的服务器基本都是 [NUMA](https://en.wikipedia.org/wiki/Non-uniform_memory_access) 架构, 比起过去的 [SMP](https://en.wikipedia.org/wiki/Symmetric_multiprocessing) 架构, `NUMA` 在 CPU 和内存利用率方面都有很大的提升. 不过 NUMA 架构对内存占用较多的应用(比如数据库等)存在一些性能方面的影响, 比较知名的有 [MySQL swap insanity](https://blog.jcole.us/2012/04/16/a-brief-update-on-numa-and-mysql/), 简单概括此问题即是 `当你把主机大部分内存分配给InnoDB时，你会发现明明操作系统还有很多内存，但是却有很多内存被交换到了 SWAP 分区`. 

为什么会发生这样的问题? 主要的原因在于 MySQL 使用的内存超过了 NUMA 架构中单颗 CPU 对应的内存, 如下所示:

```
# numactl -H
available: 2 nodes (0-1)
node 0 cpus: 0 2 4 6 8 10
node 0 size: 32722 MB
node 0 free: 24803 MB
node 1 cpus: 1 3 5 7 9 11
node 1 size: 32768 MB
node 1 free: 28378 MB
```

每颗 `CPU node` 对应一半的内存(32G). 如果 MySQL 的内存超过 32G 就会产生上述的 `swap insanity` 问题. 更多描述可以参考以前的文章 [MySQL numa交叉模式启动说明]({{ site.baseurl }}/mysql-numa%e4%ba%a4%e5%8f%89%e6%a8%a1%e5%bc%8f%e5%90%af%e5%8a%a8%e8%af%b4%e6%98%8e/). 

避免产生此类问题的方式目前主要就是修改 MySQL 的占用内存的策略, 保证可以使用每颗 CPU 对应的内存. MySQL 对 NUMA 的支持主要经过了以下阶段:

```
 numactl(命令行)  ->  numa_interleave(mysqld_safe 脚本) -> innodb_numa_interleave(mysqld 选项)

 ```

 新版本的选项 `innodb_numa_interleave` 即可设置 MySQL 在启动的时候将 NUMA 内存策略从默认的 `MPOL_DEFAULT` 策略修改为 `MPOL_INTERLEAVE` 交互模式, 更多策略见 [numa_memory_policy](https://www.kernel.org/doc/html/latest/admin-guide/mm/numa_memory_policy.html#components-of-memory-policies). 通过 `INTERLEAVE` 策略完成内存分配后, MySQL 又会将策略修改回默认的 `DEFAULT` 策略, 如下官方说明:

 ```
 Enables the NUMA interleave memory policy for allocation of the InnoDB buffer pool. 
 When innodb_numa_interleave is enabled, the NUMA memory policy is set to MPOL_INTERLEAVE 
 or the mysqld process. After the InnoDB buffer pool is allocated, the NUMA memory policy
 is set back to MPOL_DEFAULT. 
 ```

## 为什么启动很慢?

在 [percona-PS-3967](https://jira.percona.com/browse/PS-3967) 的问题中, 自从 Oracle 官方引入 `innodb_numa_interleave` 功能后, Percona 版本之前的 `NUMA` 策略并没有生效, 为了解决这个问题, Percona 从以下版本开始在启用 `NUMA INTERLEAVE` 策略的时候一并通过 `mmap` 的 `MAP_POPULATE` 标记预先分配 `innodb_buffer_pool_size` 指定的内存:

| 主版本 | 生效版本 |
| :-: | :-: |
| 5.6 | >= 5.6.40-83.2 |
| 5.7 | >= 5.7.22-22 |

这意味着 MySQL 在启动的时候就会预先占用 `innodb_buffer_pool_size` 指定的大小的内存, 指定的越大, 分配的时间就会越长, 如下所示:
```
Feature reverted from the upstream implementation back to the one ported from Percona Server 5.6, 
in which innodb_numa_interleave variable not only enables NUMA memory interleaving at InnoDB buffer
pool allocation, but allocates buffer pool with MAP_POPULATE, forcing interleaved allocation at 
the buffer pool initialization time.
```

再回到我们最开始的问题, 分配的 `innodb_buffer_pool_size` 为 432G, 启动时间约为 440s, mmap 平均每秒分配约 1G 左右的内存.

## 如何避免启动慢的问题?

实际上我们很少对数据库进行重启操作, 即便启动很慢, 影响也是很小. 不过如果想加快启动速度, 可以试着从以下几方面着手:

#### 1. 降低 innodb_buffer_pool_size

尽量不要将此参数设置的过大, 如果数据很多能拆库尽量拆库.

#### 2. 关闭  innodb_numa_interleave

如果实例使用的内存远小于单颗 cpu 对应的内存, 可以考虑关闭 numa 策略. 很多云主机实例仅一颗 `CPU node`, 无法开启 numa 的平衡策略(`kernel.numa_balancing`), 这种情况下就无需开启 `innodb_numa_interleave` 选项.

#### 3. 保存 buffer pool

参考以下配置, 通过保存 `buffer pool` 状态加快启动过程, 同时也节省了不少数据预热的时间:

```
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_at_shutdown = 1
innodb_buffer_pool_dump_pct = 60
```

更多见: [Saving and Restoring the Buffer Pool State](https://dev.mysql.com/doc/refman/5.7/en/innodb-preload-buffer-pool.html)  

#### 4. 使用低版本 MySQL

如上所述的版本变更, 我们可以使用较低的版本, 不过可能出现 [PS-3967](https://jira.percona.com/browse/PS-3967) 不生效的问题. 从笔者的使用经验来看, 可以参考以下版本:

```
percona mysql 5.6.38
percona mysql 5.7.19
```

#### 5. 开启 large-page

可以考虑将共享缓存分配给 `innodb buffer pool`, MySQL 指定 `large page` 功能后, 就不需要通过 mmap 预分配指定的 `innodb_buffer_pool_size` 大小的缓存. 这种方式的启动时间和使用低版本的 MySQL 等同. 开启 `large-page` 的过程可参考: [configuring-huge-page-for-MySQL](https://www.linkedin.com/pulse/configuring-huge-pages-mysql-server-red-hat-linux-juan-soto/), [large-page-support](https://dev.mysql.com/doc/refman/5.7/en/large-page-support.html).  

## 参考

[a-brief-update-on-numa-and-mysql](https://blog.jcole.us/2012/04/16/a-brief-update-on-numa-and-mysql/)  
[5.6-innodb_numa_support](https://www.percona.com/doc/percona-server/5.6/performance/innodb_numa_support.html)  
[5.7-innodb_numa_support](https://www.percona.com/doc/percona-server/5.7/performance/innodb_numa_support.html)  
[percona_PS-3967](https://jira.percona.com/browse/PS-3967)  
[taobao-2015-07-05](http://mysql.taobao.org/monthly/2015/07/06/)  
[numa_memory_policy](https://www.kernel.org/doc/html/latest/admin-guide/mm/numa_memory_policy.html#components-of-memory-policies)  

