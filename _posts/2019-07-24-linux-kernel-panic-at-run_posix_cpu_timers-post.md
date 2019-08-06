---
layout: post
title: "Linux kernel panic at run_posix_cpu_timers+0xa4"
tags: [kernel, panic]
comments: false
---

最近一台主机突然内核崩溃后, 系统通过 kdump 服务捕获了 `vmcore` 等文件信息, 如下所示从堆栈的信息来看, 系统在进行 xfs 相关操作的时候进行了计时器中断(`apic_timer_interrupt`), 中断程序在更新进程的使用时间(`update_process_times`)的过程中, 出现了空指针(`RIP: run_posix_cpu_timers+164`)而造成内核崩溃:
```bash
crash> sys
      KERNEL: /usr/lib/debug/lib/modules/3.10.0-327.18.2.el7.x86_64/vmlinux
    DUMPFILE: vmcore  [PARTIAL DUMP]
        CPUS: 40
    NODENAME: czhost
     MACHINE: x86_64  (2197 Mhz)
      MEMORY: 127.9 GB
       PANIC: "BUG: unable to handle kernel NULL pointer dereference at 0000000000000140"
crash> 
crash> bt
PID: 80589  TASK: ffff8807deb08000  CPU: 0   COMMAND: "commserver"
 #0 [ffff88103f203a38] machine_kexec at ffffffff81051beb
 #1 [ffff88103f203a98] crash_kexec at ffffffff810f2782
 #2 [ffff88103f203b68] oops_end at ffffffff8163ea48
 #3 [ffff88103f203b90] no_context at ffffffff8162eb28
 #4 [ffff88103f203be0] __bad_area_nosemaphore at ffffffff8162ebbe
 #5 [ffff88103f203c28] bad_area_nosemaphore at ffffffff8162ed28
 #6 [ffff88103f203c38] __do_page_fault at ffffffff8164184e
 #7 [ffff88103f203c98] do_page_fault at ffffffff816419e3
 #8 [ffff88103f203cc0] page_fault at ffffffff8163dc48
    [exception RIP: run_posix_cpu_timers+164]
    RIP: ffffffff810a86f4  RSP: ffff88103f203d70  RFLAGS: 00010046
    RAX: 0000000000000000  RBX: ffffffff81a684e0  RCX: ffffffff81a68a70
    RDX: ffff88103f203db8  RSI: ffff88103f203da0  RDI: ffffffff81a684e0
    RBP: ffff88103f203e00   R8: ffffffff81a68a78   R9: ffff88103f203d38
    R10: 0000000000000000  R11: 0000000000000005  R12: ffff88103f203da8
    R13: ffffffff819a5f80  R14: ffff88103f20dfa0  R15: 0000000000000000
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
 #9 [ffff88103f203e08] update_process_times at ffffffff8108e8ee
#10 [ffff88103f203e68] update_process_times at ffffffff8108e8c7
#11 [ffff88103f203e90] tick_sched_handle at ffffffff810e0825
#12 [ffff88103f203eb0] tick_sched_timer at ffffffff810e08a1
#13 [ffff88103f203ed8] __hrtimer_run_queues at ffffffff810a9d42
#14 [ffff88103f203f30] hrtimer_interrupt at ffffffff810aa2e0
#15 [ffff88103f203f80] local_apic_timer_interrupt at ffffffff81049537
#16 [ffff88103f203f98] smp_apic_timer_interrupt at ffffffff8164874f
#17 [ffff88103f203fb0] apic_timer_interrupt at ffffffff81646e1d
--- <IRQ stack> ---
#18 [ffff88046102fad8] apic_timer_interrupt at ffffffff81646e1d
    [exception RIP: xfs_log_reserve+53]
    RIP: ffffffffa01e10f5  RSP: ffff88046102fb88  RFLAGS: 00000246
    RAX: 00000000fffffffb  RBX: ffffea0004066b40  RCX: ffff880002f35980
    RDX: 0000000000000000  RSI: 0000000000000198  RDI: ffff882025dd9000
    RBP: ffff88046102fbb0   R8: 0000000000000069   R9: 0000000000000000
    R10: ffff88046102ffd8  R11: 0000000000000293  R12: ffff88046102fb28
    R13: 0000000000000246  R14: ffff88000ee3d820  R15: ffff88000ee3d808
    ORIG_RAX: ffffffffffffff10  CS: 0010  SS: 0018
#19 [ffff88046102fbb8] xfs_trans_reserve at ffffffffa01dbad5 [xfs]
#20 [ffff88046102fc00] xfs_vn_update_time at ffffffffa01cd416 [xfs]
#21 [ffff88046102fc40] update_time at ffffffff811f9c55
#22 [ffff88046102fc70] file_update_time at ffffffff811f9f00
#23 [ffff88046102fcb0] xfs_file_aio_write_checks at ffffffffa01c492d [xfs]
#24 [ffff88046102fd18] xfs_file_buffered_aio_write at ffffffffa01c4a23 [xfs]
#25 [ffff88046102fdc8] xfs_file_aio_write at ffffffffa01c4cc0 [xfs]
#26 [ffff88046102fe20] do_sync_write at ffffffff811de02d
#27 [ffff88046102fef8] vfs_write at ffffffff811de84d
#28 [ffff88046102ff38] sys_write at ffffffff811df2ef
#29 [ffff88046102ff80] system_call_fastpath at ffffffff816461c9
    RIP: 00007fd7480bf51d  RSP: 00007fd74511dac8  RFLAGS: 00010297
    RAX: 0000000000000001  RBX: ffffffff816461c9  RCX: 00000000fffffffc
    RDX: 0000000000000059  RSI: 00007fd749415000  RDI: 0000000000000169
    RBP: 00007fd749415000   R8: 00007fd7403c53d0   R9: 00007fd74511e700
    R10: 3030302d30303030  R11: 0000000000000293  R12: 0000000021e4f8cc
    R13: 0000000000000059  R14: 00007fd7403c52f0  R15: 0000000000000059
    ORIG_RAX: 0000000000000001  CS: 0033  SS: 002b


crash> log | tail -n 61
[16758125.174987] BUG: unable to handle kernel NULL pointer dereference at 0000000000000140
[16758125.175089] IP: [<ffffffff810a86f4>] run_posix_cpu_timers+0xa4/0x840
[16758125.175165] PGD 2d6359067 PUD 861340067 PMD 0 
[16758125.175211] Oops: 0000 [#1] SMP 
......

```

从函数 `run_posix_cpu_timers` 的执行过程来看, 最后终止在 `kernel/posix-cpu-timers.c` 程序的 `1292` 行代码, 函数中的 tsk 进程信息则由函数 `update_process_times` 传递, 如下所示, 
```c
crash> dis -rl run_posix_cpu_timers+164
....
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/posix-cpu-timers.c: 1291
0xffffffff810a86ed <run_posix_cpu_timers+157>:  mov    0x768(%rbx),%r15
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/posix-cpu-timers.c: 1292
0xffffffff810a86f4 <run_posix_cpu_timers+164>:  mov    0x140(%r15),%ecx
crash> gdb list 1290
1273 static inline int fastpath_timer_check(struct task_struct *tsk)
1274 {
1275         struct signal_struct *sig;
1276         cputime_t utime, stime;
1277 
1278         task_cputime(tsk, &utime, &stime);
1279 
1280         if (!task_cputime_zero(&tsk->cputime_expires)) {
1281                 struct task_cputime task_sample = {
1282                         .utime = utime,
1283                         .stime = stime,
1284                         .sum_exec_runtime = tsk->se.sum_exec_runtime
1285                    };
1286    
1287                    if (task_cputime_expired(&task_sample, &tsk->cputime_expires))
1288                            return 1;
1289            }
1290    
1291            sig = tsk->signal;
1292            if (sig->cputimer.running) {
1293                    struct task_cputime group_sample;
1294    

crash> dis -rl ffffffff8108e8c7
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1370
......
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/arch/x86/include/asm/current.h: 14
0xffffffff8108e89c <update_process_times+28>:   mov    %gs:0xb7c0,%rbx

//source/kernel/timer.h
1369 void update_process_times(int user_tick)
1370 {
1371         struct task_struct *p = current;
1372         int cpu = smp_processor_id();
1373 
1374         /* Note: this timer irq context must be accounted for as well. */
1375         account_process_tick(p, user_tick);
1376         run_local_timers();
1377         rcu_check_callbacks(cpu, user_tick);
1378 #ifdef CONFIG_IRQ_WORK
1379         if (in_irq())
1380                 irq_work_tick();
1381 #endif
1382         scheduler_tick();
1383         run_posix_cpu_timers(p);
1384 }

//source/arch/x86/include/asm/current.h
  8 struct task_struct;
  9 
 10 DECLARE_PER_CPU(struct task_struct *, current_task);
 11 
 12 static __always_inline struct task_struct *get_current(void)
 13 {
 14         return this_cpu_read_stable(current_task);
 15 }

crash> dis -rl ffffffff8108e8ee
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1370
...
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/arch/x86/include/asm/current.h: 14
0xffffffff8108e89c <update_process_times+28>:   mov    %gs:0xb7c0,%rbx
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1375
0xffffffff8108e8a5 <update_process_times+37>:   mov    %rbx,%rdi
0xffffffff8108e8a8 <update_process_times+40>:   callq  0xffffffff810bbec0 <account_process_tick>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1402
0xffffffff8108e8ad <update_process_times+45>:   callq  0xffffffff810aa670 <hrtimer_run_queues>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1403
0xffffffff8108e8b2 <update_process_times+50>:   mov    $0x1,%edi
0xffffffff8108e8b7 <update_process_times+55>:   callq  0xffffffff81084f30 <raise_softirq>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1377
0xffffffff8108e8bc <update_process_times+60>:   mov    %r12d,%esi
0xffffffff8108e8bf <update_process_times+63>:   mov    %r13d,%edi
0xffffffff8108e8c2 <update_process_times+66>:   callq  0xffffffff81126690 <rcu_check_callbacks>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/arch/x86/include/asm/thread_info.h: 211
0xffffffff8108e8c7 <update_process_times+71>:   mov    %gs:0xb7b8,%rax
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1379
0xffffffff8108e8d0 <update_process_times+80>:   testl  $0x3ff0000,-0x3fbc(%rax)
0xffffffff8108e8da <update_process_times+90>:   je     0xffffffff8108e8e1 <update_process_times+97>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1380
0xffffffff8108e8dc <update_process_times+92>:   callq  0xffffffff81156070 <irq_work_tick>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1382
0xffffffff8108e8e1 <update_process_times+97>:   callq  0xffffffff810b75c0 <scheduler_tick>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1383
0xffffffff8108e8e6 <update_process_times+102>:  mov    %rbx,%rdi     // task_struct variable
0xffffffff8108e8e9 <update_process_times+105>:  callq  0xffffffff810a8650 <run_posix_cpu_timers>
/usr/src/debug/kernel-3.10.0-327.18.2.el7/linux-3.10.0-327.18.2.el7.x86_64/kernel/timer.c: 1384
0xffffffff8108e8ee <update_process_times+110>:  pop    %rbx
```

从上述的信息来看, `update_process_times` 将进程的信息传给了 `run_posix_cpu_timers` 函数. `run_posix_cpu_timers` 函数的汇编代码中, 寄存器 `R15` 和 `RDI` 对应的值相同, 并且 RDI 寄存器为 `run_posix_cpu_timers` 函数的第一个参数, 上述的汇编代码中 `mov    %gs:0xb7c0,%rbx`, 0xb7c0 即为 `update_process_times` 函数的task_struct 结构体的 p 指针变量. 从下述的分析可以看到 p 变量的 signal_struct 变量正常, cputimer.running 为 0:
```c
crash> kmem -o | grep 'CPU 0'
  CPU 0: ffff88103f200000
crash> eval ffff88103f200000 + 0xb7c0
hexadecimal: ffff88103f20b7c0  
    decimal: 18446612202092804032  (-131871616747584)
      octal: 1777774201007710133700
     binary: 1111111111111111100010000001000000111111001000001011011111000000
crash> rd ffff88103f20b7c0
ffff88103f20b7c0:  ffff8807deb08000                    ........
crash> struct task_struct ffff8807deb08000 
struct task_struct {
  state = 0, 
  stack = 0xffff88046102c000, 
...
  signal = 0xffff88108bea8d80,
  pid = 80589, //commserver task
  tgid = 80586,

crash> struct signal_struct 0xffff88108bea8d80
struct signal_struct {
  sigcnt = {
    counter = 77
...
  cputimer = {
    cputime = {
      utime = 0, 
      stime = 0, 
      sum_exec_runtime = 0
    }, 
    running = 0, 
    lock = {
```

不过我们从 1292 行代码即可看到, 程序在引用 `signal_struct` 结构体的 `cuptimer` 成员的时候却成为了空值,导致执行 `sig->cputimer.running` 代码的时候出现内核崩溃. 对比上述的汇编代码来看 `rbx` 寄存器的值在传给 `rdi` 之前经过了以下函数的处理:
```
account_process_tick
hrtimer_run_queues
raise_softirq
rcu_check_callbacks
irq_work_tick
scheduler_tick
```
看起来有可能是上述的哪个函数 pop 了错误的 `rbx`, 导致传给 `run_posix_cpu_timers` 的变量为空值. 


### 触发条件

目前并未找到引起空指针的原因, 红帽知识库, dell 和 intel 相关的站点也未找到关于上述堆栈的错误信息. 不过从下面两个角度来看最好不做主机的 BIOS 和系统内核的升级:

```
1. 中断相关的代码在最新版 3.10.0-957 内核中未见变更;
2. 主机 BIOS 版本为 2.0.1, 到最新的 2.9.1 版本的 changelog 中未见到相关 bug 说明;
```

在第二点中, 由于堆栈里显示的是计时器中断没有获取到对应 cpu 0 的进程信息才引起了空指针，如果触发条件和 cpu 无关, 升级 BIOS 其实没什么作用.

### 参考

[stack-frame-layout-on-x86_64](https://eli.thegreenplace.net/2011/09/06/stack-frame-layout-on-x86-64/)  
[intel-intro](https://www3.nd.edu/~dthain/courses/cse40243/fall2015/intel-intro.html)  
[dell-R430-BIOS-driver](https://www.dell.com/support/home/us/en/04/drivers/driversdetails?driverid=7V25P&oscode=W12R2&productcode=poweredge-r430)  
