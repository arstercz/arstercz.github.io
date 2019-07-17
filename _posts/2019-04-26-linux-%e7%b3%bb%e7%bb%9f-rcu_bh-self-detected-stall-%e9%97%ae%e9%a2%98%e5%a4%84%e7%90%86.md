---
id: 1157
title: linux 系统 rcu_bh self-detected stall 问题处理
date: 2019-04-26T16:11:42+08:00
author: arstercz
layout: post
guid: https://arstercz.com/?p=1157
permalink: '/linux-%e7%b3%bb%e7%bb%9f-rcu_bh-self-detected-stall-%e9%97%ae%e9%a2%98%e5%a4%84%e7%90%86/'
categories:
  - system
tags:
  - kernel
  - rcu
---
<h2>问题说明</h2>

近期几台 linux 机器都报了以下 kernel 提示:

```
Apr 24 21:02:09 cztest kernel: INFO: rcu_bh self-detected stall on CPU { 0}  (t=0 jiffies) 
Apr 24 21:02:09 cztest kernel: Pid: 0, comm: swapper/0 Not tainted 3.4.95.R620.CentOS6.5-x86_64.OpenBeta.KVM #1 
Apr 24 21:02:09 cztest kernel: Call Trace: 
Apr 24 21:02:09 cztest kernel:  <IRQ>  [<ffffffff810bbca2>] __rcu_pending+0x192/0x4e0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff810a1e70>] ? tick_nohz_handler+0xf0/0xf0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff810bc0bb>] rcu_check_callbacks+0xcb/0xe0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81071603>] update_process_times+0x43/0x80 
Apr 24 21:02:09 cztest kernel:  [<ffffffff810a1ed1>] tick_sched_timer+0x61/0xb0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff810847dd>] __run_hrtimer+0x5d/0x120 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81084c9e>] hrtimer_interrupt+0xee/0x250 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81051f74>] smp_apic_timer_interrupt+0x64/0xa0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81638c8a>] apic_timer_interrupt+0x6a/0x70 
Apr 24 21:02:09 cztest kernel:  <EOI>  [<ffffffff8108f778>] ? sched_clock_cpu+0xb8/0x110 
Apr 24 21:02:09 cztest kernel:  [<ffffffff810578d6>] ? native_safe_halt+0x6/0x10 
Apr 24 21:02:09 cztest kernel:  [<ffffffff814f189f>] ? cpuidle_idle_call+0x1f/0xf0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff8103d6e7>] default_idle+0x27/0x50 
Apr 24 21:02:09 cztest kernel:  [<ffffffff8103da29>] cpu_idle+0x89/0xd0 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81608a2d>] rest_init+0x6d/0x80 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81967e17>] start_kernel+0x34d/0x35a 
Apr 24 21:02:09 cztest kernel:  [<ffffffff819678f8>] ? kernel_init+0x1d5/0x1d5 
Apr 24 21:02:09 cztest kernel:  [<ffffffff8196732a>] x86_64_start_reservations+0x131/0x136 
Apr 24 21:02:09 cztest kernel:  [<ffffffff81967430>] x86_64_start_kernel+0x101/0x110
```

该主机的环境如下:

```
      System | Dell Inc.; PowerEdge R620; vNot Specified (Rack Mount Chassis)
    Platform | Linux
      Kernel | 3.4.95
Total Memory | 64G
```

<h2>处理说明</h2>

linux 提供了 `RCU(read, copy and update)` 机制来解决多核处理器之间的数据同步问题, 上述提示中的 `rcu_bh` 意为 `rcu bottom halves`, 即 `rcu` 机制相关的下半部中断处理, `rcu bh` 在 `2.6.9` 内核中引入的主要目的是为了防 `DDos` 攻击, 在较新的系统中主要在软中断中运行. 系统中一些需要快速处理的中断程序通常会在上半部处理, 对时间要求比较宽松的中断程序会在下半部处理. 中断程序一般都在软硬件驱动, 内核等层面出现, 用户空间的应用程序不会做中断的处理. 按照内核文档的描述, 以下情况会出现 `rcu_bh stall` 相关的警告信息:

```
详见: kernel-source/Documentation/RCU/stallwarn.txt

So your kernel printed an RCU CPU stall warning.  The next question is
"What caused it?"  The following problems can result in RCU CPU stall
warnings:

o       A CPU looping with interrupts disabled.  This condition can
        result in RCU-sched and RCU-bh stalls.

o       A CPU looping with preemption disabled.  This condition can
        result in RCU-sched stalls and, if ksoftirqd is in use, RCU-bh
        stalls.

o       A CPU looping with bottom halves disabled.  This condition can
        result in RCU-sched and RCU-bh stalls.
```

一共三种情况会出现 `rcu_bh` 相关的提示, 分别为:

```
1. CPU 循环处理中禁止了中断;
2. CPU 循环处理中禁止了抢占, 并且启用了 ksoftirqd;
3. CPU 循环处理中禁止了下半部;
```

这几个条件都是和中断或内核抢占相关的, 由此看来应用程序不是引起该警告的原因, 更像是系统层面的.

再来看上面的报错:

```
INFO: rcu_bh self-detected stall on CPU { 0}  (t=0 jiffies)
```

可以译为检测到 `cpu 0` 上存在 `rcu_bh` 处理延迟或超时. 不过从 `linux-3.4/kernel/rcutree.c` 源文件来看:

```c
static void print_cpu_stall(struct rcu_state *rsp)
{
...
        printk(KERN_ERR "INFO: %s self-detected stall on CPU", rsp-&gt;name);
        print_cpu_stall_info_begin();
        print_cpu_stall_info(rsp, smp_processor_id());
        print_cpu_stall_info_end();
        printk(KERN_CONT " (t=%lu jiffies)\n", jiffies - rsp-&gt;gp_start);
        if (!trigger_all_cpu_backtrace())
                dump_stack();
...
```

`t=0 jiffies` 这里的 `0` 就很奇怪, 因为从代码里看这里的值应该是当前 `jiffies`(当前系统自启动以来的节拍总数, `jiffies / HZ` 即为机器启动的秒数, 系统的时钟频率 HZ 默认为 100, 相当于10ms 一次) 减去中断程序启动的 `jiffies`. 这里的 `0` 意味着经历了 `0` 个节拍, 在 `10ms` 之内. 下半部的中断在 `10ms` 内就被认为是处理延迟或超时. 不过 10ms 还远没超过默认的 `timeout(60s)` 值, 可以从 `/sys/module/rcutree/parameters/rcu_cpu_stall_timeout` 查看该值. 这个问题先保留, 或许可以通过升级内核版本解决.

另外堆栈中的信息, `update_process_times` 函数主要通过计时器中断程序来给当前的进程计时, 不过在计时前对 `rcu` 的调用进行了检查, 上述的堆栈信息即从 `rcu_check_callbacks` 中输出. 可以看到执行 `rcu_check_callbacks` 函数后, 无论是否打印堆栈信息都会执行后续的计时操作. 所以从这方面来看上面的信息只是警告信息, 不会影响用户空间程序的使用.

```c
Apr 24 21:02:09 cztest kernel:  [<ffffffff81071603>] update_process_times+0x43/0x80


source/kernel/timer.c
void update_process_times(int user_tick)
{
        struct task_struct *p = current;
        int cpu = smp_processor_id();

        /* Note: this timer irq context must be accounted for as well. */
        account_process_tick(p, user_tick);
        run_local_timers();
        rcu_check_callbacks(cpu, user_tick);  // ---&gt; rcu_pending -&gt; __rcu_pending -&gt; print_cpu_stall
        printk_tick();
#ifdef CONFIG_IRQ_WORK
        if (in_irq())
                irq_work_run();
#endif
        scheduler_tick();
        run_posix_cpu_timers(p);
```

<h2>总结说明</h2>

从上述的简单分析来看, 该消息只是提示信息, 不会是用户空间的程序来引起, 不过也需要多观察该 kernel 提示是否频繁出现. 可以尝试通过升级内核来解决该问题.

<h2>参考:</h2>

<a href="http://lwn.net/Articles/262464/">lwn-262464</a>
<a href="https://lwn.net/Articles/264090/">lwn-264090</a>
<a href="https://bugzilla.redhat.com/show_bug.cgi?id=806610">bugzilla-806610</a>
