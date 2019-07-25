---
id: 1077
title: Centos 系统 SLAB dentry 过高引起系统卡顿分析处理
date: 2018-10-23T15:39:53+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1077
permalink: '/centos-%e7%b3%bb%e7%bb%9f-slab-dentry-%e8%bf%87%e9%ab%98%e5%bc%95%e8%b5%b7%e7%b3%bb%e7%bb%9f%e5%8d%a1%e9%a1%bf%e5%88%86%e6%9e%90%e5%a4%84%e7%90%86/'
categories:
  - performance
  - system
tags:
  - centos
  - curl
  - dentry
  - slab
---
## 问题说明

近期几台主机系统都出现卡顿几秒甚至十几秒的现象, 期间没有网络问题. 每次出现卡顿现象的时间也不固定. 服务请求数和流量也没有异常变化, 我们使用 [cpu_capture]({{ site.baseurl }}/doctool/trace/cpu_capture.sh) 状态脚本解析 top 命令的输出, 正常情况几百毫秒即可输出, 在异常时耗时很长, 如下可以看到耗时接近 15s:
```
begin time: 2018-09-24T23:26:25.347257868
  end time: 2018-09-24T23:26:40.062807607
Total cpu usage: 241.8
   373 -> cpu: 100.00, state: R, cmd: kswapd0
   374 -> cpu: 100.00, state: R, cmd: kswapd1
 31493 -> cpu: 20.90, state: R, cmd: curl
 31196 -> cpu: 16.70, state: R, cmd: top
 31197 -> cpu: 4.20, state: S, cmd: perl
    11 -> cpu: 0.00, state: S, cmd: migration/2
     7 -> cpu: 0.00, state: S, cmd: migration/1
```

系统 [snoopy]({{ site.baseurl }}/how-does-snoopy-log-every-executed-command/)日志同样也有十几秒的中断, 占用 cpu 资源增长的很快(注: 监控每 10s 取最新的数据, 再和上次的值做差值平均, 和真实的情况会略有偏差, 不过能反映整体的情况):
![cpu]({{ site.baseurl }}/images/articles/201810/cpu.bmp)

## 系统环境

几台主机初始为低版本, 后续升级到新版, 不过两个版本都出现卡顿问题, 更换两台新主机后也出现同类的问题:
```
CentOS release 6.7:
  Memory: 64G
  kernel-2.6.32-573.el6.x86_64

CentOS release 6.10:
  Memory: 64G
  kernel-2.6.32-754.3.5.el6.x86_64
```

## 分析处理

在问题描述部分中, snoopy 和 cpu 检测日志可以说明检测脚本在一段时间内没有任何操作, 不过脚本检测都是在用户空间运行, 如果仅是用户空间卡顿, 在没有脚本执行的时候 snoopy 日志也不会有任何输出(原理见: [snoopy 如何工作]({{ site.baseurl }}/how-does-snoopy-log-every-executed-command/), 如果是系统内核空间卡顿, 那我们就有幸碰到了传说中的系统冻结 (system freeze) 问题, 这种情况下系统不会有任何响应, 早期的系统在冻结的时候, 可能出现 cpu 风扇都不正常转动的情况. 不过现代的操作系统应该不会有这种情况, 即便有也不会卡顿十几秒之久. 

基于此我们增加systemtap 脚本 [thread-times.stp]({{ site.baseurl }}/doctool/trace/thread-times.stp) 和 [cpu_proc.stp]({{ site.baseurl }}/doctool/trace/cpu_proc.stp) 来检测出现问题的时候卡顿发生在用户空间还是内核空间. `thread-times.stp` 脚本在 `perf.sw.cpu_clock` 和 `timer.profile` 两个探测点按照进程, pid 等信息进行用户空间和内核空间的统计, 最终输出每个进程的使用率; `cpu_proc.stp` 则在 `timer.profile` 探测点按每颗 cpu 输出用户空间及内核空间的调用次数. 如果是内核空间卡顿, 基于两个脚本编译的内核模块在出问题的时候不会有信息输出, 如果是用户空间则正常输出信息.

以内核模块的方式抓取出现卡顿现象时的日志如下:

### thread-times.stp

每 2s 输出一次, swapper 为内核里很重要的进程, pid 为 0, 负责系统的初始化, 电源管理等. 下面的 94.09% 仅表示 2s 内采样的统计信息里, swappper 进程在内核空间内执行次数的较多，不要和上文中的 cpu 使用率混淆. 

从下面日志可以看出:

23:26:21 ~ 23:26:23 为正常情况下的输出, 用户空间的 top, curl 等进程正常执行, 存在用户模式的调用. 23:26:25 ~ 23:26:27 为出现卡顿现象的时候的输出, 可以看到所有用户空间的进程 (top, sed, top, snmpd 等) 仅存在内核模式的调用, 用户模式均为 0.00%.
```
begin at Mon Sep 24 23:26:21 2018 CST
  end at Mon Sep 24 23:26:23 2018 CST
            comm   tid   pid   %user %kernel (of 47961 ticks)
         swapper     0     0   0.00%  94.09%
             top 28961 28961   0.04%   0.15%
             top 29779 29779   0.04%   0.16%
            curl 30158 30158   0.11%   0.07%
            curl 29415 29415   0.10%   0.07%
            curl 29711 29711   0.10%   0.07%
            curl 29860 29860   0.09%   0.08%
            curl 29266 29266   0.10%   0.07%
            curl 29565 29565   0.10%   0.07%
            curl 30009 30009   0.10%   0.07%
             top 30081 30081   0.00%   0.05%
             top 28662 28662   0.01%   0.05%
            curl 30304 30304   0.05%   0.01%



begin at Mon Sep 24 23:26:25 2018 CST
  end at Mon Sep 24 23:26:27 2018 CST
            comm   tid   pid   %user %kernel (of 47965 ticks)
         swapper     0     0   0.00%  64.89%
             top 30899 30899   0.00%   4.16%
         kswapd0   373   373   0.00%   4.16%
             sed 31240 31240   0.00%   4.16%
         kswapd1   374   374   0.00%   4.16%
            grep 31238 31238   0.00%   4.14%
             top 31196 31196   0.00%   3.81%
       strace.sh 28886 28886   0.00%   3.45%
           snmpd  2413  2413   0.00%   2.68%
             awk 31239 31239   0.00%   2.33%
           sleep 31030 31030   0.00%   0.15%
    xfsaild/sda1  1093  1093   0.00%   0.01%
```

### cpu_proc.stp

同样每 2s 输出一次, 23:26:21 为正常情况的输出, 可以看到不少 cpu 都存在用户模式的调用; 23:26:37 为有卡顿现象时候的输出, 可以看到每颗 cpu 仅有内核模式的输出. 没有用户空间的调用.

```
begin at: Mon Sep 24 23:26:21 2018 CST
      MODE   CPU      COUNT
    kernel     0       1682
      user     0        312
    kernel     1       1586
      user     1         39
    kernel     2       1177
      user     2          7
    kernel     3       1495
      user     3         11
    kernel     4        216
    kernel     5        246
    kernel     6         60
    kernel     7         61
    kernel     8         61
    kernel     9        101
    kernel    10         83
    kernel    11         63
    kernel    12        955
      user    12         66
    kernel    13        670
      user    13          8
    kernel    14       1506
      user    14        161
      user    15        165
    kernel    15       1507
      user    16         63
    kernel    16       1522
    kernel    17       1636
      user    17         82
    kernel    18        602
      user    18         14
      user    19         21
    kernel    19       1033
    kernel    20        345
      user    20          4
    kernel    21        663
      user    21         25
    kernel    22        119
    kernel    23        102
	
begin at: Mon Sep 24 23:26:37 2018 CST
      MODE   CPU      COUNT
    kernel     0       2000
    kernel     1       1032
    kernel     2       1319
    kernel     3       1720
    kernel     4        875
    kernel     5         64
    kernel     6       1042
    kernel     7       1034
    kernel     8       2000
    kernel     9       2000
    kernel    10        341
    kernel    11        345
    kernel    12       1722
    kernel    13        751
    kernel    14       1118
    kernel    15        161
    kernel    16        341
    kernel    17        440
    kernel    18        760
    kernel    19       1027
    kernel    20        345
    kernel    21       1756
    kernel    22       2000
    kernel    23       2000
```

从上面两个内核模块的输出我们可以看到卡顿现象仅发生在用户空间, 内核空间一直在工作, 这也就意味着应用程序是因为得不到用户空间的资源, 造成应用程序挂起, 进而引起相应的服务超时. 

### 用户空间分析

得到上述结论后, 我们开始分析为何用户空间会卡顿. 不过分析用户空间也属于操作系统层面, 所以我们使用 kdump(kexec-tools.rpm kdump 为内核 2.6 后增加的内核崩溃转储功能) 工具获取内核崩溃之后的转储文件, 再通过红帽提供的 [crash](http://people.redhat.com/anderson/) 工具对转储文件进行更细致的分析. 需要在主机调整下述的内核参数, 在出现用户进程卡顿超过 5s 的时候进行 kernel panic 行为:

#### kdump 及参数设置

`/etc/sysctl.conf` 增加以下参数
```
kernel.hung_task_panic = 1              # 存在 hung 任务的时候出发 kernel panic
kernel.hung_task_timeout_secs = 5       # 默认超时 120s, 修改为 5s, 小于系统卡顿的时间即可
kernel.hung_task_warnings = 2           # 超过 2s 则输出警告信息;
kernel.softlockup_all_cpu_backtrace = 1 # 内核检测到 soft lockup 条件的时候就打印所有 cpu 的堆栈信息
```
`/etc/grub.conf` 增加 crashkernel 选项, 重启系统后 `service kdump start` 启动 kdump 服务即可.
```
        kernel /boot/vmlinuz-2.6.32-754.3.5.el6.x86_64 ro root=/dev/sda1  rd_NO_LUKS  KEYBOARDTYPE=pc KEYTABLE=us rd_NO_MD crashkernel=256M 
LANG=en_US.UTF-8 rd_NO_LVM rd_NO_DM rhgb quiet
```


这样设置后, 系统在应用程序卡顿 5s 后, 进行 kernel panic 操作, kdump 则会保存内核崩溃的转储文件(保存目录见 `/etc/kdump.conf` 的 `path` 选项).

#### crash 分析

再次出现卡顿现象的时候, kdump 生成转储文件, 比如以下, `vmcore` 为内核转储文件, `vmcore-dmesg.txt` 保存相关的 kernel 日志信息:
```
# ls -hl /export/crash/127.0.0.1-2018-09-30-17\:21\:46/
total 15G
-rw------- 1 root root  15G Sep 30 17:42 vmcore
-rw-r--r-- 1 root root 149K Sep 30 17:21 vmcore-dmesg.txt
```

使用 crash 分析 vmcore 文件, 更多使用文档见 [crash help](http://people.redhat.com/anderson/help.html) :
```
# crash /usr/lib/debug/lib/modules/2.6.32-754.3.5.el6.x86_64/vmlinux vmcore

crash 7.1.0-8.el6
Copyright (C) 2002-2014  Red Hat, Inc.
......
This GDB was configured as "x86_64-unknown-linux-gnu"...

      KERNEL: /usr/lib/debug/lib/modules/2.6.32-754.3.5.el6.x86_64/vmlinux
    DUMPFILE: vmcore  [PARTIAL DUMP]
...
       STATE: TASK_RUNNING (PANIC)

crash> bt      # 打印当前的 backtrace 信息
PID: 348    TASK: ffff880821132040  CPU: 7   COMMAND: "khungtaskd"
 #0 [ffff8808211cbce8] machine_kexec at ffffffff81040f1b
 #1 [ffff8808211cbd48] crash_kexec at ffffffff810d6722
 #2 [ffff8808211cbe18] panic at ffffffff8155823e
 #3 [ffff8808211cbe98] watchdog at ffffffff810f7308
 #4 [ffff8808211cbee8] kthread at ffffffff810aaa30
 #5 [ffff8808211cbf48] kernel_thread at ffffffff815657d0


crash> kmem -i  # 打印通用的内存使用信息
                 PAGES        TOTAL      PERCENTAGE
    TOTAL MEM  16449056      62.7 GB         ----
         FREE    63226       247 MB    0% of TOTAL MEM
         USED  16385830      62.5 GB   99% of TOTAL MEM
       SHARED  1745812       6.7 GB   10% of TOTAL MEM
      BUFFERS        0            0    0% of TOTAL MEM
       CACHED  2051062       7.8 GB   12% of TOTAL MEM
         SLAB  14155149        54 GB   86% of TOTAL MEM

   TOTAL SWAP        0            0         ----
    SWAP USED        0            0  100% of TOTAL SWAP
    SWAP FREE        0            0    0% of TOTAL SWAP

 COMMIT LIMIT  8224528      31.4 GB         ----
    COMMITTED   149498       584 MB    1% of TOTAL LIMIT

crash>
crash> foreach bt -rt  # 打印每个进程对应的堆栈信息
.....
PID: 373    TASK: ffff880821265520  CPU: 0   COMMAND: "kswapd0"
              START: crash_nmi_callback at ffffffff8103728c
  [ffff880045a09e90] crash_nmi_callback at ffffffff8103728c
  [ffff880045a09ea0] notifier_call_chain at ffffffff81560350
  [ffff880045a09ee0] atomic_notifier_call_chain at ffffffff815603ba
  [ffff880045a09ef0] notify_die at ffffffff810b12ee
  [ffff880045a09f20] do_nmi at ffffffff8155dea9
  [ffff880045a09f50] nmi at ffffffff8155d781
    [exception RIP: __shrink_dcache_sb_locked+244]
    RIP: ffffffff811bb914  RSP: ffff88082126bb80  RFLAGS: 00000246
    RAX: ffff88091b742240  RBX: ffff880820584400  RCX: ffff8808205844f8
    RDX: 0000000000000000  RSI: ffff88082126bbc0  RDI: ffffffff81a863c0
    RBP: ffff88082126bc00   R8: ffff88091b742100   R9: 0000000000000001
    R10: 00000000ffffffff  R11: 0000000000000000  R12: 0000000000000080
    R13: ffff88082126bbb0  R14: ffff8808205844f8  R15: 0000000000000008
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0000
--- <NMI exception stack> ---
  [ffff880045a09000] __shrink_dcache_sb_locked at ffffffff811bb914
  [ffff88082126bc08] __shrink_dcache_sb at ffffffff811bbaf6
  [ffff88082126bc38] shrink_dcache_memory at ffffffff811bbc59
  [ffff88082126bc98] shrink_slab at ffffffff8114cd96
  [ffff88082126bcf8] balance_pgdat at ffffffff8115017a
  [ffff88082126bdb8] calculate_pressure_threshold at ffffffff81156ed6
  [ffff88082126be28] kswapd at ffffffff81150544
  [ffff88082126be80] autoremove_wake_function at ffffffff810aaed0
  [ffff88082126bec8] kswapd at ffffffff81150410
  [ffff88082126bee8] kthread at ffffffff810aaa30
...
PID: 374    TASK: ffff880821264ab0  CPU: 21  COMMAND: "kswapd1"
              START: crash_nmi_callback at ffffffff8103728c
  [ffff88084c689e90] crash_nmi_callback at ffffffff8103728c
  [ffff88084c689ea0] notifier_call_chain at ffffffff81560350
  [ffff88084c689ee0] atomic_notifier_call_chain at ffffffff815603ba
  [ffff88084c689ef0] notify_die at ffffffff810b12ee
  [ffff88084c689f20] do_nmi at ffffffff8155dea9
  [ffff88084c689f50] nmi at ffffffff8155d781
    [exception RIP: _spin_lock+28]
    RIP: ffffffff8155bf7c  RSP: ffff88082126fb50  RFLAGS: 00000297
    RAX: 0000000000004d1e  RBX: ffff880820584400  RCX: 0000000000000000
    RDX: 0000000000004d1d  RSI: ffff880821264ab0  RDI: ffffffff81a863c0
    RBP: ffff88082126fb50   R8: ffff88082126c000   R9: 0000000000000001
    R10: 00000000ffffffff  R11: 0000000000000000  R12: 000000000000001d
    R13: ffff88082126fbb0  R14: ffff8808205844f8  R15: 0000000000000008
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
--- <NMI exception stack> ---
  [ffff88084c689000] _spin_lock at ffffffff8155bf7c
  [ffff88082126fb58] __cond_resched_lock at ffffffff81077e1a
  [ffff88082126fb78] __shrink_dcache_sb_locked at ffffffff811bb8ef
  [ffff88082126fc08] __shrink_dcache_sb at ffffffff811bbaf6
  [ffff88082126fc38] shrink_dcache_memory at ffffffff811bbc59
  [ffff88082126fc98] shrink_slab at ffffffff8114cd96
  [ffff88082126fcf8] balance_pgdat at ffffffff8115017a
  [ffff88082126fdb8] calculate_pressure_threshold at ffffffff81156ed6
  [ffff88082126fe28] kswapd at ffffffff81150544
  [ffff88082126fe80] autoremove_wake_function at ffffffff810aaed0
  [ffff88082126fec8] kswapd at ffffffff81150410
  [ffff88082126fee8] kthread at ffffffff810aaa30
  [ffff88082126ff48] child_rip at ffffffff815657d0
  [ffff88082126ffc8] kthread at ffffffff810aa990
  [ffff88082126ffd8] child_rip at ffffffff815657b0
...
PID: 17830  TASK: ffff880822c67520  CPU: 9   COMMAND: "perl"
              START: crash_nmi_callback at ffffffff8103728c
  [ffff88084c509e90] crash_nmi_callback at ffffffff8103728c
  [ffff88084c509ea0] notifier_call_chain at ffffffff81560350
  [ffff88084c509ee0] atomic_notifier_call_chain at ffffffff815603ba
  [ffff88084c509ef0] notify_die at ffffffff810b12ee
  [ffff88084c509f20] do_nmi at ffffffff8155dea9
  [ffff88084c509f50] nmi at ffffffff8155d781
    [exception RIP: _spin_lock+30]
    RIP: ffffffff8155bf7e  RSP: ffff88085d303ba8  RFLAGS: 00000287
    RAX: 0000000000004d23  RBX: ffff880769e02bc0  RCX: 0000000000000247
    RDX: 0000000000004d1d  RSI: ffffffff81a863c0  RDI: ffffffff81a863c0
    RBP: ffff88085d303ba8   R8: 0000000000000000   R9: 0000000000000000
    R10: 000000000000000c  R11: 0000000000000000  R12: ffff880769e02bc0
    R13: ffff88085d303cb8  R14: 0000000000000000  R15: 0000000000000000
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
--- <NMI exception stack> ---
  [ffff88084c509000] _spin_lock at ffffffff8155bf7e
  [ffff88085d303bb0] _atomic_dec_and_lock at ffffffff812a3195
  [ffff88085d303be0] dput at ffffffff811bd502
  [ffff88085d303c00] path_put at ffffffff811b002a
  [ffff88085d303c20] __link_path_walk at ffffffff811b2847
  [ffff88085d303d00] path_walk at ffffffff811b2d5a
  [ffff88085d303d40] filename_lookup at ffffffff811b2f6b
  [ffff88085d303d50] security_file_alloc at ffffffff812436ac
...
PID: 18370  TASK: ffff880ff889aab0  CPU: 1   COMMAND: "tcp_capture.sh"
              START: schedule at ffffffff815589da
  [ffff880ff873bd80] sys_wait4 at ffffffff81085190
  [ffff880ff873bd90] kprobe_exceptions_notify at ffffffff81560045
  [ffff880ff873bda0] handle_mm_fault at ffffffff811606f6
  [ffff880ff873be50] do_wait at ffffffff81085124
  [ffff880ff873beb0] sys_wait4 at ffffffff81085233
....
```

输出的信息较多, 不过都容易查看. 不过也需要注意以下几点:

* 最开始使用 crash 命令连接 vmcore 文件后, bt 命令显示当前系统堆栈的信息为 khungtaskd 相关的进程, 这是因为 kernel.hung_task_panic 参数控制崩溃的, 和我们要分析的系统卡顿没有关系; 

* 从 `kmem -i` 的输出信息来看, 内存使用了 99%, 占 62.5G 内存, SLAB 分配器使用了 86% 的内存, 占用了 54G 内存, 我们再进一步查看 SLAB 分配器的的对象信息:
```
crash> kmem -s # 由于 dentry 太多, 该步骤执行时间过长, 二十分钟左右
CACHE            NAME                 OBJSIZE  ALLOCATED     TOTAL  SLABS  SSIZE
ffff88081d552240 nf_conntrack_expect      240          0         0      0     4k
ffff88081d542200 nf_conntrack_ffffffff81b2d260 312   425       948     79     4k
......
ffff881024d80200 taskstats                328          0         0      0     4k
ffff8808249b0f80 proc_inode_cache         656      28704     30324   5054     4k
.....
ffff881025cf0140 inode_cache              592       6521      7230   1205     4k
ffff881027cb0100 dentry                   192  280672224  280726440 14036322     4k
......
ffff881027c90040 selinux_inode_security    72       9947     10335    195     4k
ffff880827920e80 radix_tree_node          560      37534     37541   5363     4k
ffff880827910e40 key_jar                  192          5        40      2     4k
ffff880827900e00 buffer_head              104    1742052   1742737  47101     4k
......
```

可以看到 SLAB 分配器大约给 dentry 项分配了 `280726440` 个对象, 每个对象 192 字节, 整体上大概 `280726440*192/1024/1024/1024 = 50.19GB`, 也就是说 dentry 占用了绝大多数 SLAB 分配器的空间. 实际上我们的系统内存一共也就 64GB. 

注: slab 机制是 Linux 内核中用来分配和释放内存数据结构的普遍的方式之一, 便于数据频繁的分配和回收, 内存的内部碎片问题以及小内存的频繁分配都可以通过 slab 机制很好的解决.  详细机制见:  `Linux Kernel Develepment, 3rd Edition  12.6 section`; dentry 只直译为目录项, Linux 中, VFS 为了方便文件查找, 将目录当做文件对待, 对于 `/bin/ls` 而言, `/`, `bin`, `ls` 都属于目录项对象, 如果 VFS 要遍历很多的目录对象将是很费时耗力的操作, 所以内核会将目录项进行缓存, 即缓存到 SLAB 分配器的 denty 条目中. 详细机制见: `Linux Kernel Develepment, 3rd Edition  13.9 section`.

* `foreach bt -rt` 命令则打印索引进程的堆栈信息, 这里我们挑选了一些重要的进程信息, 大部分进程堆栈的开头部分如下:
```
              START: crash_nmi_callback at ffffffff8103728c
  [ffff88084c649e90] crash_nmi_callback at ffffffff8103728c
  [ffff88084c649ea0] notifier_call_chain at ffffffff81560350
  [ffff88084c649ee0] atomic_notifier_call_chain at ffffffff815603ba
  [ffff88084c649ef0] notify_die at ffffffff810b12ee
  [ffff88084c649f20] do_nmi at ffffffff8155dea9
  [ffff88084c649f50] nmi at ffffffff8155d781
```

这些都是 `nmi watchdog` 机制打印出的消息, 红帽系列的系统默认开启 `nmi watchdog` 特性. 一般系统发生死锁可以分为可中断和不可中断, 可中断的死锁比较容易处理, 可以通过额外方式终止死锁(比如信号控制等), 不可中断则很棘手, 因为不可中断, 所以没有别的方式终止死锁, 只能一直等待执行. nmi watchdog 机制意为不可屏蔽中断(Non Maskable Interrupt), Linux 定时器一般会以设置的参数来决定每秒直接多少次(100 ~ 1000)时钟中断, 如果 nmi 检测到有 cpu 超过 5s 还没有执行则认为系统死机, 进而开始 panic, 获取到内核转储. 我们上述得到的 vmcore 文件也是在该机制下产生的. 更多 nmi_watchdog 机制见`kernel-doc-2.6.32/Documentation/nmi_watchdog.txt` . 再来看上述的信息, 这些 nmi 机制仅保证了产生转储文件, 于我们的分析作用不大, 所以我们着重看以下信息:
```
.....
PID: 373    TASK: ffff880821265520  CPU: 0   COMMAND: "kswapd0"
--- <NMI exception stack> ---
  [ffff880045a09000] __shrink_dcache_sb_locked at ffffffff811bb914
  [ffff88082126bc08] __shrink_dcache_sb at ffffffff811bbaf6
  [ffff88082126bc38] shrink_dcache_memory at ffffffff811bbc59
  [ffff88082126bc98] shrink_slab at ffffffff8114cd96
  [ffff88082126bcf8] balance_pgdat at ffffffff8115017a
  [ffff88082126bdb8] calculate_pressure_threshold at ffffffff81156ed6
  [ffff88082126be28] kswapd at ffffffff81150544
...
PID: 374    TASK: ffff880821264ab0  CPU: 21  COMMAND: "kswapd1"
--- <NMI exception stack> ---
  [ffff88084c689000] _spin_lock at ffffffff8155bf7c
  [ffff88082126fb58] __cond_resched_lock at ffffffff81077e1a
  [ffff88082126fb78] __shrink_dcache_sb_locked at ffffffff811bb8ef
  [ffff88082126fc08] __shrink_dcache_sb at ffffffff811bbaf6
  [ffff88082126fc38] shrink_dcache_memory at ffffffff811bbc59
  [ffff88082126fc98] shrink_slab at ffffffff8114cd96
  [ffff88082126fcf8] balance_pgdat at ffffffff8115017a
  [ffff88082126fdb8] calculate_pressure_threshold at ffffffff81156ed6
  [ffff88082126fe28] kswapd at ffffffff81150544
...
PID: 17830  TASK: ffff880822c67520  CPU: 9   COMMAND: "perl"
  [ffff88084c509000] _spin_lock at ffffffff8155bf7e
  [ffff88085d303bb0] _atomic_dec_and_lock at ffffffff812a3195
  [ffff88085d303be0] dput at ffffffff811bd502
  [ffff88085d303c00] path_put at ffffffff811b002a
  [ffff88085d303c20] __link_path_walk at ffffffff811b2847
  [ffff88085d303d00] path_walk at ffffffff811b2d5a
  [ffff88085d303d40] filename_lookup at ffffffff811b2f6b
  [ffff88085d303d50] security_file_alloc at ffffffff812436ac
...
PID: 18370  TASK: ffff880ff889aab0  CPU: 1   COMMAND: "tcp_capture.sh"
              START: schedule at ffffffff815589da
  [ffff880ff873bd80] sys_wait4 at ffffffff81085190
  [ffff880ff873bd90] kprobe_exceptions_notify at ffffffff81560045
  [ffff880ff873bda0] handle_mm_fault at ffffffff811606f6
  [ffff880ff873be50] do_wait at ffffffff81085124
  [ffff880ff873beb0] sys_wait4 at ffffffff81085233
....
```

Linux 中进程变量及每次函数调用的信息都在栈空间中从高地址到低地址分配, 所以上述信息中每个进程堆栈信息的从下到上的方向即为进程函数调用的顺序. 另外我们线上的 Dell 服务器均为 NUMA 架构, 每颗 CPU 各占一半内存, 所以会有 两个 kswapd 进程存在, 即 kswapd0 管理 cpu node0, kswapd1 管理 cpu node1, 分别管理对应 CPU 的内存. kswapd 除了周期性的释放 dentry 对象外, 在每颗 CPU 可用内存低于 min_free_kbytes 的时候也会触发释放 dentry 的操作. 更多细节见:`Professional Linux Kernel Architecture 18.6 section`.

仔细观察上述内容可以发现不少有用的信息:

pid 为 18370 的 tcp_capture.sh 进程看起来一切正常, 如下所示, sys_wait4 系统调用将该进程中断(state 为 IN): 
```
crash> ps 18370   
   PID    PPID  CPU       TASK        ST  %MEM     VSZ    RSS  COMM
  18370      1   1  ffff880ff889aab0  IN   0.0  110992   2164  tcp_capture.sh
```

pid 为 17830 的应用进程都经过以下函数调用 `dput -> _atomic_dec_and_lock -> _spin_lock`, `dput` 函数用来释放 `dentry` 对象, 如下所示, 调用 dput 函数后, 随机进入 `atomic_dec_and_lock` 函数, 该函数实际调用 `_atomic_dec_and_lock` 函数, `atomic_add_unless` 为原子的给 `atomic` 变量加 `-1` , 直到为 1 为止, 成功后则给 `lock` 变量增加自旋锁, 不过从应用进程的堆栈来看, 都卡在了 `_spin_lock`, 从 `atomic_dec_and_lock` 函数的变量即可看到 `_spin_lock` 需要给 `spinlock_t` 类型 `dcache_lock` 变量增加自旋锁, 没成功的话则一直处于忙等状态.

```
============== linux-2.6.32-754.3.5.el6.x86_64/fs/dcache.c

void dput(struct dentry *dentry)
{
        if (!dentry)
                return;

repeat:
        if (atomic_read(&dentry->d_count) == 1)
                might_sleep();
        if (!atomic_dec_and_lock(&dentry->d_count, &dcache_lock))
                return;

        spin_lock(&dentry->d_lock);
.....

=========== linux-2.6.32-754.3.5.el6.x86_64/include/linux/spinlock.h

extern int _atomic_dec_and_lock(atomic_t *atomic, spinlock_t *lock);
#define atomic_dec_and_lock(atomic, lock) \
                __cond_lock(lock, _atomic_dec_and_lock(atomic, lock))
				


=========== linux-2.6.32-754.3.5.el6.x86_64/lib/dec_and_lock.c

int _atomic_dec_and_lock(atomic_t *atomic, spinlock_t *lock)
{
        /* Subtract 1 from counter unless that drops it to 0 (ie. it was 1) */
        if (atomic_add_unless(atomic, -1, 1))
                return 0;

        /* Otherwise do it the slow way */
        spin_lock(lock);
        if (atomic_dec_and_test(atomic))
                return 1;
        spin_unlock(lock);
        return 0;
}

=========== linux-2.6.32-754.3.5.el6.x86_64/arch/x86/include/asm/atomic_64.h
/**
 * atomic_add_unless - add unless the number is a given value
 * @v: pointer of type atomic_t
 * @a: the amount to add to v...
 * @u: ...unless v is equal to u.
**/
static inline int atomic_add_unless(atomic_t *v, int a, int u)
{
        int c, old;
        c = atomic_read(v);
        for (;;) {
                if (unlikely(c == (u)))
                        break;
                old = atomic_cmpxchg((v), c, c + (a));
                if (likely(old == c))
                        break;
                c = old;
        }
        return c != (u);
}
```

pid 为 373 的 `kswapd0` 进程的函数调用为 `shrink_dcache_memory -> __shrink_dcache_sb -> __shrink_dcache_sb_locked`, 即运行到了 `__shrink_dcache_sb_locked` 函数, pid 为 374 的 `kswap1` 进程的函数调用则为 `shrink_dcache_memory -> __shrink_dcache_sb -> __shrink_dcache_sb_locked -> __cond_resched_lock -> _spin_lock`, 对比 kswapd0 进程, 多了 `__cond_resched_lock -> _spin_lock` 函数调用, 从下述代码的 `__cond_resched_lock` 函数中的 `spin_lock` 同样需要给 `dcache_lock` 增加自旋锁, 获取不到则忙等待; 再来看 kswapd0 进程, 进入 `__shrink_dcache_sb` 函数中就对  `dcache_lock` 加了自旋锁, 进入 `__shrink_dcache_sb_locked` 函数后, 在执行 `cond_resched_lock` 或 `prune_one_dentry` 函数之前都不会释放 `dcache_lock`. 由此可以简单猜想, 由于 `kswapd0` 进程持有 `dcache_lock` 自旋锁, 所以引起其它进程都处于忙等状态.

```
============== linux-2.6.32-754.3.5.el6.x86_64/fs/dcache.c

static int shrink_dcache_memory(struct shrinker *shrink, int nr, gfp_t gfp_mask)
{
        if (nr) {
                if (!(gfp_mask & __GFP_FS))
                        return -1;
                prune_dcache(nr);                    // 调用 prune_dcache 函数
        }
        return (dentry_stat.nr_unused / 100) * sysctl_vfs_cache_pressure;
}

/**
 * prune_dcache - shrink the dcache
 * @count: number of entries to try to free           // 需要释放的条目数
 *
 * Shrink the dcache. This is done when we need more memory, or simply when we
 * need to unmount something (at which point we need to unuse all dentries).
 *
 * This function may fail to free any resources if all the dentries are in use.
 */

static void prune_dcache(int count)
{
        struct super_block *sb;
        int w_count;
        int unused = dentry_stat.nr_unused;
        int prune_ratio;
        int pruned;

	....
                if (down_read_trylock(&sb->s_umount)) {
                        if ((sb->s_root != NULL) &&
                            (!list_empty(&sb->s_dentry_lru))) {
                                spin_unlock(&dcache_lock);
                                __shrink_dcache_sb(sb, &w_count,                 // 调用 __shrink_dcache_sb 函数
                                                DCACHE_REFERENCED);
                                pruned -= w_count;
                                spin_lock(&dcache_lock);
                        }
                        up_read(&sb->s_umount);
                }
                spin_lock(&sb_lock);
                count -= pruned;
.....
}

static void __shrink_dcache_sb(struct super_block *sb, int *count, int flags)
{
        BUG_ON(!sb);
        BUG_ON((flags & DCACHE_REFERENCED) && count == NULL);
        spin_lock(&dcache_lock);                               // 对 dcache_lock 加自旋锁
        __shrink_dcache_sb_locked(sb, count, flags);
        spin_unlock(&dcache_lock);                             // 释放自旋锁
}

static void __shrink_dcache_sb_locked(struct super_block *sb, int *count, int flags)
{
        LIST_HEAD(referenced);
        LIST_HEAD(tmp);
...
restart:
        if (count == NULL)
                list_splice_init(&sb->s_dentry_lru, &tmp);     // count 为 NULL 时
        else {                                                       
                while (!list_empty(&sb->s_dentry_lru)) {
                        dentry = list_entry(sb->s_dentry_lru.prev,
                                        struct dentry, d_lru);
                        BUG_ON(dentry->d_sb != sb);

                        spin_lock(&dentry->d_lock);
....
                        if ((flags & DCACHE_REFERENCED)
                                && (dentry->d_flags & DCACHE_REFERENCED)) {
                                dentry->d_flags &= ~DCACHE_REFERENCED;
                                list_move(&dentry->d_lru, &referenced);
                                spin_unlock(&dentry->d_lock);
                        } else {
                                list_move_tail(&dentry->d_lru, &tmp);
                                spin_unlock(&dentry->d_lock);
                                cnt--;
                                if (!cnt)
                                        break;
                        }
                        cond_resched_lock(&dcache_lock);
                }
        }
        while (!list_empty(&tmp)) {                        
                dentry = list_entry(tmp.prev, struct dentry, d_lru);
                dentry_lru_del_init(dentry);
                spin_lock(&dentry->d_lock);                // 获取自旋锁
...
                if (atomic_read(&dentry->d_count)) {
                        spin_unlock(&dentry->d_lock);
                        continue;
                }
                prune_one_dentry(dentry);                  // 清理 dentry 条目
                /* dentry->d_lock was dropped in prune_one_dentry() */
                cond_resched_lock(&dcache_lock);
        }
.....
}


static void prune_one_dentry(struct dentry * dentry)  // 清理 dentry
        __releases(dentry->d_lock)
        __releases(dcache_lock)                       // 释放 dcache_lock
        __acquires(dcache_lock)
{
        __d_drop(dentry);
        dentry = d_kill(dentry);

        /*
         * Prune ancestors.  Locking is simpler than in dput(),
         * because dcache_lock needs to be taken anyway.
         */
        spin_lock(&dcache_lock);
        while (dentry) {
                if (!atomic_dec_and_lock(&dentry->d_count, &dentry->d_lock))
                        return;

                if (dentry->d_op && dentry->d_op->d_delete)
                        dentry->d_op->d_delete(dentry);
                dentry_lru_del_init(dentry);
                __d_drop(dentry);
                dentry = d_kill(dentry);
                spin_lock(&dcache_lock);
        }
}

========== linux-2.6.32-754.3.5.el6.x86_64/kernel/sched.h
#define cond_resched_lock(lock) ({                              \
        __might_sleep(__FILE__, __LINE__, PREEMPT_LOCK_OFFSET); \
        __cond_resched_lock(lock);                              \
})

========== linux-2.6.32-754.3.5.el6.x86_64/kernel/sched.c
int __cond_resched_lock(spinlock_t *lock)
{
        int resched = should_resched();
        int ret = 0;

        lockdep_assert_held(lock);

        if (spin_needbreak(lock) || resched) {
                spin_unlock(lock);
                if (resched)
                        __cond_resched();
                else
                        cpu_relax();
                ret = 1;
                spin_lock(lock);               // 给 lock 增加自旋锁
        }
        return ret;
}
```

从上述的分析来看, 我们可以简单理解 `kswapd0` 进程持有了 `dcache_lock` 自旋锁引起其它进程在 `spin_lock(xxxx)` 一直处于忙等状态, 进而引起程序在用户空间无响应, 而且其它进程也都调用了 `dput` 函数, 这意味着其它进程也触发了清理 `dentry` 的操作. 另外从 `__shrink_dcache_sb_locked` 函数来看 `dentry` 是以循环方式加自旋锁(`spin_lock` 适用于短时间的轻量的锁)清理的, 所以单个的 kswapd 进程不会持有 `dcache_lock` 过长时间. 不过 `__shrink_dcache_sb_locked` 函数的指针变量参数 `count` 却决定了需要释放多少 `dentry` 条目, 如果 `count` 为 `NULL`, 则需要释放整个 `dentry` 对象空间, 上述的 `crash` 分析中我们看到 `SLAB` 分配器中大约有 `280672224`, 这个数值足够大, 相信全部清理需要不短的时间, 如果 `count` 不为 `NULL`, 则具体的数值由 `prune_dcache` 函数进行判定, 如下所示:
```
========== linux-2.6.32-754.3.5.el6.x86_64/fs/dcache.c

 541 static void prune_dcache(int count)
 542 {
 543     struct super_block *sb;
 544     int w_count;
......
 553     if (count >= unused)
 554         prune_ratio = 1;
 555     else
 556         prune_ratio = unused / count;
 557     spin_lock(&sb_lock);
 558     list_for_each_entry(sb, &super_blocks, s_list) {
......
 571         spin_unlock(&sb_lock);
 572         if (prune_ratio != 1)
 573             w_count = (sb->s_nr_dentry_unused / prune_ratio) + 1;
 574         else
 575             w_count = sb->s_nr_dentry_unused;
 576         pruned = w_count;
......
 587                 spin_unlock(&dcache_lock);
 588                 __shrink_dcache_sb(sb, &w_count,
 589                         DCACHE_REFERENCED);
......
```
查看 `dentry` 的状态, 如下所示, `unused` 值依旧很大, 所以上述 `prune_dcache` 函数中不管 `prune_ratio` 是否为1, 计算出来的 `w_count` 都很大,  传递给 `__shrink_dcache_sb` 函数的 `count` 值也就很大, 所以 `count` 不为 `NULL` 的时候, 清理 `dentry` 的操作应该也需要不短的时间. 这点我们从上述 `cpu` 检测脚本的输出中可以看到一点迹象, 每次卡顿恢复的时候, 都有 `kswapd0`, `kswapd1` 进程的存在.
```
# cat /proc/sys/fs/dentry-state
# dentry          unused   age_limit want_pages    dummy[2]
280626228       280615209       45      0          0       0
```

#### 为何 dentry 占用这么多

从上述的分析来看, 应用程序不响应是因为 `dentry` 释放的原因造成的, 那么为什么主机中会有这么多 `dentry` 条目, 我们的程序没有上传文件等需要缓存 `dentry` 的操作, 甚至还有两台机器只跑了几个检测脚本, 却有接近3亿多的目录缓存对象. 

参考红帽知识库 [access-55818](https://access.redhat.com/solutions/55818) , 其中提到了 `dentry` 增长的原因等问题, 不过场景和我们的不同, 我们的系统并没有那么多子目录或文件. 不过下面的评论却值得一提, 如下所示:
![replay]({{ site.baseurl }}/images/articles/201810/redhat_replay.png)

一些依赖 `nss-softokn` 老版本库的工具, 比如 curl 在访问 `https` 的时候, 由于 `sdb_measureAccess` 方法会访问很多 `/etc/pki/nssdb/.xxxxx.db` 不存在的文件, 进而造成 `dentry` 数量增加, 更详细见: [bugzilla-1044666](https://bugzilla.redhat.com/show_bug.cgi?id=1044666) .  这点正好符合我们环境,几台主机都有 `curl https` 相关的脚本在执行, 每秒三四次 curl, 每次 curl 产生约 800 左右的不存在文件, 算下来每秒差不多 3000 左右, 每天就需要缓存 2.6亿左右的条目, 比较符合我们情况. 

参考国内的文章 [aliyun-131870](https://yq.aliyun.com/articles/131870) , 也出现了类似的问题, 不过其分析 `slab` 分配器 `dentry` 对象的代码没有对外开放, 遍历整个 `dentry` 的对象对线上环境影响也较大, 所以我们增加 [dentry.stp]({{ site.baseurl }}/doctool/trace/dentry.stp) 脚本来查看, 该脚本在内核函数 dentry_lru_add 增加探针, 可以帮助我们查看系统在 dentry 对象中增加的到底是什么目录条目, 如下所示:

```
......
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685897_dOeSnotExist_.db
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685898_dOeSnotExist_.db
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685899_dOeSnotExist_.db
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685900_dOeSnotExist_.db
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685901_dOeSnotExist_.db
Mon Oct 15 12:07:04 2018 - tid: 3289, ppid: 3258, path: /etc/pki/nssdb/.6685902_dOeSnotExist_.db
.......
```

可以看到, 有很多 nss 相关的文件在进行访问. 所以到这里我们可以确定`curl https`操作就是造成 dentry 条目增加的原因. 按照上述红帽的 `bugzilla` 描述, 将 `nss-softokn` 升级到 `3.16.1-4` 版本即可解决该问题. 不过红帽并没有给出 rpm 相关的升级包, 手动更新则需要编译很多 nss 相关的依赖, Centos 系统都需要升级以解决该问题, 不过 nss 官方也给出了变通方案, 用户可以设置 `NSS_SDB_USE_CACHE` 环境变量(`yes` 或 `no` 都可以)跳过 nss 库的 `sdb_measureAccess` 方法, 详见: [nss sdb access](https://hg.mozilla.org/projects/nss/rev/5a67f6beee9a), Centos 5,6 等升级到 `nss-softokn-3.14.3` 版本即可使用该补丁. 另外 Centos 7 默认为 `3.28.x` 高版本, 不会有我们所描述的相关问题.

了解这些后, 我们停掉 `curl https` 相关的脚本, 重新声明变量 NSS_SDB_USE_CACHE 后再启动该脚本:
```
export NSS_SDB_USE_CACHE=yes
nohup tttt.sh &
```

如下所示, 主机可用内存不在像以前一样频繁使用, 更改后的可用内存更稳定:

![memory]({{ site.baseurl }}/images/articles/201810/memory.bmp)

设置 `NSS_SDB_USE_CACHE` 变量后, 主机没有再出现卡顿的现象. 

## 其它问题

#### vm.vfs_cache_pressure 生效问题

内核文档中对 `vm.vfs_cache_pressure` 进行了描述:
```
用来控制内核回收内存的趋势. 默认为100, 表示以相对公平的速率回收缓存中的 dentry 和 inode 对象. 减少该值则内核倾向
于保留缓存中的 dentry 和 inode 对象, 为 0 时内核不会进行 dentry 及 inode 回收, 不过这样容易引起 OOM 问题. 增加该值
则表示内核倾向清理缓存中的对象, 不过值设置过大会加大锁开销, 影响系统性能. 
```

从描述来看, 增加 `vfs_cache_pressure` 值可以加快 `dentry` 及 `inode` 对象的回收, 不过在实际使用中, 调整该参数并未生效, dentry 对象一直在增加, 并未随着时间而有所减少. 网上此类问题也较多, 比如红帽知识库中 [access-55818](https://access.redhat.com/solutions/55818) 中提到的修改参数未生效问题.

从源代码来看, `vfs_cache_pressure` 参数仅被 `shrink_dcache_memory` 函数调用, 该函数通过结构体 `shrinker` 的 `shrink` 成员变量访问:
```
============== linux-2.6.32-754.3.5.el6.x86_64/fs/dcache.c

  41 int sysctl_vfs_cache_pressure __read_mostly = 100;
  42 EXPORT_SYMBOL_GPL(sysctl_vfs_cache_pressure);
...
 953 static int shrink_dcache_memory(struct shrinker *shrink, int nr, gfp_t gfp_mask)
 954 {
 955     if (nr) {                                  // nr 为 0 则跳过
 956         if (!(gfp_mask & __GFP_FS))
 957             return -1;
 958         prune_dcache(nr);
 959     }
 960     return (dentry_stat.nr_unused / 100) * sysctl_vfs_cache_pressure;
 961 }
 962 
 963 static struct shrinker dcache_shrinker = {
 964         .shrink = shrink_dcache_memory,        // 指向 shrink_dcache_memory 函数
 965         .seeks = DEFAULT_SEEKS,
 966 };
```

`shrink_slab` 函数调用 `shrinker` 结构体进行内存的回收处理, 该函数主要用来收缩所有注册为可收缩的函数, 其在访问结构体 `shrinker` 的 `shrink` 成员变量的时候, nr 参数为 0 则对应上述的 `shrink_dcache_memory` 函数, 仅返回缓存中可回收的对象数目(同上面分析中的 `nr_unused` 条目), 下面的 `max_pass` 值决定了 `shrinker->nr` 的值, 这意味着 `vm.vfs_cache_pressure` 参数值越大, `shrinker->nr` 的值就越大, 初始的 `total_scan` 的值也就越大. `SHRINK_BATCH` 默认为 128, 在 `total_scan` 大于 128 的时候开始进行 while 循环处理, `shrink_ret` 为每次调用 `shrink_dcache_memory` 函数后返回的可回收对象数目. 从 while 条件 `total_scan >= SHRINK_BATCH` 可以看到内核参数 `vm.vfs_cache_pressure` 的作用确实如内核文档说明一样, 值越大则清理更多的缓存对象, 为 0 则不会执行 while 处理.

```
============== linux-2.6.32-754.3.5.el6.x86_64/mm/vmscan.c 
 226 unsigned long shrink_slab(unsigned long scanned, gfp_t gfp_mask,
 227                         unsigned long lru_pages)
 228 {
 229         struct shrinker *shrinker;
 230         unsigned long ret = 0;
......

 241         list_for_each_entry(shrinker, &shrinker_list, list) {
 242                 unsigned long long delta;
 243                 unsigned long total_scan;
 244                 unsigned long max_pass;
 245 
 246                 max_pass = (*shrinker->shrink)(shrinker, 0, gfp_mask);  // 返回可回收对象数目
 247                 /* -> shrink returns an int; many have overflow issues */
 248                 if (max_pass > INT_MAX)
 249                         max_pass = INT_MAX;
 250                 delta = (4 * scanned) / shrinker->seeks;
 251                 delta *= max_pass;                                      // 决定 delta 的值
 252                 do_div(delta, lru_pages + 1);
 253                 shrinker->nr += delta;
......

 266                 if (shrinker->nr > max_pass * 2)                        // 不超过 2 倍大小的 max_pass, 避免无线循环
 267                         shrinker->nr = max_pass * 2;
 268 
 269                 total_scan = shrinker->nr;
 270                 shrinker->nr = 0;
 271 
 272                 while (total_scan >= SHRINK_BATCH) {                   // SHRINK_BATCH 默认为 128
 273                         long this_scan = SHRINK_BATCH;
 274                         int shrink_ret;
 275                         int nr_before;
 276 
 277                         nr_before = (*shrinker->shrink)(shrinker, 0, gfp_mask);  // 返回可回收对象数目
 278                         shrink_ret = (*shrinker->shrink)(shrinker, this_scan,    // this_scan 大于 0, 回收对象, 返回 shrink_dcache_memory 函数处理后的最新的数目 
 279                                                                 gfp_mask);
 280                         if (shrink_ret == -1)
 281                                 break;
 282                         if (shrink_ret < nr_before)                              // 正常回收则表达式为 true 
 283                                 ret += nr_before - shrink_ret;
 284                         count_vm_events(SLABS_SCANNED, this_scan);
 285                         total_scan -= this_scan;
```

不过 kswapd 在周期性清理缓存对象或者可用内存不足时, 并不是每次都会调用 shrink_slab 函数, 如下所示, balance_pgdata 在收缩内存的时候, 会按照函数或其他参数的优先级进行调用, 调用高优先级的函数后如何系统可用内存足够则不需要调用低优先级的函数, 下图中的 shrink_slab 函数优先级较低, 这就说明内存足够的情况下不会调用 shrink_slab 函数, 使用脚本 shrink_slab.stp 进行抓取也发现该函数并不是周期性的调用, 当然手动 drop_cache 会触发该函数执行. 
![shrink]({{ site.baseurl }}/images/articles/201810/kswapd_shrink.bmp)

## 总结说明

根据上述的分析, 几台主机主要由于 nss 库问题而产生了很多 `dentry` 对象, 所以大致有以下几种方式避免 `curl https` 产生的此类问题:
```
1. 低版本系统启动 curl 请求前声明 NSS_SDB_USE_CACHE 环境变量, 值为 yes 或 no 均可;
2. 升级 nss-softoken 到 3.16.1-4 或以上版本, Centos 5,6 依赖较多, 慎重考虑升级, Centos 7 默认高版本(3.28..);
3. 单独编译 curl, 不过 ssl 选项可以修改为 openssl, 这样编译后 curl 访问 https 使用 openssl 相关的库, 而不会使用 nss 库;
```
