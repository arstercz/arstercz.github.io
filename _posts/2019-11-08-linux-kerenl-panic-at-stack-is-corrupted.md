---
layout: post
title: "Linux kernel panic at stack is corrupted"
tags: [kernel, panic]
comments: false
---

## 问题说明

一台机器异常重启后, 从 `vmcore` 文件的分析来看, 内核的崩溃是由于触发了 gcc 的 `-fstack-protector` 特性, 如下所示, `stack-protector` 即意味着内核函数存在栈溢出的问题:

```bash
crash> sys
      KERNEL: /usr/lib/debug/lib/modules/3.10.0-862.14.2.el7.x86_64/vmlinux
    DUMPFILE: vmcore  [PARTIAL DUMP]
        CPUS: 40
        DATE: Thu Nov  5 15:40:53 2019
      UPTIME: 171 days, 21:25:01
LOAD AVERAGE: 1.45, 1.59, 1.61
       TASKS: 12533
    NODENAME: czh1
     RELEASE: 3.10.0-862.14.2.el7.x86_64
     VERSION: #1 SMP Wed Sep 26 15:12:11 UTC 2018
     MACHINE: x86_64  (2197 Mhz)
      MEMORY: 127.9 GB
       PANIC: "Kernel panic - not syncing: stack-protector: Kernel stack is corrupted in: ffffffff810aa8da"
```

## 分析说明

目前绝大多数的 Linux 发行版都会开启 `CONFIG_HAVE_CC_STACKPROTECTOR` 选项, 以在编译内核的时候开启 gcc 的 `-fstack-protector` 特性来保护内核函数的栈溢出避免引起更严重的错误. 对内核而言, 只要检测到栈溢出的问题则调用 `__stack_chk_fail(和用户空间的 glibc 提供的 __stack_chk_fail 类似)` 函数, 该函数会直接调用 `panic` 函数使内核直接崩溃以避免更严重的问题, 如下所示:
```c
//src/kernel/panic.c
......
#ifdef CONFIG_CC_STACKPROTECTOR

/*
 * Called when gcc's -fstack-protector feature is used, and
 * gcc detects corruption of the on-stack canary value
 */
void __stack_chk_fail(void)
{
        panic("stack-protector: Kernel stack is corrupted in: %p\n",
                __builtin_return_address(0));
}
EXPORT_SYMBOL(__stack_chk_fail);
```

我们从下面的调用关系分析来看, `__stack_chk_fail` 是由内核函数 `hrtimer_nanosleep` 函数调用:

```bash
crash> bt
PID: 115885  TASK: ffff8812473bae00  CPU: 18  COMMAND: "App01"
 #0 [ffff8812473e3b68] machine_kexec at ffffffff81051beb
 #1 [ffff8812473e3bc8] crash_kexec at ffffffff810f2782
 #2 [ffff8812473e3c98] panic at ffffffff8162f28e
 #3 [ffff8812473e3d18] __stack_chk_fail at ffffffff8107b00b
 #4 [ffff8812473e3d28] hrtimer_nanosleep at ffffffff810aa8da     <---- 此处
 #5 [ffff8812473e3e70] do_futex at ffffffff810e52ae
 #6 [ffff8812473e3f08] sys_futex at ffffffff810e57e0
 #7 [ffff8812473e3f80] system_call_fastpath at ffffffff816461c9
    RIP: 00007fa399c8f6d5  RSP: 00007fa37479f000  RFLAGS: 00010246
    RAX: 00000000000000ca  RBX: ffffffff816461c9  RCX: 0000000000004000
    RDX: 00000000015a40f6  RSI: 0000000000000080  RDI: 0000000036972d5c
    RBP: 00007fa3747dfc80   R8: 0000000036972d00   R9: 0000000000ad2059
    R10: 0000000000000000  R11: 0000000000000246  R12: 0000000000000000
    R13: 00007fa3747e0700  R14: 00007fa3747e09c0  R15: 0000000000000000
    ORIG_RAX: 00000000000000ca  CS: 0033  SS: 002b
crash> 
crash> bt -r
......
ffff8812473e3c90:  ffff8812473e3d10 panic+223        
ffff8812473e3ca0:  ffff881200000010 ffff8812473e3d20 
ffff8812473e3cb0:  ffff8812473e3cc0 000000001f07388f 
ffff8812473e3cc0:  ffff8812473e3de0 hrtimer_nanosleep+346 
ffff8812473e3cd0:  0000000000000000 ffff8812473e3fd8 
ffff8812473e3ce0:  ffff8812473e0000 000000000000001c 
ffff8812473e3cf0:  00000000299015d3 0000000000000000 
ffff8812473e3d00:  0000000000000000 0000000036972d5c 
ffff8812473e3d10:  ffff8812473e3d20 __stack_chk_fail+27 
ffff8812473e3d20:  ffff8812473e3e68 hrtimer_nanosleep+346  <-- 此处 
ffff8812473e3d30:  check_preempt_curr+117 0000000000000000 
ffff8812473e3d40:  ffff8812473e3e10 00000000015a40f6 
ffff8812473e3d50:  0000000036972d5c ffffc9001ce115c0 
```

单独查看 `hrtimer_nanosleep`, 可以看到 gcc 的 `-fstack-protector` 特性在 `hrtimer_nanosleep` 函数的开始和结束位置插入了一些汇编代码, 来修改函数栈的组织, 在 `RBP` 和缓冲区之间插入 `canary` 标识信息, 函数在返回的时候通过对比标识信息即可判断是否溢出, 如下所示: 

```bash
crash> dis -rl ffffffff810aa8da
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1508
0xffffffff810aa780 <hrtimer_nanosleep>: nopl   0x0(%rax,%rax,1) [FTRACE NOP]
...
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1508
0xffffffff810aa79c <hrtimer_nanosleep+28>:      push   %r12
0xffffffff810aa79e <hrtimer_nanosleep+30>:      mov    %edx,%r12d
0xffffffff810aa7a1 <hrtimer_nanosleep+33>:      push   %rbx
0xffffffff810aa7a2 <hrtimer_nanosleep+34>:      sub    $0x70,%rsp
0xffffffff810aa7a6 <hrtimer_nanosleep+38>:      mov    %gs:0x28,%rax              -----
0xffffffff810aa7af <hrtimer_nanosleep+47>:      mov    %rax,-0x28(%rbp)            函数开始处插入汇编代码, 将段寄存器 %gs:0x28 位置中的信息保存到 -0x28(%rbp) 基指针相对的 -0x28 位置处;
0xffffffff810aa7b3 <hrtimer_nanosleep+51>:      xor    %eax,%eax                  -----
...
...
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1537
0xffffffff810aa879 <hrtimer_nanosleep+249>:     mov    %edx,-0x3fa8(%rax)
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1539
0xffffffff810aa87f <hrtimer_nanosleep+255>:     mov    -0x78(%rbp),%rdx
0xffffffff810aa883 <hrtimer_nanosleep+259>:     mov    %rdx,-0x3f90(%rax)
0xffffffff810aa88a <hrtimer_nanosleep+266>:     mov    $0xfffffffffffffdfc,%rdx
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1545
0xffffffff810aa891 <hrtimer_nanosleep+273>:     mov    -0x28(%rbp),%rbx                             ------
0xffffffff810aa895 <hrtimer_nanosleep+277>:     xor    %gs:0x28,%rbx                                取出之前保存的 -0x28(%rbp) 位置的数据和当前的段寄存器 %gs:0x28 位置的数据进行异或比较, 如果不同标识栈溢出, 则跳转到 __stack_chk_fail 函数
0xffffffff810aa89e <hrtimer_nanosleep+286>:     mov    %rdx,%rax                                     
0xffffffff810aa8a1 <hrtimer_nanosleep+289>:     jne    0xffffffff810aa8d5 <hrtimer_nanosleep+341>   ------
0xffffffff810aa8a3 <hrtimer_nanosleep+291>:     add    $0x70,%rsp
0xffffffff810aa8a7 <hrtimer_nanosleep+295>:     pop    %rbx
0xffffffff810aa8a8 <hrtimer_nanosleep+296>:     pop    %r12
0xffffffff810aa8aa <hrtimer_nanosleep+298>:     pop    %r13
0xffffffff810aa8ac <hrtimer_nanosleep+300>:     pop    %r14
0xffffffff810aa8ae <hrtimer_nanosleep+302>:     pop    %rbp
0xffffffff810aa8af <hrtimer_nanosleep+303>:     retq   
...
0xffffffff810aa8d3 <hrtimer_nanosleep+339>:     jmp    0xffffffff810aa891 <hrtimer_nanosleep+273>
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/kernel/hrtimer.c: 1545
0xffffffff810aa8d5 <hrtimer_nanosleep+341>:     callq  0xffffffff8107aff0 <__stack_chk_fail>
/usr/src/debug/kernel-3.10.0-862.14.2.el7/linux-3.10.0-862.14.2.el7.x86_64/include/linux/ktime.h: 78
0xffffffff810aa8da <hrtimer_nanosleep+346>:     movabs $0x7fffffffffffffff,%rax
```

也就是说内核函数 `hrtimer_nanosleep` 在运行的时候出现了栈溢出的问题引起内核崩溃. 

## 如何处理

关于 `stack-protector` 机制引起的内核崩溃的问题到目前(可以查看 `kerne-3.10.0-1062` 版本的 changelog)为止, 还未有解决的方式, 出现这种内核栈溢出的问题可以反馈对应系统的厂商解决, 参考红帽的知识库文档[redhat-3375591](https://access.redhat.com/solutions/3375591):
```
Resolution

The Red Hat Enterprise Linux 7 (x86_64) kernel, is built with Stack Protector support. Stack Protector works by placing a 
predefined pattern, at the start of the stack frame and verifying that it has not been overwritten when returning from the 
function. The pattern is called stack canary. By default, when the stack canary is found to be overwritten, panic() is 
invoked. The address listed in the panic string is where the stack canary corruption was detected.

Root Cause

The Stack Protector mechanism detected a stack frame corruption.
Please contact Red Hat Technical Support for further assistance.
```

当然我们也需要持续关注, 如果出现此类问题的机器较多可以考虑升级内核的方式看能否避免此类问题.
