---
layout: post
title: "发生 SLAB 内存泄漏该怎么办"
tags: [linux, slab]
comments: true
---

通常应用程序主要通过类似 `malloc` 等标准函数来进行内存的分配使用, 不过在 Linux 中, 内核无法使用标准函数, 一般通过 [SLAB Allocator](https://www.kernel.org/doc/gorman/html/understand/understand011.html) 机制来进行内存的分配. 各个子系统, 驱动以及内核模块等都可以通过 `SLAB Allocator` 机制分配内存, 同时该机制还可以当作缓存来使用, 这点主要是针对经常分配并释放的对象. 从内核 2.6 版本开始, `slab` 分配器有两个替代分配器:

 | 分配器 | 用途 |
 | :-: | :-: |
 | slob | 主要用于嵌入式系统, 代码量少, 算法简单 |
 | slub | 主要用于服务器等大型系统, 优化内存开销 |

> **更多见**: [slab/slob/slub](https://hammertux.github.io/slab-allocator)

通常的服务器系统都使用 `slub` 分配器, 内核, 模块或驱动用完内存后都需要释放掉内存, 如果一直占用着内存, 系统可能会频繁的 `OOM(Out of Memory)` 杀掉用户空间的进程, 更有可能耗尽系统内存引起内核崩溃. 在如下信息中, 系统已经没有多少内存可用, 其中 `SUnreclaim` 为 `slab` 的一部分, 占据了大量的内存:
```
# 系统环境

Dell R620
MEM 64G
Centos 7
kernel-3.10.0-862.el7.x86_64


# less /proc/meminfo 
MemTotal:       65759220 kB
MemFree:          294356 kB
MemAvailable:     110732 kB
Buffers:            4264 kB
Cached:          1746492 kB
...
Slab:           63117636 kB
SReclaimable:      55500 kB
SUnreclaim:     63062136 kB
```

`SUnreclaim` 是不可回收状态, 它几乎占用了整个系统内存, 通过 `slabtop` 命令来看:
```
# slabtop -sc
 Active / Total Objects (% used)    : 63476486 / 63523309 (99.9%)
 Active / Total Slabs (% used)      : 1996655 / 1996655 (100.0%)
 Active / Total Caches (% used)     : 80 / 110 (72.7%)
 Active / Total Size (% used)       : 63100006.52K / 63116476.68K (100.0%)
 Minimum / Average / Maximum Object : 0.01K / 0.99K / 12.69K

  OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME                   
62983672 62983275  99%    1.00K 1985241       32  63527712K kmalloc-1024
 25060  12262  48%    0.57K    895       28     14320K radix_tree_node
 17600  16523  93%    0.58K    320       55     10240K inode_cache
```

`kmalloc-1024` 即表示内核空间在分配 1024 字节大小的内存, 总共占据了接近 `62G` 的内存. 这可能意味着内核子系统, 驱动或者模块存在分配内存但不释放的行为. 如何诊断这种问题? 可以通过以下几种方式找到一些有用的线索:

* [通过 debugfs 查找线索](#通过-debugfs-查找线索)
* [通过 slub 查找线索](#通过-slub-查找线索)
* [通过 kmemleak 查找线索](#通过-kmemleak-查找线索)
* [通过 perf 查找线索](#通过-perf-查找线索)
* [通过 systemtap 查找线索](#通过-systemtap-查找线索)

### 通过 debugfs 查找线索

内核开发者应该对 [debugfs](https://www.kernel.org/doc/html/latest/filesystems/debugfs.html) 很熟悉, 我们可以将很多内核空间的状态信息暴露到用户空间. 通过 `debugfs` 我们可以很方便的找出哪些程序分配了 `1024` 字节的内存, 如下所示:

```
# mount -t debugfs none /sys/kernel/debug

// 增加过滤规则, 指定 bytes_alloc 为 1024 字节
# echo "bytes_alloc == 1024" > /sys/kernel/debug/tracing/events/kmem/kmalloc/filter

// 开启事件跟踪
# echo 1 > /sys/kernel/debug/tracing/events/kmem/kmalloc/enable

// 经过一段时间后关闭
echo 0 > /sys/kernel/debug/tracing/events/kmem/kmalloc/enable

// 获取信息
# cat /sys/kernel/debug/tracing/trace > /tmp/kmem.out
```

从 `/tmp/kmem.out` 即可发现不少信息, 如下所示:
```
# less /tmp/kmem.out 
# tracer: nop
#           TASK-PID   CPU#  ||||    TIMESTAMP  FUNCTION
#              | |       |   ||||       |         |
...
       cmf-agent-3768  [010] .... 8824626.658432: kmalloc: call_site=ffffffff951b4836 ptr=ffff8c1be58e9000 bytes_req=936 bytes_alloc=1024 gfp_flags=GFP_KERNEL
            bash-844   [000] .... 8824683.769449: kmalloc: call_site=ffffffff95224c73 ptr=ffff8c16ef3bb800 bytes_req=640 bytes_alloc=1024 gfp_flags=GFP_KERNEL|GFP_ZERO
            bash-844   [000] .... 8824683.769468: kmalloc: call_site=ffffffff9512ee23 ptr=ffff8c16ef3be400 bytes_req=920 bytes_alloc=1024 gfp_flags=GFP_KERNEL|GFP_ZERO
       cmf-agent-3768  [000] .... 8824686.715482: kmalloc: call_site=ffffffff951b4836 ptr=ffff8c16ef3b9400 bytes_req=936 bytes_alloc=1024 gfp_flags=GFP_KERNEL
 java_version.sh-2526  [014] .... 8824686.805563: kmalloc: call_site=ffffffff9512ee23 ptr=ffff8c1727fbc400 bytes_req=920 bytes_alloc=1024 gfp_flags=GFP_KERNEL|GFP_ZERO
            java-2529  [015] .... 8824686.820292: kmalloc: call_site=ffffffff9512ee23 ptr=ffff8c21a214b800 bytes_req=920 bytes_alloc=1024 gfp_flags=GFP_KERNEL|GFP_ZERO
         systemd-1     [020] .... 8824687.815762: kmalloc: call_site=ffffffff9512ee23 ptr=ffff8c180afbfc00 bytes_req=920 bytes_alloc=1024 gfp_flags=GFP_KERNEL|GFP_ZERO
...
```

跟踪的时间越长, 发现线索的概率就越大, 上述的信息中可以看到有不少用户空间的进程, 包括`systemd` 都进行了内存分配. 如果从上述信息中找到了可疑的信息, 可以关闭这些 `TASK` 对应的程序或内核模块, 如果找不到则可能是内核子系统, 驱动引起的原因. 上述信息中由于已经没有多少可用内存, 跟踪的时间也比较短, 所以没有发现可疑的线索. 同类问题可以参考 [kmalloc-1024 slab caches take all resources](https://access.redhat.com/solutions/1546313). 

### 通过 slub 查找线索

可以通过 `slub debug` 来追踪 `kmalloc-1024` 的内存分配是否存在内存泄漏的行为. 目前大多数发行版都开启了编译选项 `CONFIG_SLUB_DEBUG`, 我们可以在运行时通过命令 `echo 1 > /sys/kernel/slab/<leaking_slab>/trace` 开启 debug 调试, 这种方式对将进程的堆栈也打印出来, 一般输出到系统 `messages` 或者 `console`, 如下所示:
```
# echo 1 > /sys/kernel/slab/kmalloc-1024/trace

// 经过一段时间后在关闭调试
# echo 0 > /sys/kernel/slab/kmalloc-1024/trace
```

**备注**: 该方式会输出大量的信息, 主机可能因为系统日志 buffer 的原因出现卡慢的现象, 实际使用中建议通过以下命令执行:
```
# echo 1 > /sys/kernel/slab/kmalloc-1024/trace  && sleep <n> && echo 0 > /sys/kernel/slab/kmalloc-1024/trace
```

> n 为数字, 建议 30 以内, 表示 sleep 多少秒, 不建议设置的很大.

开启调试后, 可以在 `console` 或系统日志中看到类似下面的信息:
```
Sep 16 16:27:26 cztest kernel: CPU: 14 PID: 56451 Comm: bash Kdump: loaded Tainted: P           OE  ------------   3.10.0-862.14.4.el7.x86_64 #1
Sep 16 16:27:26 cztest kernel: Hardware name: Dell Inc. PowerEdge R620/0D2D5F, BIOS 2.5.4 01/22/2016
Sep 16 16:27:26 cztest kernel: Call Trace:
Sep 16 16:27:26 cztest kernel: [<ffffffff99f13754>] dump_stack+0x19/0x1b
Sep 16 16:27:26 cztest kernel: [<ffffffff99f108b8>] free_debug_processing+0x1ca/0x259
Sep 16 16:27:26 cztest kernel: [<ffffffff99a292f0>] ? free_pipe_info+0x90/0xa0
Sep 16 16:27:26 cztest kernel: [<ffffffff99a292f0>] ? free_pipe_info+0x90/0xa0
Sep 16 16:27:26 cztest kernel: [<ffffffff999fa000>] __slab_free+0x250/0x2f0                         --> 释放 slab
Sep 16 16:27:26 cztest kernel: [<ffffffff99c27080>] ? tty_check_change.part.10+0xf0/0x100
Sep 16 16:27:26 cztest kernel: [<ffffffff99a292f0>] ? free_pipe_info+0x90/0xa0
Sep 16 16:27:26 cztest kernel: [<ffffffff999fa766>] kfree+0x106/0x140
Sep 16 16:27:26 cztest kernel: [<ffffffff99a292f0>] free_pipe_info+0x90/0xa0
Sep 16 16:27:26 cztest kernel: [<ffffffff99a29359>] put_pipe_info+0x59/0x60
Sep 16 16:27:26 cztest kernel: [<ffffffff99a29400>] pipe_release+0xa0/0xb0
Sep 16 16:27:26 cztest kernel: [<ffffffff99a214fc>] __fput+0xec/0x260
Sep 16 16:27:26 cztest kernel: [<ffffffff99a2175e>] ____fput+0xe/0x10
Sep 16 16:27:26 cztest kernel: [<ffffffff998bab8b>] task_work_run+0xbb/0xe0
Sep 16 16:27:26 cztest kernel: [<ffffffff9982bc55>] do_notify_resume+0xa5/0xc0
Sep 16 16:27:26 cztest kernel: [<ffffffff99f25ae4>] int_signal+0x12/0x17
```

没有 `__slab_free` 的堆栈可能就是内存泄漏的线索. 同类问题的处理见 [诊断 SLUB 问题](http://linuxperf.com/?p=184)

### 通过 kmemleak 查找线索

[kmemleak](https://www.kernel.org/doc/html/v4.10/dev-tools/kmemleak.html) 通过追踪 `kmalloc(), kmem_cache_alloc(), vmalloc()` 等函数来判断内核是否存在内存泄漏. 目前大多数的发行版并没有开启编译选项 `CONFIG_DEBUG_KMEMLEAK `, 我们可以通过安装对应内核版本的 debug 版本来使用此特性.  这里不做具体的介绍, 详细示例可参考 [kmemleak 检测内核内存泄漏](http://linuxperf.com/?p=188) 和 [debug-kernel-space-memory-leak](https://www.bo-yang.net/2015/03/30/debug-kernel-space-memory-leak).

### 通过 perf 查找线索

可以通过 perf 来跟踪 `slab` 内存分配的信息, 如下所示, 单独指定探针函数 `kmem_cache_alloc` 进行跟踪:
```
// 初始化, 清理已存在的探针函数
# perf probe -d kmem_cache_alloc*

// Centos 7 中执行
# perf probe kmem_cache_alloc      's->name:string' 2>/dev/null  

// 记录数据, 时间可以自己指定
# perf record -a -g -e probe:kmem_cache_alloc --filter 'name == "kmalloc-1024"' sleep 10

// 查看信息
# perf script
WTOplog.lThread 99877 [000] 22544738.707289: probe:kmem_cache_alloc: (ffffffff999fadc0) name="kmalloc-1024"
                  3fadc1 kmem_cache_alloc (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                  45b963 bio_alloc_bioset (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                   1095f ext4_bio_write_page ([ext4])
                    6c47 mpage_submit_page ([ext4])
                    6d70 mpage_process_page_bufs ([ext4])
                    7c75 mpage_prepare_extent_to_map ([ext4])
                    c617 ext4_writepages ([ext4])
                  3a3b81 do_writepages (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                  398405 __filemap_fdatawrite_range (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                  398551 filemap_write_and_wait_range (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                    34da ext4_sync_file ([ext4])
                  453277 do_fsync (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                  453583 sys_fdatasync (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                  92579b system_call (/usr/lib/debug/lib/modules/3.10.0-862.14.4.el7.x86_64/vmlinux)
                   f51ad [unknown] (/usr/lib64/libc-2.17.so)
                  b5adae __wt_log_force_sync (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
                  b6152b __wt_log_flush (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
                  abd5ae __session_log_flush (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
                  a51778 mongo::WiredTigerSessionCache::waitUntilDurable (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
                  a3eaa8 mongo::WiredTigerOplogManager::_oplogJournalThreadLoop (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
                 23422d0 execute_native_thread_routine (/opt/mongodb-linux-x86_64-3.6.15/bin/mongod)
......
``` 

更多参考: [track-slab-using-perf](https://access.redhat.com/solutions/2850631).  

### 通过 systemtap 查找线索

在文章 [linux-dynamic-trace](https://blog.arstercz.com/introduction_to_linux_dynamic_tracing/) 中, 我们提到了 [systemtap](https://sourceware.org/systemtap/) 这个强悍的工具, 这里我们也可以使用 `systemtap` 来跟踪 `slab` 内存分配的堆栈情况. 如下所示增加脚本跟踪 `kmem_cache_alloc` 函数:
```c
# cat kmem.stap
# This script displays the number of given slab allocations and the backtraces leading up to it.
# used with centos 7

global slab = @1
global stats, stacks
probe kernel.function("kmem_cache_alloc") {
        if (kernel_string($s->name) == slab) {
                stats[execname()] <<< 1
                stacks[execname(),kernel_string($s->name),backtrace()] <<< 1
        }
}
# Exit after 10 seconds
# probe timer.ms(10000) { exit () }
probe end {
        printf("Number of %s slab allocations by process\n", slab)
        foreach ([exec] in stats) {
                printf("%s:\t%d\n",exec,@count(stats[exec]))
        }
        printf("\nBacktrace of processes when allocating\n")
        foreach ([proc,cache,bt] in stacks) {
                printf("Exec: %s Name: %s  Count: %d\n",proc,cache,@count(stacks[proc,cache,bt]))
                print_stack(bt)
                printf("\n-------------------------------------------------------\n\n")
        }
}
```

执行输出如下:
```
# stap -v --all-modules kmem.stp kmalloc-1024
Pass 1: parsed user script and 476 library scripts using 273956virt/69332res/3516shr/65876data kb, in 710usr/70sys/795real ms.
Pass 2: analyzed script: 2 probes, 9 functions, 4 embeds, 3 globals using 426840virt/223480res/4820shr/218760data kb, in 3080usr/1510sys/4696real ms.
Pass 3: translated to C into "/tmp/stapd1lZps/stap_cf01a87fb02d496c7f93f7cfbd8898a7_7397_src.c" using 426840virt/223888res/5228shr/218760data kb, in 5860usr/260sys/6344real ms.
Pass 4: compiled C into "stap_cf01a87fb02d496c7f93f7cfbd8898a7_7397.ko" in 17840usr/2710sys/19353real ms.
Pass 5: starting run.
WARNING: Missing unwind data for a module, rerun with 'stap -d (unknown; retry with -DDEBUG_UNWIND)'
^CNumber of kmalloc-1024 slab allocations by process
xfsaild/sda2:   33
systemd-udevd:  2
gpg-agent:      2
kworker/u97:1:  1
......
......
-------------------------------------------------------

Exec: gpg-agent Name: kmalloc-1024  Count: 1
 0xffffffff8a01d630 : kmem_cache_alloc+0x0/0x1f0 [kernel]
 0xffffffff8a41eb99 : sk_prot_alloc+0x39/0x190 [kernel]
 0xffffffff8a41f82c : sk_alloc+0x2c/0xd0 [kernel]
 0xffffffff8a4f649d : unix_create1+0x4d/0x1a0 [kernel]
 0xffffffff8a4fa0fa : unix_stream_connect+0x9a/0x4a0 [kernel]
 0xffffffff8a41b96d : SYSC_connect+0xed/0x130 [kernel]
 0xffffffff8a41d5be : sys_connect+0xe/0x10 [kernel]
 0xffffffff8a576ddb : system_call_fastpath+0x22/0x27 [kernel]
 0x7ff070008d50 : 0x7ff070008d50
```

可以看到我们获取了进程及相应的堆栈信息, 提供了不少诊断的线索. 完整示例见: [track-slab-with-systemtap](https://access.redhat.com/articles/2850581).

## 总结说明

上述介绍的几种方式不一定能找出内存泄漏的根本原因, 不过会帮助我们获取一些有用的线索. 值得一提的是, 如果找到了相关的线索, 关闭对应的任务, 模块或驱动后, 内核不一定会释放这些内存, 可能只能观察到 `kmalloc-1024` 的数量不再增长, 这种情况下就只能靠重启系统释放内存.

## 参考

[slab-allocator](https://hammertux.github.io/slab-allocator)  
[kmalloc-1024 slab caches take all resources](https://access.redhat.com/solutions/1546313)  
[keep track of slab leaks](https://access.redhat.com/solutions/358933)  
[track slab allocations using perf](https://access.redhat.com/solutions/2850631)  
[track slab allocations with systemtap](https://access.redhat.com/articles/2850581)  
[debug-kernel-space-memory-leak](https://www.bo-yang.net/2015/03/30/debug-kernel-space-memory-leak)  
[kmemleak 检测内核内存泄漏](http://linuxperf.com/?p=188)  
[诊断 SLUB 问题](http://linuxperf.com/?p=184)  
[诊断 SLAB 问题](http://linuxperf.com/?p=148)  
