---
id: 1159
title: linux 系统 page allocation failure 问题处理
date: 2019-04-28T16:16:21+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1159
permalink: '/linux-%e7%b3%bb%e7%bb%9f-page-allocation-failure-%e9%97%ae%e9%a2%98%e5%a4%84%e7%90%86/'
categories:
  - system
tags:
  - kernel
  - page
---
## 问题说明

近期一台主机报以下 `kernel` 警告信息:
```
Apr 28 05:30:51 cztest kernel: swapper/13: page allocation failure: order:5, mode:0x4020 
Apr 28 05:30:51 cztest kernel: Pid: 0, comm: swapper/13 Not tainted 3.4.24-x86_64
 #3 
Apr 28 05:30:51 cztest kernel: Call Trace: 
Apr 28 05:30:51 cztest kernel:  <IRQ>  [<ffffffff8109b77b>] warn_alloc_failed+0xeb/0x130 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8105611e>] ? __wake_up+0x4e/0x70 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8109c7c2>] __alloc_pages_nodemask+0x632/0x7e0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff810d0d35>] kmalloc_large_node+0x55/0xa0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff810d22ab>] __kmalloc_node_track_caller+0xeb/0x100 
Apr 28 05:30:51 cztest kernel:  [<ffffffff814467db>] ? skb_copy+0x3b/0xa0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff81445835>] __alloc_skb+0x75/0x170 
Apr 28 05:30:51 cztest kernel:  [<ffffffff814467db>] skb_copy+0x3b/0xa0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff813934b9>] tg3_start_xmit+0xa49/0xd80 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8144e133>] ? dev_gro_receive+0x1b3/0x2b0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8144f10d>] dev_hard_start_xmit+0x24d/0x5f0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff81468367>] sch_direct_xmit+0xf7/0x1d0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff814684ea>] __qdisc_run+0xaa/0x130 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8144b85e>] net_tx_action+0xce/0x190 
Apr 28 05:30:51 cztest kernel:  [<ffffffff81038529>] __do_softirq+0x99/0x130 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8152c509>] ? _raw_spin_lock+0x9/0x10 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8152e49c>] call_softirq+0x1c/0x30 
Apr 28 05:30:51 cztest kernel:  [<ffffffff81003e55>] do_softirq+0x65/0xa0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8103829e>] irq_exit+0x8e/0xb0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff810035a1>] do_IRQ+0x61/0xe0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8152c96a>] common_interrupt+0x6a/0x6a 
Apr 28 05:30:51 cztest kernel:  <EOI>  [<ffffffff8100a153>] ? mwait_idle+0x63/0x80 
Apr 28 05:30:51 cztest kernel:  [<ffffffff8100a4d9>] cpu_idle+0x89/0xd0 
Apr 28 05:30:51 cztest kernel:  [<ffffffff815232c8>] start_secondary+0x1ac/0x1b1 
...
Apr 28 05:30:51 cztest kernel: active_anon:6434276 inactive_anon:1 isolated_anon:0 
Apr 28 05:30:51 cztest kernel:  active_file:4209869 inactive_file:5472663 isolated_file:0 
Apr 28 05:30:51 cztest kernel:  unevictable:0 dirty:0 writeback:0 unstable:0 

Apr 28 05:30:51 cztest kernel:  free:48236 slab_reclaimable:183007 slab_unreclaimable:14023 
Apr 28 05:30:51 cztest kernel:  mapped:9411 shmem:1 pagetables:14374 bounce:0 
Apr 28 05:30:51 database kernel: Node 0 DMA free:15920kB min:4kB low:4kB high:4kB active_anon:0kB inactive_anon:0kB active_file:0kB inactive_file:0kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:15664kB mlocked:0kB dirty:0kB writeback:0kB mapped:0kB shmem:0kB slab_reclaimable:0kB slab_unreclaimable:0kB kernel_stack:0kB pagetables:0kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:0 all_unreclaimable? yes 
Apr 28 05:30:51 database kernel: lowmem_reserve[]: 0 3203 32183 32183 
Apr 28 05:30:51 database kernel: Node 0 DMA32 free:120772kB min:1612kB low:2012kB high:2416kB active_anon:980332kB inactive_anon:0kB active_file:914628kB inactive_file:1095816kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:3280064kB mlocked:0kB dirty:0kB writeback:0kB mapped:428kB shmem:0kB slab_reclaimable:137848kB slab_unreclaimable:5708kB kernel_stack:696kB pagetables:2268kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:0 all_unreclaimable? no 
Apr 28 05:30:51 database kernel: lowmem_reserve[]: 0 0 28980 28980
Apr 28 05:30:51 cztest kernel: Node 0 Normal free:36276kB min:14608kB low:18260kB high:21912kB active_anon:13860108kB inactive_anon:4kB active_file:5225004kB inactive_file:10006192kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:29675520kB mlocked:0kB dirty:0kB writeback:0kB mapped:25740kB shmem:4kB slab_reclaimable:222264kB slab_unreclaimable:27504kB kernel_stack:1304kB page
tables:30084kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:2 all_unreclaimable? no 
Apr 28 05:30:51 cztest kernel: lowmem_reserve[]: 0 0 0 0 
Apr 28 05:30:51 cztest kernel: Node 1 Normal free:19976kB min:16260kB low:20324kB high:24388kB active_anon:10896664kB inactive_anon:0kB active_file:10699844kB inactive_file:10788644kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:33030144kB mlocked:0kB dirty:0kB writeback:0kB mapped:11476kB shmem:0kB slab_reclaimable:371916kB slab_unreclaimable:22880kB kernel_stack:1392kB pag
etables:25144kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:0 all_unreclaimable? no 
```

该主机的环境如下:
```
      System | Dell Inc.; PowerEdge R620; vNot Specified (Rack Mount Chassis)
    Platform | Linux
      Kernel | 3.4.24
Total Memory | 64G
```

## 处理说明

该主机内存的占用情况如下:
```
05:00:01 AM kbmemfree kbmemused  %memused kbbuffers  kbcached kbswpfree kbswpused  %swpused  kbswpcad
05:00:01 AM   1578652  64357004     97.61         0  37448504         0         0      0.00         0
05:10:01 AM    525044  65410612     99.20         0  38365896         0         0      0.00         0
05:20:01 AM    515644  65420012     99.22         0  38382032         0         0      0.00         0
05:30:01 AM    426808  65508848     99.35         0  38460508         0         0      0.00         0
05:40:01 AM   1544476  64391180     97.66         0  37479036         0         0      0.00         0
05:50:02 AM   1536244  64399412     97.67         0  37489504         0         0      0.00         0
```

看起来 `5:30` 之后做了内存回收, 另外从堆栈的调用情况来看, 引起内存页分配失败的原因在于网络传输, 主机将接收或要发送的数据 `copy` 到内存中, 开始分配大内存, 不过内存不够出现内存分配失败的堆栈信息:
```
net_tx_action -> tg3_start_xmit -> skb_copy -> kmalloc_large_node -> warn_alloc_failed
```

上述的 `kernel` 信息中也包含了不同内存区域的详细信息, 如下所示为 linux 中常见的内存区域:

| **内存区域** | **说明** |
|::|::|
| ZONE_DMA | 此区域包含的页用来执行 DMA(直接内存访问) 操作 |
| ZONE_DMA32 | 和 ZONE_DMA 类似, 不过其中的页只能被 32 位设备访问 |
| ZONE_NORMAL | 可以正常映射的页, 用户空间程序使用此区域的页 |
| ZONE_HIGHMEM | 高端内存, 其中的页不能永久映射到内核地址空间, 64 位体系结构中所有内存都可以被映射, 所以 x86-64 的机器不存在高端内存 |

内核在分配物理内存时, 从高端(`HIGHMEM`)到低端(`DMA`)依次查找是否有足够的内存可以分配, 找到可用的内存后编映射到虚拟地址上供程序使用, 不过低端的内存较少, 如果低端的内存区域被占满, 就算剩余的物理内存很大，可能还会会出现 `oom` 或 `page allocation failure` 的情况.

DMA 内存区域很小, 所以我们主要关注 DMA32 和 NORMAL 的内存区域, 如下所示为 NODE0, NODE1 两颗 cpu 对应的 NORMAL 内存区域的详细信息:
```
Node 0 DMA free:15920kB min:4kB low:4kB high:4kB dirty:0kB shmem:0kB slab_reclaimable:0kB slab_unreclaimable:0kB
Node 0 DMA32 free:120772kB min:1612kB low:2012kB high:2416kB dirty:0kB shmem:0kB slab_reclaimable:137848kB slab_unreclaimable:5708kB
Node 0 Normal free:36276kB min:14608kB low:18260kB high:21912kB dirty:0kB shmem:4kB slab_reclaimable:222264kB slab_unreclaimable:27504kB
Node 1 Normal free:19976kB min:16260kB low:20324kB high:24388kB dirty:0kB shmem:0kB slab_reclaimable:371916kB slab_unreclaimable:22880kB
```

这台主机的 `vm.min_free_kbytes` 为 `32496`, 对于 `vm.min_free_kbytes` 参数而言, linux 会根据此参数的值计算每颗 CPU 对应的每个内存区域的(low, high)水位值. 低于 low 的值时, kswapd 进程开始执行 reclaim 操作, 低于 min 的值时, 内核直接执行 reclaim 操作. kswapd 和内核执行 reclaim 操作的区别在于前者是在后台执行, 后者直接在前台执行, 所以在可用内存低于 min 值的时候, 系统可能出现卡顿的现象. 

*备注:* 可以手动触发输出当前系统的内存使用信息到系统 message:
```
echo m > /proc/sysrq-trigger
```

另外 `vm.lowmem_reserve_ratio` 参数对各个内存区域提供了防卫作用, 主要可以防止高端区域在没有内存的情况下过度使用低端区域的内存资源. 所以下面的公式也决定了本内存区域是否同意分批内存给更高端的内存分配请求, 下面的等式成立则拒绝分配:
```
# 内存区域
watermark + protection[i] > free_page
```
可以从内核文档中查看 `vm.lowmem_reserve_ratio` 的具体说明, 其值为数组格式, 每个内存区域的保留页都通过以下方式进行计算:
```
# /proc/zoneinfo #查看内存区域信息
Node 0, zone      DMA
  pages free     1355
        min      3
        low      3
        high     4
        :
        :
    numa_other   0
        protection: (0, 2004, 2004, 2004)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

zone[i]'s protection[j] is calculated by following expression.

(i < j):
  zone[i]->protection[j]
  = (total sums of present_pages from zone[i+1] to zone[j] on the node)
    / lowmem_reserve_ratio[i];
(i = j):
   (should not be protected. = 0;
(i > j):
   (not necessary, but looks 0)

The default values of lowmem_reserve_ratio[i] are
    256 (if zone[i] means DMA or DMA32 zone)
    32  (others).
```

默认情况下 `vm.lowmem_reserve_ratio` 的值, 其组成 3 个元素的数组:
```
# cat /proc/sys/vm/lowmem_reserve_ratio 
256     256     32
```

`lowmem_reserve_ratio[i]` 即为对应下标的值, 低端内存区域的保留页即可从上一层高端区域的总页数计算出来. 

从上面的信息中可以看出 , `Node 1` 的可用内存低于 low 的值, 开始触发 `kswapd` 执行 reclaim 操作. 不过是否执行 reclaim 操作还需由内核参数 `vm.zone_reclaim_mode` 决定, 我们线上的主机中该参数均为默认值 0, 不会触发 reclaim 操作而是直接返回 `zone full` 提示：
```
# linux3.4/mm/page_alloc.c
1738 static struct page *
1739 get_page_from_freelist(gfp_t gfp_mask, nodemask_t *nodemask, unsigned int order,
...
1816                         if (zone_reclaim_mode == 0)
1817                                 goto this_zone_full;
...
1848 this_zone_full:
1849                 if (NUMA_BUILD)
1850                         zlc_mark_zone_full(zonelist, z);



# Documentation/sysctl/vm.tx
zone_reclaim_mode:

Zone_reclaim_mode allows someone to set more or less aggressive approaches to
reclaim memory when a zone runs out of memory. If it is set to zero then no
zone reclaim occurs. Allocations will be satisfied from other zones / nodes
in the system.

This is value ORed together of

1       = Zone reclaim on
2       = Zone reclaim writes dirty pages out
4       = Zone reclaim swaps pages
```

函数 `get_page_from_freelist` 在跳转到 `zone full` 之后, page 为 NULL 值, 后续的函数 `__alloc_pages_slowpath` 则直接跳转到 nopage:
```
# __alloc_pages_nodemask -> __alloc_pages_slowpath -> warn_alloc_failed
# linux-3.4/mm/page_alloc.c

2294         /* Atomic allocations - we can't balance anything */
2295         if (!wait)
2296                 goto nopage;
...
2404 nopage:
2405         warn_alloc_failed(gfp_mask, order, NULL);
2406         return page;
```

最后 `__alloc_pages_nodemask` 函数在分配 page 失败的时候会进行重试:
```
2444 retry_cpuset:
...
2458         if (unlikely(!page))
2459                 page = __alloc_pages_slowpath(...)
...
2472         if (unlikely(!put_mems_allowed(cpuset_mems_cookie) && !page))
2473                 goto retry_cpuset;
```
## 总结

从这方面的分析来看, 上述 `kernel` 的提示信息不会影响程序的正常执行, 但可能会减缓程序的执行效率. 不过要避免这个提示大概可以通过以下两种方式:

```
1. 增加 vm.min_free_kbytes 的参数值, 调低 vm.lowmem_reserve_ratio 的参数值;;
2. 设置 vm.zone_reclaim_mode 为 1;
3. 升级内核;
4. 限制网络传输速率;
```

第一种方式实际上只能缓解 kernel 报提示消息的频率, 加大 `vm.min_free_kbytes` 的值意味着加大了水位值(low, high), kswapd 进程可以提前做 `reclaim` 和释放内存相关的操作, 但是在突然需要大内存操作的时候还是会出现这个错误. 线上的报错如果频繁的话可以考虑调整该参数到 `Centos 7` 的默认值 `90112(88M)`. 另外调高 `vm.lowmem_reserve_ratio` 参数值即意味着 `NORMAL` 内存不足的时候内核可以借用`DMA32/DMA`的内存来救急, 但是也不能设置过高, 调低该值意味着预留更多的保留页, 避免低端内存使用不足引起内存分配失败. 如下所示调低 ·lowmem_reserve_ratio[1](对应 DMA32 区域) ` 的值, 可以避免低端内存不足而引起的内存分配失败的问题:
```
256  128  32
```

第二种方式其实不太建议设置, 现在很多的物理服务器基本都为 `NUMA` 架构, 每颗 `CPU` 占用一半的本地内存, `vm.zone_reclaim_mode` 默认为 0, 表示可以从其它 CPU 节点上回收内存, 保留本节点的内存, 这种方式尽可能的避免了内存的远端访问, 对占用内存比较多的程序(数据库等)很有好处; 设置为 1 后则在本节点回收内存, 本节点内存的回收可能意味着对应程序在服务时需要重新将磁盘的数据缓存到内存中, 这样会降低程序的性能响应. 如果上面的报错频繁的话也可以考虑设置该参数.

当然也可以考虑升级内核, 计算水位值的算法在新版本中有所修改, 内存的回收策略也做了不少更新, 如果报错频繁的话也可以考虑升级内核.

第四种方式则从网络数据方面来考虑, 我们可以降低传输数据的速率, 可能会减少突然需要大内存的操作, 这样或许也能能降低报错出现的频率.

如果我们的系统存在很多 `dentry` 和 `inode` 节点的缓存信息(可以通过 `slabtop` 查看), 可以考虑加大 `vfs_cache_pressure` 参数值, 让内核加快清理 `dentry` 和 `inode` 缓存. 


## 参考

[redhat-641323](https://access.redhat.com/solutions/641323)  
[redhat-2209921](https://access.redhat.com/solutions/2209921)  
[kernel-vm](https://www.kernel.org/doc/Documentation/sysctl/vm.txt)  
[what-are-page-allocation-failures](https://access.redhat.com/articles/1360023) 
