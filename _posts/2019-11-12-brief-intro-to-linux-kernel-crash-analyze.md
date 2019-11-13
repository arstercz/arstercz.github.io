---
layout: post
title: "Linux 系统内核崩溃分析处理简介"
tags: [linux, crash, kernel]
comments: false
---

## 背景说明

目前绝大多数的 Linux 发行版都会将 [kdump.service](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/kernel_administration_guide/kernel_crash_dump_guide) 服务默认开启, 以方便在内核崩溃的时候, 可以通过 kdump 服务提供的 [kexec](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/7/html/tuning_guide/using_kdump_and_kexec_with_the_rt_kernel) 机制快速的启用保留在内存中的第二个内核来收集并转储内核崩溃的日志信息(`vmcore 等文件`), 这种机制需要服务器硬件特性的支持, 不过现今常用的服务器系列均已支持.

如果没有特别设置, 系统都采用默认的 kdump 服务配置, 崩溃的日志文件默认以 disk 方式保存在本地的磁盘目录, `Centos/Redhat` 系列的系统主要保存在以下目录:
```
/var/crash/
```

一般生成的 `vmcore` 文件仅仅是内核崩溃时的一部分信息, 如果全部导出对磁盘和时间都是很大的消耗, 默认情况下, dump 的级别为 31, 仅导出内核态的数据, 详见 [makedumpfile](https://linux.die.net/man/8/makedumpfile) `-d` 选项. 这种情况下系统崩溃一般生成的 `vmcore` 文件大小受崩溃时内核占用的内存决定, 通常不会很大. 下面则主要介绍如何收集并简单分析这些 vmcore 文件.

### 目录列表

* [获取 vmcore](#获取-vmcore)
* [分析 vmcore](#分析-vmcore)
* [分析 vmcore 的目的](#分析-vmcore-的目的)
* [线上处理注意事项](#线上处理注意事项)
* [参考](#参考)


## 获取 vmcore

我们在主机中分析 vmcore 文件的时候需要系统安装对应内核版本的 `debuginfo` 安装包以便获取函数的符号信息. 以如下内核版本为例:

```
kernel-3.10.0-957.27.2.el7.x86_64            -- 系统内核版本
kernel-debuginfo-3.10.0-957.27.2.el7.x86_64  -- 安装对应的 debuginfo 版本
```

所以想要快速的分析 `vmcore` 文件大概可以采用以下两种方式:
```
1. 在出问题的机器中直接安装对应版本的 debuginfo 包;
2. 将 vmcore 文件推到指定的主机进行分析;
```

上面两种方式都需要在主机中安装 `crash` 工具, 第一种方式相对快速, 不过会修改服务的主机, 另外也不容易大范围的安装到线上的所有机器. 第二种方式较慢, 具体取决于传输的速度, 不过很适合对线上故障的汇总分析. 

我们通常采用第二种方式, 可以修改 `kdump` 配置以 nfs 或 ssh 方式将生成的日志传到指定的机器, 也可以在问题主机重启后手动传到指定的机器. 当然主机间通信的速度要足够快, 崩溃日志传送完成后才会开始重启操作, 所以越慢就意味着机器正常重启需要的时间越长, 相应的从内核崩溃到可以简单的 `crash` 分析之间的时间间隔就越大.

## 分析 vmcore

安装 `debuginfo` 包的目的在于获取对应内核版本的符号信息(vmlinux 文件), 所以我们可以在指定机器中收集了业务运行的所有发行版内核对应的 `debuginfo` 包和内核源代码文件(方便查看代码), 如下所示:

```
/data/
├── kernel-crash       -- 收到的各主机的 vmcore 文件
├── kernel-debuginfo   -- 对应线上内核版本的 debuginfo 文件
├── kernel-package     -- 常用的 kernel 安装包
└── kernel-source      -- 对应线上内核版本的源码文件
```

可以通过 `rpm2cpio` 的方式解压不同版本的 rpm 包来获取文件. 比如以下示例:
```
mkdir /data/kernel-debuginfo-3.10.0-957.21.3 
pushd /data/kernel-debuginfo-3.10.0-957.21.3 
rpm2cpio /data/kernel-package/kernel-debuginfo-3.10.0-957.21.3.el7.src.rpm | cpio -div 
popd
```

`kernel-debuginfo` 和 `kernel-source` 目录中存储了各内核版本对应的文件, 如下所示:
```
/data/kernel-debuginfo/
├── kernel-debuginfo-2.6.32-642.13.1.el6.x86_64
├── kernel-debuginfo-3.10.0-862.14.4.el7.x86_64
├── kernel-debuginfo-3.10.0-957.21.3.el7.x86_64
└── kernel-debuginfo-3.10.0-957.27.2.el7.x86_64


/data/kernel-source/
├── linux-2.6.32-642.13.1.el6
├── linux-3.10.0-862.14.4.el7
├── linux-3.10.0-957.21.3.el7
├── linux-3.10.0-957.27.2.el7
```

通过 [crash](https://www.dedoimedo.com/computers/crash-analyze.html) 命令指定 `vmcore` 文件对应版本的 `vmlinux` 文件即可简单分析 vmcore 文件, 如下所示:
```bash
# crash /data/kernel-debuginfo/kernel-debuginfo-3.10.0-957.21.3.el7.x86_64/usr/lib/debug/lib/modules/3.10.0-957.21.3.el7.x86_64/vmlinux vmcore

crash 7.2.3-10.el7
......

      KERNEL: /export/kernel-debuginfo/kernel-debuginfo-3.10.0-957.21.3.el7.x86_64/usr/lib/debug/lib/modules/3.10.0-957.21.3.el7.x86_64/vmlinux
    DUMPFILE: vmcore  [PARTIAL DUMP]   <-----  仅部分内核转储信息
        CPUS: 40
 ...
     RELEASE: 3.10.0-957.21.3.el7.x86_64
 ...
       PANIC: "BUG: unable to handle kernel NULL pointer dereference at           (null)"
         PID: 167966
     COMMAND: "java"
        TASK: ffff880103d74500  [THREAD_INFO: ffff880013c68000]
         CPU: 11
       STATE: TASK_RUNNING (PANIC)

crash> bt
PID: 167966  TASK: ffff880103d74500  CPU: 11  COMMAND: "java"
 #0 [ffff880013c6ba38] machine_kexec at ffffffff81051beb
 #1 [ffff880013c6ba98] crash_kexec at ffffffff810f2782
 #2 [ffff880013c6bb68] oops_end at ffffffff8163ea48
 #3 [ffff880013c6bb90] no_context at ffffffff8162eb28
 #4 [ffff880013c6bbe0] __bad_area_nosemaphore at ffffffff8162ebbe
 #5 [ffff880013c6bc28] bad_area_nosemaphore at ffffffff8162ed28
 #6 [ffff880013c6bc38] __do_page_fault at ffffffff8164184e
 #7 [ffff880013c6bc98] do_page_fault at ffffffff816419e3
 #8 [ffff880013c6bcc0] page_fault at ffffffff8163dc48
    [exception RIP: unknown or invalid address]
    RIP: 0000000000000000  RSP: ffff880013c6bd78  RFLAGS: 00010282
    RAX: ffff880103d74500  RBX: ffff880013c6be10  RCX: ffff880013c6bfd8
    RDX: 0000000000000000  RSI: 0000000000000000  RDI: ffff880103d74500
    RBP: 0000000000000000   R8: ffff880013c68000   R9: 0000000000000018
    R10: 0000000000000000  R11: 0000000000000001  R12: 0000000000000001
    R13: 00007f7e88012454  R14: ffffc9001ce8efc0  R15: ffff880013c6bd60
    ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
......
crash> 
``` 

可以参考 [crash-book](https://www.dedoimedo.com/computers/crash-book.html) 学习更多的调试技巧.

## 分析 vmcore 的目的

内核崩溃时会将 kernel buffer 中的信息写到 `vmcore-dmesg.txt` 文件, 不过由于缺乏符号信息我们一般难以找到更细致的线索. 而 `vmcore` 文件仅导出了部分内核转储日志, 实际上也不一定准确, 不过可以提供汇编和代码级的信息. 通常需要我们结合两个文件共同查看. 不过在实际的使用中, 存在很大的局限性, 因为很多时候难以确定问题的具体原因, 即便确定了原因我们可能也难以升级内核, 如果没有单独维护补丁更新, 就无法使用 kpatch 等在线升级功能. 所以从这方面来看, 每次出现内核崩溃的时候, 我们分析 `vmcore` 的目的主要在于以下几点: 
```
1. 明白内核崩溃的大致原因;
2. 可以对内核崩溃的原因做更细致的分析;
3. 可以对故障事件做代码级别的分类和汇总;
4. 方便第三方厂商(如果购买了服务)分析原因定位问题;
```

## 线上处理注意事项

### kdump 配置问题

如果出现内核问题的频率不高, kdump 生成的日志可以仍旧以默认配置为主, 日志会存放到本地的 `/var/crash` 目录:
```
# grep ^path /etc/kdump.conf 
path /var/crash
```

如果产生的频率较高, 可以配置 `ssh` 选项, 将产生的崩溃日志直接发送到对应内网的其它机器. 注意内网通信的速度要够快, 越慢则意味着传送文件的速度越慢, 机器正常重启需要的时间越长. 配置 ssh 选项需要注意以下设置:
```
# /etc/kdump.conf

path /var/crash
ssh kerenl-crash@collect-host
default dump_to_rootfs                                      # 如果 ssh 失败则选择将日志转储到本地磁盘路径
core_collector makedumpfile -l --message-level 1 -d 31 -F   # 如果启用 ssh, 则增加 -F 选项, 使导出到远程机器的数据日志为 flattened 格式. 
```
启用 ssh 选项需要在 `makedumpfile` 命令中增加 `-F` 选项, 数据会以 `flattened` 格式存储, 如果 ssh 失败则以本地磁盘的标准格式存储. 远程主机收到日志后, 以 `flat` 为后缀名, 通过 `-R` 选项可以将 flat 格式转为标准格式, 如下所示:
```
makedumpfile -R vmcore < vmcore.flat
```

### 快速查看原因

在需要快速了解崩溃原因的时候, 可以简单查看崩溃主机(如果重启成功)的 `vmcore-dmesg.txt` 文件, 该文件列出了内核崩溃时的堆栈信息, 有助于我们大致了解崩溃的原因, 方便处理措施的决断. 如下所示为生成的日志文件通常的路径:
```
/var/crash/127.0.0.1-2019-11-11-08:40:08/vmcore-dmesg.txt
```

### 加快 vmcore 分析

`vmcore` 文件的大小受 kdump 参数 dump 级别决定, 默认为 31 仅导出内核态的数据. 这种级别下一般由崩溃时内核占用的内存决定. 可以查看 `/proc/meminfo` 的 Slab 信息查看内核态大概的数据, 通常情况下 vmcore 都会小于 slab 的值. vmcore 传到指定的机器需要一定的时间, 如果传输较慢, 可以将 vmcore 文件拉倒对应内网机器进行分析. 该机器需要提前装好对应内核版本的 `debuginfo` 包, 当然不用非要 rpm 安装, 我们可以将 `debuginfo` 包通过 `rpm2cpio` 方式解压出来单独存放到指定的目录. 

*备注*: 使用 crash 工具分析 vmcore 文件的时候通常会出现 `[PARTIAL DUMP]` 的提示, 这种提示一般在设置 dump 级别的时候进行提示, 更多可以参考 [bugzella-857111](https://bugzilla.redhat.com/show_bug.cgi?id=857111).

### 处理反馈及建议

在分析具体原因的时候我们可以遵循以下的规则尽快给业务人员反馈处理建议:
```
1. 快速查看 vmcore-dmesg 文件了解大概的故障原因;
2. 如果碰到过此类问题就参考知识库的处理;
3. 如果没有碰到过, 需要单独分析 vmcore 日志, 在指定时间内反馈处理建议;
4. 反馈后再慢慢分析可能的原因和处理方式, 汇总成知识库;
```

## 参考

[kdump.service](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/kernel_administration_guide/kernel_crash_dump_guide)  
[how does kexec works](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux_for_real_time/7/html/tuning_guide/using_kdump_and_kexec_with_the_rt_kernel)  
[kdump](https://www.kernel.org/doc/Documentation/kdump/kdump.txt)  
[crash-analyze](https://www.dedoimedo.com/computers/crash-analyze.html)  
[crash-book-pdf](https://www.dedoimedo.com/computers/www.dedoimedo.com-crash-book.pdf)  
