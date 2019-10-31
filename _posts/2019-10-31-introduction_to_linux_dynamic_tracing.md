---
layout: post
title: "Linux 系统动态追踪技术介绍"
tags: [linux, trace]
comments: false
---

## 目录

* [动态追踪历史](#动态追踪历史)
* [追踪机制说明](#追踪机制说明)
* [常用追踪工具](#常用追踪工具)
* [线上实践指南](#线上实践指南)
* [总结](#参考)
* [参考](#参考)


## 动态追踪历史

严格来讲 Linux 中的动态追踪技术其实是一种高级的调试技术, 可以在内核态和用户态进行深入的分析, 方便开发者或系统管理者便捷快速的定位和处理问题.  Linux 在过去十多年的发展中, 演化了很多追踪技术, 不过一直没有一款可以媲美 `Solaris/FreeBSD` 系统中的 `DTrace` 追踪工具, 直到 `Linux 4.1+` 版本 [eBPF](https://lwn.net/Articles/740157/) 机制的出现, 这种情况才得到了极大的改善. 不过 `eBPF` 也不是一蹴而就的, 而是经过了漫长的过程才得以完善. 

如下所示, 为 Linux 追踪技术的大致发展历程(时间可能不够准确, 具体可参考 [kernel-tracing-page37](https://ftp.halifax.rwth-aachen.de/ccc/congress/2018/slides-pdf/35c3-9532-kernel_tracing_with_ebpf.pdf)):

| 年份 | 技术 |
| :-: | :-: | :-: |
| 2004 | kprobes/kretprobes |
| 2008 | ftrace |
| 2005 | systemtap |
| 2009 | perf_events |
| 2009 | tracepoints |
| 2012 | uprobes |
| 2015 ~ 至今 | eBPF (Linux 4.1+) |

经过长期的发展, `kprobes/uprobes` 机制在事件(events)的基础上分别为内核态和用户态提供了追踪调试的功能, 这也构成了 tracepoint 机制的基础, 后期的很多工具, 比如 `perf_events`, `ftrace` 等都是在其基础上演化而来. 参考由 [Brendan Gregg](http://www.brendangregg.com) 提供的资料来看, `kprobes/uprobes` 在 Linux 动态追踪层面起到了基石的作用, 如下所示:

![linux-probes.png]({{ site.baseurl }}/images/articles/201910/linux-probes.png)

更详细的介绍参见 [Tracing: no shortage of options](https://lwn.net/Articles/291091/), 下面则简单介绍下每种动态追踪工具的机制.

## 追踪机制说明

### kprobes/kretprobes/uprobes

[kprobes](https://lwn.net/Articles/132196/) 主要用来对内核进行调试追踪, 属于比较轻量级的机制, 本质上是在指定的探测点(比如函数的某行, 函数的入口地址和出口地址, 或者内核的指定地址处)插入一组处理程序. 内核执行到这组处理程序的时候就可以获取到当前正在执行的上下文信息, 比如当前的函数名, 函数处理的参数以及函数的返回值, 也可以获取到寄存器甚至全局数据结构的信息. 

`kretprobes` 在 `kprobes` 的机制上实现, 主要用于返回点(比如内核函数或者系统调用的返回值)的探测以及函数执行耗时的计算.

`uprobes`  机制类似 `kprobes`, 不过主要用户空间的追踪调试. 另外 `uprobes` 应该主要是由 [systemtap](https://sourceware.org/systemtap/) 实现并完善. 更多的使用示例见  [linux-ftrace-uprobe](http://www.brendangregg.com/blog/2015-06-28/linux-ftrace-uprobe.html)

### tracepoint

`tracepoint` 应该要比 `ftrace` 更早出现, 不过随着 `ftrace` 的完善, `tracepoint` 的机制也越来越成熟, 其本质上就是一种管理探测点(probe)和处理程序的机制, 管理员或者开发者可以动态的开启/关闭追踪功能. `perf` 和 `ftrace` 等工具也在很大程度上依赖了 `tracepoint` 特性.

### perf_event

[perf_event](https://perf.wiki.kernel.org/index.php/Main_Page) 随内核的主版本进行发布, 一直是 linux 用户的主要追踪工具, 通常由 `perf` 命令提供服务. 可以支持对 `tracepoint`, `kprobes` 和 `uprobes` 机制的处理, 另外 perf 也是可以对 cpu 性能进行计数的强大工具之一. 值得一提的是 perf 可以将追踪的数据保存起来(默认为 perf.data) 方便以后分析, 这类似 tcpdump 的机制, 在分析存在延迟或者上下文切换的问题时尤为有用. `Brendan Gregg` 的 [FlameGraph 性能火焰图](https://github.com/brendangregg/FlameGraph) 就是主要依靠 `perf_event` 的机制实现的.

### ftrace

[ftrace(function trace)](http://lwn.net/Articles/370423/) 则更像是一个完整的追踪框架, 可以支持对 `tracepoint`, `kprobes`, `uprobes` 机制的处理, 同时还提供了事件追踪(event tracing, 类似 tracepoint 和 function trace 的组合) , 追踪过滤, 事件的计数和计时, 记录函数执行流程等功能. 我们常用的 [perf-tools](https://github.com/brendangregg/perf-tools) 工具集就是依赖 `ftrace` 机制而实现的.

虽然 `ftrace` 的内部是复杂的, 不过输出的信息却以简单明了为主. 其提供了一个基于文件系统(debugfs)的用户空间层面的 API 来方便大家执行各种跟踪和概要分析. 更详细的使用示例可以参考 [ftrace-lwn-365835](https://lwn.net/Articles/365835/), 如下图所示, 大致为 `ftrace` 的原理:

![ftrace-theory.png]({{ site.baseurl }}/images/articles/201910/ftrace-theory.png)

`kprobes` 相当于图中的 `A`, 处理程序相当于图中的 `B`, `tracepoint` 则相当于图中的 `A` 和 `B`, `ftrace` 则相当于在 `A`, `B` 的基础上增加了 `C` 和 `D` 的功能. 更多介绍见 [linux-ftrace](https://www.ibm.com/developerworks/cn/linux/1609_houp_ftrace/index.html)

### systemtap

`systemtap` 其实已经存在很长时间了, 不过一直没有合并到内核主版本中, 这意味着它必须紧跟内核的变化, 每个版本的变动, 都需要做相应的调整, 这种方式也直接造成了我们难以在线上大规模使用 systemtap. 不过 `systemtap` 提供了很成熟的调试符号及复杂的探针处理程序, 支持对 `tracepoint, kprobes 和 uprobes` 的处理, 同时也可以进行内核编程, 以及性能相关的统计分析. 所以从大的方面来看, `systemtap` 可以在系统调用, 用户空间以及内核空间几个方面实现细粒度的跟踪分析, 另外 `systemtap` 也实现了自己的脚本语言, 方便 `systemtap` 将这些脚本工具转换为内核模块加载运行. 更详细的介绍可以参考春哥的文章 [dynamic-tracing](https://openresty.org/posts/dynamic-tracing/). 

### eBPF

[eBPF: extended Berkeley Packet Filter](https://lwn.net/Articles/740157/) 已经被合并到了 Linux 内核的主版本中, 相当于一个内核虚拟机, 以 JIT(Just In Time) 的方式运行事件相关的追踪程序, 同时 eBPF 也支持对 `ftrace`, `perf_events` 等机制的处理. 另外 eBPF 在传统的包过滤器进行很大的变革, 其在内核追踪, 应用性能追踪, 流控等方面都做了很大的改变, 不过在接口的易用性方面还有待提高. 第三方的 [bpftrace](https://github.com/iovisor/bpftrace) 实现了对 eBPF 的封装, 支持 python, lua 等接口, 用起来方便了很多, 还有其提供的 [bcc](https://github.com/iovisor/bcc) 工具集在 `> Linux 4.1+` 的系统中被广泛应用. 可以说 eBPF 能够监控所有想监控的, 在 `Linux 4.1+` 系统中, 动态追踪工具使用 eBPF 一款即可. 低版本的内核更多的时候需要同时使用多个工具来互相辅助追踪分析.


## 常用追踪工具

下面则主要介绍一些常用的追踪工具, 其实了解上面的不同追踪机制后就会发现各种各样的分析工具都是建立在不同的机制上, 我们就会对各种工具的不同作用有一个清晰的认识.

### ftrace && utrace

基于 ftrace, utrace 机制的分析工具主要基于 `debugfs` 文件系统提供的接口而实现, 简单的使用可以参考 [ftrace-lwn-322666](https://lwn.net/Articles/322666/),  绝大多数的 Linux 发行版 都将 `debugfs/tracefs` 默认挂载到 `/sys/kernel/debug` 目录中. 如果没有挂载, 可以使用以下方式挂载(以 RedHat/Centos 发行版为例):

```bash
mount -t debugfs /sys/kernel/debug
```

基于 `ftrace, utrace` 实现的有名的工具主要以 `Brendan Gregg` 的 [perf-tools](https://github.com/brendangregg/perf-tools) 为代表, 该工具在用户空间和内核空间的不同层面均提供了对应的分析工具, 极大提高了我们的调试技巧. 不过基于这种机制的分析也不是万能的, 比如检测 tcp 重传的 [tcpretras](https://github.com/brendangregg/perf-tools/blob/master/net/tcpretrans) 工具目前仅支持 ipv4 的分析, ipv6 的分析可以通过 systemtap 或 eBPF 这些工具实现.

### perf

正如上面提到的, perf 工具也是一款很强大的工具, 不过有了 `ftrace, utrace` 的出现, perf 工具现在更多的用于 cpu 性能, 内核函数以及函数调用链的追踪分析上. `Brendan Gregg` 的 [FlameGraph 性能火焰图](https://github.com/brendangregg/FlameGraph) 即为此类工具的代表. 

###  strace && sysdig

这两款工具实际上仅对系统调用进行追踪分析. 如果需要追踪内核函数就需要依赖 `ftrace`, `systemtap`, `eBPF` 等工具. 很多情况下, 仅分析系统调用的使用也能解决很多疑难问题. 不过这两款工具的原理有很大的不同, 实际的使用中应该明确二者的不同点.

#### strace

strace 已经存在了很长时间, 其主要依靠 [ptrace](https://en.wikipedia.org/wiki/Ptrace) 来追踪用户空间的所有系统调用, 这种机制的问题在于应用程序每做一次系统调用都需要 ptrace 进行捕获, 获取到数据后再放行响应的系统调用. 如下所示:

![linux-strace.png]({{ site.baseurl }}/images/articles/201910/linux-strace.png)

为了能够获取到系统调用的详细信息, ptrace 需要做很多复杂的操作, 如果应用程序的系统调用很频繁, strace 就会对程序产生很大的影响. man 手册中的 bug 部分也着重强调了这点:
```
$ man 1 strace
....
BUGS
       Programs that use the setuid bit do not have effective user ID privileges while being traced.

       A traced process runs slowly.
```

以 [strace-wow-much-syscall](http://www.brendangregg.com/blog/2014-05-11/strace-wow-much-syscall.html) 文章中的测试为例:

```bash
$ dd if=/dev/zero of=/dev/null bs=1 count=500k
512000+0 records in
512000+0 records out
512000 bytes (512 kB) copied, 0.103851 s, 4.9 MB/s

$ strace -eaccept dd if=/dev/zero of=/dev/null bs=1 count=500k
512000+0 records in
512000+0 records out
512000 bytes (512 kB) copied, 45.9599 s, 11.1 kB/s
```

可以看到性能下降了很多, 当然这个测试以读写为例, 正常业务以内存, 锁, 读写等系统调用为主, 在业务清闲的时候影响不会那么明显. 如果只是调试执行单个命令行, 则用 strace 调试会很方便. 值得一提的是, 自身存在信号处理的应用程序在通过 ptrace 追踪的时候可能造成挂起的问题. 在实际排查问题的时候最好慎重使用这些工具. 

#### sysdig

sysdig 则以另一种创新的方式获取所有的系统调用, 从下图来看:

![linux-sysdig.png]({{ site.baseurl }}/images/articles/201910/linux-sysdig.png)

sysdig 以内核模块的方式监控获取所有的系统调用, 其使用方式类似 libpcap/tcpdump 的用法, 可以将一段时间内的系统调用数据暂存起来供后续的跟踪分析. 因为对于 [syscall_64](https://github.com/torvalds/linux/blob/master/arch/x86/entry/syscalls/syscall_64.tbl) 来讲, 用户态层面的系统调用最终都会陷入到内核态, 由内核去完成对应的功能. sysdig 在内核态也就能很方便的获取到进程的上下文信息. sysdig 以非阻塞(non-blocking), 零拷贝(zero-copy) 的方式获取数据, 所以在实际使用中对在线的业务只有很轻微的影响. 线上繁忙程序的分析可以考虑使用 `sysdig` 而不是 `strace`.

更多 sysdig 示例可以参考: [Sysdig-Examples](https://github.com/draios/sysdig/wiki/Sysdig-Examples)

### systemtap toolkit

[systemtap](https://sourceware.org/systemtap/) 其实对新手很不友好, 深入的分析需要在 systemtap 脚本中内嵌相关的代码才行, 如果嵌入 c 代码, 那么 `systemtap` 就很难保证代码的安全性, 甚至造成内核崩溃的风险, 毕竟嵌入的代码是可以直接和内核交互的, 一些安全函数的使用, 可以参考官方的[手册文档](https://sourceware.org/systemtap/tutorial/). 

目前网上已经存在了很多 `systemtap` 工具脚本, 比如下面的工具, 很多工具也都当做示例整理到了 `systemtap-client` 安装包中. 如下所示:

[systemtap-lwtools](https://github.com/brendangregg/systemtap-lwtools)  
[youzan-systemtap-toolkit](https://github.com/youzan/systemtap-toolkit/)  
[openresty-systemtap-toolkit](https://github.com/openresty/openresty-systemtap-toolkit)  

这些工具满足了大多数的调试需求, 如果没有合适的可以参考其中的示例自行开发. 不过上述的几个工具本质上都是都是以 `stap ...` 的方式运行, 其中一些工具通过 `Perl` 语言进行了封装, 这种方式的好处主要有以下几点:

```
1. 选项参数可以动态变化, 比如指定不同的端口;
2. 随时设置 systemtap 的安全限制值, 比如 `MAXNESTING, MAXSTRINGLEN, MAXACTION` 等;
```

不过遗憾的是, 这种 `stap ...` 方式的运行需要系统安装`对应内核版本`(要和内核版本号一致)的 kernel 开发包和 debug 安装包以获取内核调试符号, `RedHat/Centos` 系统主要需要安装以下安装包:
```
kernel-3.10.0-957.27.2.el7.x86_64
kernel-headers-3.10.0-957.27.2.el7.x86_64
kernel-devel-3.10.0-957.27.2.el7.x86_64
kernel-debuginfo-3.10.0-957.27.2.el7.x86_64
kernel-debuginfo-common-x86_64-3.10.0-957.27.2.el7.x86_64
systemtap-4.0-9.el7.x86_64
```

`Debian/Ubuntu` 系统则需要安装以下包:
```
apt-get install -y systemtap gcc linux-image-$(uname -r)-dbgsym
```

一般线上的环境中很少安装 debug 调试包, 所以这种高级语言封装的方式可能并不适合大规模的使用. 不过我们可以将 systemtap 脚本编译为内核模块, 再将内核模块拷贝到同样内核版本的其它机器上使用, 以 Centos7 系统为例, 这种方式仅安装以下包即可:
```
kernel-3.10.0-957.27.2.el7.x86_64
kernel-headers-3.10.0-957.27.2.el7.x86_64
kernel-devel-3.10.0-957.27.2.el7.x86_64
systemtap-runtime-4.0-9.el7.x86_64
```

编译好的内核模块可以通过 `staprun` 来运行, 如下所示:
```
$ stap -r `uname -r` tcp_conn.stp -m tcp_conn.ko -p4  #第四阶段
Truncating module name to 'tcp_conn'
tcp_conn.ko

$ staprun tcp_conn.ko destport=6379
=> Only capture port: 6379

                        TIME   EUID    UID    GID              CMD    PID   PORT IP_SOURCE
Tue Oct 29 19:52:52 2019 CST    996    996    994     redis-server  35307   6379 10.0.21.5
```
这种方式比较适合线上的调试, 不过需要编译模块所在的机器内核版本与运行模块的机器一致.

### bpftrace && bcc

在 `2015 ~ 2017` 左右的时候, 网上出现了很多实现了封装 eBPF 的工具, 不过随着技术的发展, 目前稳定且持续发展的就只有 [iovisor](https://github.com/iovisor), 其主要提供以下两个工具方便大家对系统的调试排错:

[bpftrace](https://github.com/iovisor/bpftrace)  
[bcc](https://github.com/iovisor/bcc)  

`bcc` 则是在 `bpftrace` 的基础上实现的很多工具集, 从应用到内核, 不同层面的工具应用仅有. 最后再提醒下, eBPF 仅适用于 `Linux 4.1+` 的版本, 以 eBPF 开发的[进度](https://github.com/iovisor/bcc/blob/master/docs/kernel-versions.md)的来看, 
`eBPF` 在 `kernel-4.10` 之后的支持才相对全面, 线上在使用的时候尽量选择较高内核版本的发行版, 比如以下示例:
```
Redhat/Centos 8   -  4.18
Ubuntu 18.04 LTS  -  4.15
Debian 10(Buster) -  4.19  
```

## 线上实践指南

从上述的分析来看, Linux 系统的调试分析主要以内核版本分成两部分来看, eBPF 实际上是从 `3.15` 版本开始的, 不过我们为了稳妥安全, 这里还是以 4.1+ 版本作为分界线. 幸运的是 Linux 发行版一般都会将 `perf_event`, `kprobes/uprobes`, `ftrace` 等内置编译进去, 如果 `perf_event`, `ftrace` 等特性没有内置在内核中, 那就只能试试 systemtap, LTTng 等工具, 如下所示为 `Brendan Gregg` 提供的调试方式:

![linux-choose-debug.png]({{ site.baseurl }}/images/articles/201910/linux-choose-debug.png)

### 内核版本低于 4.1+

以 Centos7 系统为例, 其依赖 `3.10.0` 内核版本, 这就决定了我们只能通过 `perf_event`, `ftrace/utrace` 和 `systemtap` 的方式进行系统调试. 在实际使用的时候我们需要考虑不同的需求使用不同的工具, 如下所示为简单的总结:

| 需求 | 工具 |
| :-: | :-: |
| cpu 性能分析 | perf, systemtap |
| 函数调用链 | perf, ftrace |
| 函数及堆栈统计分析 | perf, systemtap |
| 函数执行追踪 | ftrace/utrace, systemtap |
| 系统调用分析 | ftrace, sysdig, strace(慎用), systemtap |

相比而言, 基于 `perf_event` 和 `ftrace` 的工具更为轻便, 定制性也更强, 大家可以按需修改. 不过部分分析还只能在用户层实现, 使用 systemtap 则更方便些, 可以直接在内核函数增加探针, 比如上述提到的 tcp 重传的抓取, 使用 `systemtap` 就可以很方便的获取到 `ipv4/ipv6` 的信息. 

当然不管使用哪种方式, 想要很方便的调试线上的环境, 我们都需要提前安装好以下安装包(以 Centos 为例):
```bash
kernel-3.10.0-957.27.2.el7.x86_64
kernel-headers-3.10.0-957.27.2.el7.x86_64
kernel-devel-3.10.0-957.27.2.el7.x86_64
perf-3.10.0-957.27.2.el7.x86_64
systemtap-runtime-4.0-9.el7.x86_64 (可选)
```

这里的版本需要和内核版本一致, `systemtap-runtime` 为可选项, 方便直接以 `staprun ...` 方式直接运行 `systemtap` 编译好的内核模块.

### 内核版本高于 4.1+

高于 `4.1+` 版本的系统则简单了许多, 可以直接通过 eBPF 获取想要调试的信息. 以 Centos8 为例, 仅需要安装以下包即可:
```bash
python3-bcc-0.7.0-5.el8.x86_64
bcc-0.7.0-5.el8.x86_64
bcc-tools-0.7.0-5.el8.x86_64
```

`/usr/share/bcc/tools` 路径即包含可用的工具脚本. 当然也可以继续使用 frace, systemtap 等工具.

## 总结

Linux 动态追踪是一个很大, 很复杂的领域, 上述的说明仅仅为简单的介绍, 希望能让大家对 Linux 的动态调试分析有一个整体的认识. 可以看到 Linux 的调试技术多种多样, 很多新兴的工具其实都是以上面所提到的机制为基石, 实际上很多调试需求可以通过多种工具来满足. 上述内容部分介绍可能有误, 如果存在问题请及时指正. 更多关于 Linux 调试的文章见下面的 `参考` 部分.

## 参考

### ftrace/utrace 说明

[ftrace-lwn-322666](https://lwn.net/Articles/322666/)  
[ftrace-lwn-365835](https://lwn.net/Articles/365835/)  
[ftrace-lwn-366796](https://lwn.net/Articles/366796/)  
[utrace-lwn-295715](https://lwn.net/Articles/295715/)  
[linux-ftrace](https://www.ibm.com/developerworks/cn/linux/1609_houp_ftrace/index.html)  

### kprobes/uprobes

[kernel-kprobes](https://www.kernel.org/doc/Documentation/kprobes.txt)  
[kprobes-lwn-132196](https://lwn.net/Articles/132196/)  
[kprobetrace](https://www.kernel.org/doc/html/v4.17/trace/kprobetrace.html)  
[dynamic-tracing-linux-user-and-kernel-space](https://opensource.com/article/17/7/dynamic-tracing-linux-user-and-kernel-space)  

### eBPF

[eBPF-lwn-740157](https://github.com/brendangregg/perf-tools)  
[eBPF 简史](https://www.ibm.com/developerworks/cn/linux/l-lo-eBPF-history/index.html)  
[learn eBPF tracing](http://www.brendangregg.com/blog/2019-01-01/learn-ebpf-tracing.html)  

### Linux tracing

[Tracing: no shortage of options](https://lwn.net/Articles/291091/)  
[choosing-a-linux-tracer](http://www.brendangregg.com/blog/2015-07-08/choosing-a-linux-tracer.html)  
[linux-performance-analysis-perf-tools.html](http://www.brendangregg.com/blog/2015-03-17/linux-performance-analysis-perf-tools.html)  
[sysdig-vs-dtrace-vs-strace-a-technical-discussion](https://sysdig.com/blog/sysdig-vs-dtrace-vs-strace-a-technical-discussion/)  
[dynamic-tracing](https://openresty.org/posts/dynamic-tracing/)  
[kernel-tracing-with-eBPF](https://ftp.halifax.rwth-aachen.de/ccc/congress/2018/slides-pdf/35c3-9532-kernel_tracing_with_ebpf.pdf)  
[linux-tracing-systems](https://jvns.ca/blog/2017/07/05/linux-tracing-systems/)  
