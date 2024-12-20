---
layout: post
title: "numa 简单使用汇总"
tags: [numa]
comments: true
---

目前主流的物理服务(包括一些云厂商的高配 vm 机器)架构大多是 [NUMA](https://en.wikipedia.org/wiki/Non-uniform_memory_access) 架构, `NUMA` 在 CPU 和内存使用方面有很大的优势. 不过它的一些策略以及本地, 远端的访问模式可能造成一些意料之外的问题, 可以参考文章 [percona-mysql-start-slowly](https://blog.arstercz.com/percona-mysql-start-slowly/) 了解更多. 本文则对 numa 及使用做一些简单汇总.

## 系统参数控制

内核提供的 `numa_balancing` 参数可以控制系统的行为. 有个例外是进程如果指定了 `numa` 的 node 节点, 就应该 disable 该系统参数.
```
kernel.numa_balancing = 1

Enables/disables automatic page fault based NUMA memory
balancing. Memory is moved automatically to nodes
that access it often.

When this feature is enabled the kernel samples what task thread is 
accessing memory by periodically unmapping pages and later trapping 
a page fault. At the time of the page fault, it is determined if the 
data being accessed should be migrated to a local memory node.

The unmapping of pages and trapping faults incur additional overhead that
ideally is offset by improved memory locality but there is no universal
guarantee. If the target workload is already bound to NUMA nodes then this
feature should be disabled. Otherwise, if the system overhead from the
feature is too high then the rate the kernel samples for NUMA hinting
faults may be controlled by the numa_balancing_scan_period_min_ms,
numa_balancing_scan_delay_ms, numa_balancing_scan_period_max_ms,
numa_balancing_scan_size_mb, and numa_balancing_settle_count sysctls.
```

## 控制 numa 策略

### 命令行控制

早期的时候, 机器配置都不是很高. 很多占用内存的进程(比如 mysql)都可以通过 numactl 命令控制内存策略, 如下所示, 允许进程可以使用远端的内存:
```
numactl --interleave=all <program> <args>
```

### 系统调用控制

程序可以在代码层级控制策略, 如下 c 语言示例:
```c
#include <stdio.h>
#include <stdlib.h>
#include <numaif.h>

int main() {
    // Set the memory policy to interleave
    struct bitmask* numa_nodes = numa_get_mems_allowed();
    int ret = set_mempolicy(MPOL_INTERLEAVE, numa_nodes->maskp, numa_nodes->size);

    if (ret != 0) {
        perror("set_mempolicy");
        exit(1);
    }

    // Now, subsequent memory allocations will be biased towards node 1
    int *ptr = malloc(1024);

    // ... other code ...

    return 0;
}
```

> 备注: 早期的 MySQL 版本(`5.1, 5.5`) 使用命令行方式解决 numa 问题, 新的版本则使用系统调用方式(可以搜索 `set_mempolicy` 函数). 

## 查看 numa 状态

```
# numa 内存分配情况

$ numactl -H
available: 2 nodes (0-1)
node 0 cpus: 0 2 4 6 8 10 12 14 16 18 20 22
node 0 size: 15836 MB
node 0 free: 928 MB
node 1 cpus: 1 3 5 7 9 11 13 15 17 19 21 23
node 1 size: 16123 MB
node 1 free: 4177 MB
node distances:
node   0   1 
  0:  10  20 
  1:  20  10


# numa 内存使用情况

$ numastat 
                           node0           node1
numa_hit             18136592413     17603414333
numa_miss              938561440      4793700752
numa_foreign          4793700752       938561440
interleave_hit            568140          568108
local_node           18216194200     11673197270
other_node             858959653     10723917815
```

> 可以查看 numa 状态, 以确定按什么方式开启策略, 当然最好能够提前在测试环境中尝试此类操作.

## 参考

[memory-deep-dive-numa-data-locality](https://frankdenneman.nl/2015/02/27/memory-deep-dive-numa-data-locality/)  

