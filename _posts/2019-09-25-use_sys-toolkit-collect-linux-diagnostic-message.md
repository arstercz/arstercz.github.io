---
layout: post
title: "使用 sys-toolkit 收集 Linux 系统的诊断信息"
tags: [linux, toolkit]
comments: false
---

在早期的一系列文章中, 我们提到了很多关于 [percona-toolkit](https://www.percona.com/software/database-tools/percona-toolkit) 工具的使用说明, 其中最常用的 [pt-stalk]({{ site.baseurl }}/top-10-percona-toolkit-tools-%e5%9b%9b), [pt-summary]({{ site.baseurl }}/top-10-percona-toolkit-tools-%e4%b8%89/) 等工具为 MySQL 的故障诊断和系统信息收集带来了很大的帮助. 不过其中的很多工具(比如 `pt-stalk`, `pt-sift` 等) 都和 MySQL 强关联, 实际上并不适用于通用的 Linux 系统. 鉴于此原因, 我们将常用的三个工具(`pt-stalk`, `pt-sift`, `pt-summary`) 修改为通用的系统搜集工具, 并额外增加了更多的特性以便在 Linux 系统出现问题的时候搜集尽可能多的诊断信息方便故障排错. 这三个工具均收录到 [sys-toolkit](https://github.com/arstercz/sys-toolkit) 工具集中. 下面则分别介绍这些工具:

### 工具列表

* [sys-stalk](#sys-stalk-工具)
* [sys-sift](#sys-sift-工具) 
* [sys-summary](#sys-summary-工具)

**备注:** 同类的系统诊断工具还有 [LinuxKI](https://github.com/HewlettPackard/LinuxKI), 其提供内核模块的方式可以收集内核空间的状态信息, 这种方式可能存在一定的风险, 使用之前需要多关注 [issue](https://github.com/HewlettPackard/LinuxKI/issues) 列表中可能会引起的问题.

## sys-stalk 工具

[sys-stalk](https://github.com/arstercz/sys-toolkit#sys-stalk) 主要用于搜集系统的诊断信息. 仅在以下两种条件下搜集信息:

```
1. stalk 模式
2. no-stalk 模式
```

`stalk` 模式需要满足一定的条件才会开始进行各项信息的收集. 该工具提供插件的方式供大家自定义触发条件. `no-stalk` 与 `stalk` 相反, 不需要满足条件, 运行即可开始搜集信息, 该模式仅适用于临时搜集系统的各项信息, 搜集的条目和 stalk 模式相同.

`sys-stalk` 工具与 `sys-summary` 不同, `sys-summary` 更多的是搜集系统的硬件等信息, `sys-stalk` 则主要搜集系统的各项软件信息, 主要包含以下条目:

```
1. CPU 使用情况, 包含 /proc/xxxx 文件信息的搜集;
2. 内存使用情况, 包含 numa, pmap, slab 使用等信息;
3. 磁盘使用情况, 包含磁盘使用, 磁盘 io 等信息;
4. 网络使用情况, 包含 ss, netstat, tcprstat, tcpdump 等信息;
5. 运行进程信息, 包含 top, 进程列表以及忽略 oom 评分的进程;
6. 针对特定进程的信息搜集, 包含 perf, lsof, oprofile, strace, tcprstat, stack, 内存占用等信息.
```

### 风险提示

请仔细阅读该工具的帮助文档, 在使用 `sys-stalk` 的过程中如果存在问题, 请及时在 [sys-toolkit issue](https://github.com/arstercz/sys-toolkit/issues) 中留言反馈. 一些比较明显的风险会在代码中的 RISK 部分进行特别提示.

`sys-stalk` 在整个信息搜集的过程中主要执行以下命令:
```
df
hostname
iostat
gdb          (可选)
mpstat
mount
netstat
numactl      (可选)
oprofile     (可选)
pmap
perf         (可选)
cat proc/{diskstats,stat,vmstat,meminfo,slabinfo,interrupts,cmdline,cpuinfo}
ps
route
ss
strace       (可选)
sysctl
tcpdump      (可选)
tcprstat     (可选)
top
vmstat
sys-checkport (可选)
sys-numa-maps (可选)
sys-httpstat  (可选)
lspci
dmidecode
getconf
```

可选的命令执行时间会较长, `gdb`, `oprofile`, `perf`, `strace`, `tcpdump` 等选项受 `--collect-xxx` 选项控制是否执行, 这些选项选项可能影响正在服务的进程, 管理或运维人员可以按需指定. 这些选项主要针对指定的进程(由 `--program-name`, `--program-pid`, `--program-port` 三个选项控制) , pid 或者相应的进程端口进行信息搜集. 


1. gdb, pmap, strace 对应指定进程的影响较大, 在进程繁忙的情况下可能会拖慢进程的响应时间.

2. oprofile 受 `--collect-oprofile` 控制, 如果指定了 `--program-name` 并且系统安装了 oprofile 工具, 则开始进行 oprofile 的信息收集, 并忽略 strace 的信息收集. 同时修改系统的参数:
```bash
echo 0 > /proc/sys/kernel/watchdog
```

3. 在系统连接数很多(比如十几二十万的连接)的情况下, netstat 的执行时间可能会较长.

4. strace 和 oprofile 互斥, 开启了  oprofile 则会忽略 strace,  strace 可能影响正在服务的进程, 一些包含信号处理机制的进程可能会挂起.

5. tcpdump 仅抓取 3000 个数据包即退出, 不够 3000 个包则在工具退出时退出;

6. tcprstat 为可选项, 如果安装了 [tcprstat](https://github.com/y123456yz/tcprstat) 工具则进行 `--program-port` 端口相关的信息抓取, 
tcprstat 工具可以用来估算指定服务端口的 qps 信息.

7. perf 为可选项, 默认以 99 的频率进行采样, 对系统影响很轻微. 最多运行 60s. 


### 备注说明

sys-stalk 从 [pt-stalk](https://www.percona.com/doc/percona-toolkit/LATEST/pt-stalk.html) 修改而来, 并增加了一些功能:

```
1. 去掉强依赖 MySQL 的信息搜集;
2. 增加 tcpdump, tcprstat, numactl, ss 等命令;
3. 增加 perf 信息搜集;
```
同时修复以下 bug:

[#1557877](https://bugs.launchpad.net/percona-toolkit/+bug/1557877)  
[#1644694](https://bugs.launchpad.net/percona-toolkit/+bug/1644694)  
[#976179](https://bugs.launchpad.net/percona-toolkit/+bug/976179)  

### 如何自定义触发条件

sys-stalk 提供 `--function` 选项, 改选项值可以是指定的函数, 也可以是自定义 bash 脚本, bash 脚本中需要包含 trg_plugin 函数, 参考示例:

```bash
function trg_plugin()
{
   top -d 0.2 -bn 5 | grep 'Tasks:.*total' | \
       tail -n 1 | \
       perl -ane '$sum += $F[1]; END{ $sum = 200 if $sum > 600; print int($sum) . "\n"}'
}
```
该函数用来输出当前系统的进程数. 在写自定义函数的时候需要注意阈值问题, 在系统繁忙的时候该函数应该尽可能返回正常的值, 避免 sys-stalk 的执行加大对系统的伤害. 比如我们需要
在系统负载 20 的时候开始搜集信息, 在系统负载 200 的时候就应该忽略信息搜集. 上述的 `$sum = 200 if $sum > 600` 即是此类问题的保护.

### 使用说明

sys-stalk 选项较多, 主要包含以下选项:

```
  --check-url                      https://blog.arstercz.com
  --collect                        TRUE
  --collect-gdb                    FALSE
  --collect-oprofile               FALSE
  --collect-perf                   FALSE
  --collect-jstack                 FALSE
  --collect-pmap                   FALSE
  --collect-strace                 FALSE
  --collect-tcpdump                FALSE
  --config                         (No value)
  --cycles                         3
  --daemonize                      FALSE
  --dest                           /var/lib/sys-stalk
  --disk-bytes-free                104857600
  --disk-pct-free                  5
  --function                       cpu_usage
  --help                           TRUE
  --interval                       1
  --iterations                     (No value)
  --log                            /var/log/sys-stalk.log
  --notify-by-email                (No value)
  --pid                            /var/run/sys-stalk.pid
  --plugin                         (No value)
  --prefix                         (No value)
  --program-name                   (No value)
  --program-pid                    (No value)
  --program-port                   (No value)
  --retention-time                 30
  --run-time                       30
  --sleep                          300
  --sleep-collect                  1
  --stalk                          TRUE
  --threshold                      25
  --variable                       (No value)
  --verbose                        2
  --version                        FALSE
```


搜集的信息都存储在 `--dest` 选项中, 默认为 `/var/lib/sys-stalk` 目录, `--prefix` 为 目录中所有文件名的前缀, 默认为时间戳. `--threshold` 为阈值, 插件函数获取的值会和该选项进行比较, 超过阈值则开始搜集信息; `--variable` 默认为 `--program-name` 的值. `--cycles` 默认为 3, 表示触发条目连续发生三次才开始进行搜集操作. `--program-name`, `--program-pid` 和 `--program-port` 三个选项互相配合使用, sys-stalk 使用 `program-name` 获取进程的 pid 信息, 如果指定了 `program-pid` 选项则覆盖通过 `program-name` 得到的 pid, 并通过 pid 获取进程运行的端口, 如果指定了 `program-port` 则覆盖通过 pid 获取到的端口号. 

### 通用示例

实际使用中, sys-stalk 的选项较多, 可以通过 `--config` 选项指定需要的配置文件, 比如 [stalk.conf](etc/stalk.conf):
```
sleep=40
function=/etc/sys-toolkit/plugin/trg_cpu_usage
threshold=300
collect-gdb
collect-tcpdump
collect-pmap
collect-strace
collect-perf
cycles=3
dest=/data/sys-stalk
program-port=3316
```
sys-stalk 默认以循环的方式运行, 可以通过 Ctrl + c 中断运行. 如下所示, 使用 stalk 模式运行, 匹配 3 次后才开始进行信息搜集, 
```bash
# ./bin/sys-stalk --config etc/stalk.conf 
# sys-stalk --config /etc/stalk.conf --no-stalk                                 
2019_09_25_11_28_12 Starting /usr/local/bin/sys-stalk --function=/etc/sys-toolkit/plugin/trg_cpu_usage --variable= --threshold=300 --cycles=0 --interval=1 --iterations= --run-time=30 --sleep=40 --dest=/data/wt-stalk --prefix= --notify-by-email= --log=/var/log/sys-stalk.log --pid=/var/run/sys-stalk.pid --plugin=
2019_09_25_11_28_12 Not stalking; collect triggered immediately
2019_09_25_11_28_12 Collect 1 triggered
2019_09_25_11_28_12 Collect 1 PID 95713
2019_09_25_11_28_12 Collect 1 done
2019_09_25_11_28_12 Sleeping 40 seconds after collect

^C2019_09_25_11_28_36 Caught signal, exiting
2019_09_25_11_28_36 Waiting up to 90 seconds for subprocesses to finish...
2019_09_25_11_28_42 Exiting because OKTORUN is false
2019_09_25_11_28_42 /usr/local/bin/sys-stalk exit status 1
```
收到  Ctrl + c 信号后, 工具会等待未完成的子进程结束. `--dest` 指定的目录中最后包含以下文件:
```
# ls /data/sys-stalk/
2019_09_25_11_28_12-audit       2019_09_25_11_28_12-ifconfig        2019_09_25_11_28_12-numainfo    2019_09_25_11_28_12-ss
2019_09_25_11_28_12-cmdline     2019_09_25_11_28_12-interrupts      2019_09_25_11_28_12-numa-maps   2019_09_25_11_28_12-sysctl
2019_09_25_11_28_12-cpuinfo     2019_09_25_11_28_12-iostat          2019_09_25_11_28_12-output      2019_09_25_11_28_12-tcpdump
2019_09_25_11_28_12-devices     2019_09_25_11_28_12-iostat-overall  2019_09_25_11_28_12-perf        2019_09_25_11_28_12-top
2019_09_25_11_28_12-df          2019_09_25_11_28_12-kallsyms        2019_09_25_11_28_12-procstat    2019_09_25_11_28_12-trigger
2019_09_25_11_28_12-disk-space  2019_09_25_11_28_12-meminfo         2019_09_25_11_28_12-procvmstat  2019_09_25_11_28_12-uname
2019_09_25_11_28_12-diskstats   2019_09_25_11_28_12-mount           2019_09_25_11_28_12-ps          2019_09_25_11_28_12-vmstat
2019_09_25_11_28_12-dmesg       2019_09_25_11_28_12-mpstat          2019_09_25_11_28_12-ps-eo       2019_09_25_11_28_12-vmstat-overall
2019_09_25_11_28_12-dmidecode   2019_09_25_11_28_12-mpstat-overall  2019_09_25_11_28_12-release
2019_09_25_11_28_12-fstab       2019_09_25_11_28_12-netstat         2019_09_25_11_28_12-rpmlist
2019_09_25_11_28_12-getconf     2019_09_25_11_28_12-netstat_s       2019_09_25_11_28_12-slabinfo
```

另外也可以通过 `no-stalk` 模式运行工具, 该模式忽略条件的判断, 直接进行信息搜集:

```bash
sys-stalk --config etc/stalk.conf --no-stalk
```

### 收集 java 进程示例

`sys-stalk` 支持搜集 java 进程的 jstack 信息, 如果需要搜集 [jvm_tools](https://github.com/aragozin/jvm-tools/) 等信息, 需要在线上的主机中部署 `sjk.jar` 包. 仅收集 jstack 信息可以通过以下配置实现:

```
sleep=40
function=/etc/sys-toolkit/plugins/cpu_usage
threshold=300
collect-tcpdump
collect-jstack
cycles=3
dest=/data/sys-stalk
program-name=kafka.logs.dir
```
如果启用 `collect-jstack` 选项, `program-name` 选项可以为全命令行中的标识信息, 比如上述的 `kafka.logs.dir` 可以标识系统唯一的 kafka 进程, 如果系统运行多个相同的进程, 
可以设置能够唯一标识进程的信息, 也可以增加 `program-pid` 单独指定进程的 pid.
以 `no-stalk` 模式运行:
```
# ./sys-stalk --config stalk.conf --no-stalk 
```
同上述一样, `sys-stalk` 会等待未完成的子进程结束, 如下所示包含对应的 jstack 文件:
```
2019_09_24_15_28_12-audit       2019_09_24_15_28_12-ifconfig        2019_09_24_15_28_12-netstat_s   2019_09_24_15_28_12-slabinfo
2019_09_24_15_28_12-cmdline     2019_09_24_15_28_12-interrupts      2019_09_24_15_28_12-numainfo    2019_09_24_15_28_12-ss
2019_09_24_15_28_12-cpuinfo     2019_09_24_15_28_12-iostat          2019_09_24_15_28_12-numa-maps   2019_09_24_15_28_12-sysctl
2019_09_24_15_28_12-devices     2019_09_24_15_28_12-iostat-overall  2019_09_24_15_28_12-output      2019_09_24_15_28_12-tcpdump
2019_09_24_15_28_12-df          2019_09_24_15_28_12-jstack          2019_09_24_15_28_12-perf        2019_09_24_15_28_12-top
2019_09_24_15_28_12-disk-space  2019_09_24_15_28_12-kallsyms        2019_09_24_15_28_12-procstat    2019_09_24_15_28_12-trigger
2019_09_24_15_28_12-diskstats   2019_09_24_15_28_12-meminfo         2019_09_24_15_28_12-procvmstat  2019_09_24_15_28_12-uname
2019_09_24_15_28_12-dmesg       2019_09_24_15_28_12-mount           2019_09_24_15_28_12-ps          2019_09_24_15_28_12-vmstat
2019_09_24_15_28_12-dmidecode   2019_09_24_15_28_12-mpstat          2019_09_24_15_28_12-ps-eo       2019_09_24_15_28_12-vmstat-overall
2019_09_24_15_28_12-fstab       2019_09_24_15_28_12-mpstat-overall  2019_09_24_15_28_12-release
2019_09_24_15_28_12-getconf     2019_09_24_15_28_12-netstat         2019_09_24_15_28_12-rpmlist
```

[Back_to_TOC](#工具列表)


## sys-sift 工具

[sys-sift](https://github.com/arstercz/sys-toolkit#sys-sift) 主要通过读取 `sys-stalk` 产生的文件来生成系统的运行报告概览. 默认情况下读取 `/var/lib/sys-stalk` 目录中的文件. 生成的报告主要包含以下信息:

```
1. 磁盘 io 信息汇总;
2. wmstat 信息汇总;
3. 堆栈信息汇总;
4. oprofile 信息汇总(可选项);
5. sys-httpstat 结果展示;
6. netstat 网络连接信息汇总;
7. tcprstat 结果展示(可选项);
8. perf 结果展示以及 flamegraph 火焰图生成(可选项);
9. tcpdump 结果展示;
```

### 风险提示

请仔细阅读该工具的帮助文档, 在使用 sys-sift 的过程中如果存在问题, 请及时在 [sys-toolkit issue](https://github.com/arstercz/sys-toolkit/issues) 中留言反馈. 一些比较明显的风险会在代码中的 `RISK` 部分进行特别提示.

`sys-sift` 主要读取并解析 sys-stalk 产生的文件, 通过工具中内置的功能来生成报告, 不过主要也执行了以下命令:

```
tcpdump
perf
flamegraph.pl          (可选)
stackcollapse-perf.pl  (可选)
netstat
vmstat
```
其中

1. tcpdump 以 `-i any` 的方式解析 pcap 文件;

2. netstat 的解析中, 如果连接很多, 解析的实际可能过长;

3. `flamegraph.pl` 和 `stackcollapse-perf.pl` 为可选项, 主要生成 perf 文件对应的火焰图, 更多见: [FlameGraph](https://github.com/brendangregg/FlameGraph)


### 备注说明

`sys-sift` 从 [pt-sift](https://www.percona.com/doc/percona-toolkit/LATEST/pt-sift.html) 修改而来, 并增加了一些功能:
```
1. 去掉汇总 MySQL 的信息搜集;
2. 增加 tcpdump, tcprstat, perf, disk io, httpstat, netstat 等结果的解析;
3. 去掉 pt-pmap, pt-diskstats 等工具的依赖;
```

### 使用说明

`sys-sift` 使用很简单, 以如下方式运行:
```bash
Usage: sys-sift FILE|PREFIX|DIRECTORY

Options and values after processing arguments:

  --help                           TRUE
  --version                        FALSE
```

如下所示, 读取 sys-stalk 产生的文件, sys-sift 以交互模式生成报告:
```bash
# sys-sift /data/sys-stalk/

  2019_09_24_11_34_41  2019_09_24_11_41_08

Select a timestamp from the list [2019_09_24_11_41_08] 
```
因为一共执行了两次 sys-stalk 搜集, 分别对应各自的时间戳, sys-sift 默认解析最新的时间戳文件. 也可以手动将以前的时间戳附加到交互模式的末尾, 如下所示对 sys-stalk 在 `2019_09_24_11_41_08` 时间点生成的文件进行汇总:
```bash
# ./sys-sift /data/sys-stalk/

  2019_09_24_11_34_41  2019_09_24_11_41_08

Select a timestamp from the list [2019_09_24_11_41_08] 
======== dbinfo8 at 2019_09_24_11_41_08 DEFAULT (2 of 2) ========
--diskstats--
TS: 2019_09_24T11:41:13
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda     94.00      0.00      0.00     94.00         8.00      0.00      6104.00       3.00 ms      26.00 ms       0.00 ms      26.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2     94.00      0.00      0.00     94.00         8.00      0.00      6104.00       3.00 ms      26.00 ms       0.00 ms      26.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:14
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:15
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda     15.00      0.00      0.00     15.00         0.00      0.00       147.00       2.00 ms       2.00 ms       0.00 ms       2.00 ms
    sda1     11.00      0.00      0.00     11.00         0.00      0.00       123.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      3.00      0.00      0.00      3.00         0.00      0.00        24.00       2.00 ms       2.00 ms       0.00 ms       2.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:16
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:17
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda    114.00      0.00      0.00    114.00        32.00      0.00       973.00       3.00 ms       4.00 ms       0.00 ms       4.00 ms
    sda1     89.00      0.00      0.00     89.00         0.00      0.00       541.00       1.00 ms       2.00 ms       0.00 ms       2.00 ms
    sda2     22.00      0.00      0.00     22.00        32.00      0.00       432.00       1.00 ms       1.00 ms       0.00 ms       1.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:18
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      4.00      0.00      0.00      4.00         0.00      0.00        32.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      4.00      0.00      0.00      4.00         0.00      0.00        32.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:19
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:20
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda1      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda2      3.00      0.00      0.00      3.00         0.00      0.00        24.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
    sda3      0.00      0.00      0.00      0.00         0.00      0.00         0.00       0.00 ms       0.00 ms       0.00 ms       0.00 ms
TS: 2019_09_24T11:41:21
              iops        rs    rs_mer        ws       ws_mer    rs_sec       ws_sec       e_iot        e_iot_w          r_t          w_t
     sda      3.00      0.00      0.00      3.00         0.00      0.00        24.00       1.00 ms       1.00 ms       0.00 ms       1.00 ms
--vmstat--
 r b swpd     free   buff   cache si so bi  bo   in   cs us sy id wa st
 0 0    0 16641684 425452 5527024  0  0 51 137 2363 1271  0  1 99  0  0
wa 0% . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--stack traces--
    128 epoll_wait(libc.so.6),io_poll_wait(threadpool_unix.cc:292),listener(threadpool_unix.cc:292),get_event(threadpool_unix.cc:1166),worker_main(threadpool_unix.cc:1166),pfs_spawn_thread(pfs.cc:1861),start_thread(libpthread.so.0),clone(libc.so.6)
     14 pthread_cond_wait,os_cond_wait(os0sync.cc:196),os_event_wait_low(os0sync.cc:196),os_aio_simulated_handle(os0file.cc:5969),fil_aio_wait(fil0fil.cc:5923),io_handler_thread(srv0start.cc:518),start_thread(libpthread.so.0),clone(libc.so.6)
      1 sigwait(libpthread.so.0),signal_hand(mysqld.cc:3492),pfs_spawn_thread(pfs.cc:1861),start_thread(libpthread.so.0),clone(libc.so.6)
      1 sigwaitinfo(libc.so.6),timer_notify_thread(posix_timers.c:78),start_thread(libpthread.so.0),clone(libc.so.6)
      1 select(libc.so.6),os_thread_sleep(os0thread.cc:304),srv_master_sleep(srv0srv.cc:2967),srv_master_thread(srv0srv.cc:2967),start_thread(libpthread.so.0),clone(libc.so.6)
      1 select(libc.so.6),os_thread_sleep(os0thread.cc:304),page_cleaner_sleep_if_needed(buf0flu.cc:2590),buf_flush_page_cleaner_thread(buf0flu.cc:2590),start_thread(libpthread.so.0),clone(libc.so.6)
      1 select(libc.so.6),os_thread_sleep(os0thread.cc:304),page_cleaner_sleep_if_needed(buf0flu.cc:2590),buf_flush_lru_manager_thread(buf0flu.cc:2590),start_thread(libpthread.so.0),clone(libc.so.6)
      1 pthread_cond_wait,os_cond_wait(os0sync.cc:196),os_event_wait_low(os0sync.cc:196),srv_purge_coordinator_suspend(srv0srv.cc:3333),srv_purge_coordinator_thread(srv0srv.cc:3333),start_thread(libpthread.so.0),clone(libc.so.6)
--oprofile--
    No opreport file exists
--httpstat--
HTTP/1.1 302 Found
Server: nginx
Date: Tue, 12 Feb 2019 03:41:11 GMT
Content-Type: text/html; charset=ISO-8859-1
Content-Length: 69
Location: https://blog.arstercz.com/
Connection: keep-alive
Content-Language: en-US

website ip address: 109.244.11.48:443

  DNS Lookup   TCP Connection   SSL Handshake   Server Processing   Content Transfer
[       4ms  |         8ms    |       61ms    |          9ms      |          0ms     ]
             |                |               |                   |                  |
    namelookup:4ms            |               |                   |                  |
                        connect:12ms          |                   |                  |
                                    pretransfer:73ms              |                  |
                                                      starttransfer:82ms             |
                                                                                 total:82ms   

--netstat--
  Connections from remote IP address
    10.12.17.21         2
    10.12.17.26         2
    109.244.11.48       1
  Connections to local IP addresses
    10.12.17.28         5
  Connections to top 15 local ports
    18222               1
    22                  2
    3336                1
    62622               1
  States of connections
    ESTABLISHED         4
    LISTEN             20
    TIME_WAIT           1

--netstat_s fileds description--
     ip => ip packages received
    tac => tcp active connections opening
    tpc => tcp passive connections opening
    tfc => tcp failed connection attempts
    tsr => tcp segment retransmited
   tsft => tcp sockets finished time wait in fast timer
   tpdq => tcp packets directly queued to recvmsg prequeue
    tda => tcp delayed acks send
    tqa => tcp quick ack mode times
    tca => tcp connections aborted due to timeout
TS: 2019_09_24 11:41:14
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:15
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         4         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:16
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         6         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:17
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         4         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:18
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:19
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:20
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:21
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
TS: 2019_09_24 11:41:22
        ip       tac       tpc       tfc       tsr      tsft      tpdq       tqa       tda       tca
         0         0         0         0         0         0         0         0         0         0
--tcprstat--
tcprstat with port: 3316
timestamp       count   max     min     avg     med     stddev  tc      95_max  95_avg  95_std  99_max  99_avg  99_std
1549942873      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942874      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942875      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942876      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942877      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942878      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942879      0       0       0       0       0       0       0       0       0       0       0       0       0
1549942880      0       0       0       0       0       0       0       0       0       0       0       0       0
```

`sys-sift` 在交互模式中支持以下选项:
```
   You can control this program with key presses.
                  ---  COMMANDS  ---
      1  Default action: summarize files
      0  Minimal action: list files
      *  View all the files in less
      d  Invoke 'diskstats' on the disk performance data
      n  Summarize the 'netstat -antp' status data
      s  Poor man's profile on the stacktrace data
      t  read the tcpdump data
      p  Report the perf data
                  --- NAVIGATION ---
      j  Select the next timestamp
      k  Select the previous timestamp
      q  Quit the program
Press any key to continue
```
比如 `p` 可以用来查看 perf 报告:

![perf_report]({{ site.baseurl }}/images/articles/201909/sys-sift_perf.png)

生成报告的时候也会生成对应的火焰图(`/data/sys-stalk/perf-svg-2019_09_24_11_41_08.svg`)

[Back_to_TOC](#工具列表)

## sys-summary 工具

[sys-summary](https://github.com/arstercz/sys-toolkit#sys-summary) 用于汇总主机的系统信息, 可以直观的将当前主机的各项信息罗列出来, 这些信息包括以下内容:

```
1. 系统通用信息, 包含系统运行时间, 时区, 主机型号, 序列号, 系统类型, 内核版本, 硬件架构等信息;
2. 处理器信息, 包含物理 CPU, 核数, 是否超线程等信息;
3. 内存信息, 包含内存使用情况, swap, 赃页刷新策略, 内存条位置等信息;
4. 挂载的文件系统信息;
5. 磁盘信息, 包含调度算法, 队列大小, 分区使用情况等信息;
6. fio 信息(可选项, 如果该主机配置了 PCIE ssd 等设备, 则解析设备的型号, 使用参数等信息);
7. 内核 Inode 使用状态信息;
8. LVM 信息(可选项);
9. ZPOOL/ZFS 信息(可选项, 主要针对运行 zfsonlinux 的主机系统);
10. RAID 信息, 包含 RAID 控制器的型号, 缓存大小, BBU 充放电状态;
11. 虚拟设备信息, 包含 RAID 级别, RAID 缓存策略等信息;
12. 物理磁盘信息, 包含厂商及型号, 磁盘大小, 类别以及 Media error, Other error 等介质错误信息;
13. 网络信息, 包含网卡型号, TCP 连接状态信息, 网卡数据报文汇总等信息;
14. 进程信息, 前 15 个 CPU 使用最高的进程列表以及 OOM 级别为 -17(不参与 oom 评分)的进程列表;
15. vmstat 信息;
16. 判断系统是否开启 transparent_hugepage;
```

### 风险提示

请仔细阅读该工具的帮助文档, 在使用 sys-summary 的过程中如果存在问题, 请及时在 [sys-toolkit issue](https://github.com/arstercz/sys-toolkit/issues) 中留言反馈. 一些比较明显的风险会在代码中的 `RISK` 部分进行特别提示.

sys-summary 在整个信息搜集的过程中主要执行以下命令:
```
file
nm
objdump
sysctl
dmidecode
dmesg
lspci
getenforce
lvs
vgs
zpool
zfs
top
MegaCli
vmstat
ip
netstat
lsb_release
getconf
fio-status
```

1. lvs, vgs, zpool, zfs 为可选项, 系统如果存在相关的设置则进行对应的信息收集;

2. top 命令用来收集进程信息, 不过 top 计算需要至少两次采样数据才能进行计算, 官方的 `pt-summary` 还没有修复该问题, `sys-summary` 中取三次数据, 以最后一次的结果信息为准, 详见 [top report bug](https://bugzilla.redhat.com/show_bug.cgi?id=174619);

3. MegaCli 或 MegaCli64 工具需要存在于标准的 PATH 路径中, 如果以 yum/rpm 等方式安装, 则包含 `/opt/MegaRAID/MegaCli/` 路径, MegaCli 收集的信息较多, 在搜集磁盘信息的时候为了获取一致的状态, MegaCli 可能会阻塞磁盘的正常读写, 这种情况下可能会引起有些应用的超时, 尤其是以机械盘提供服务数据库主机, DB 的响应时间可能远超预期, 应该避免在高峰期执行该命令. 另外如果是固态盘, 则 MegaCli 影响很轻微, 可以在需要的时候直接运行 sys-summary 工具. 如果系统没有 MegaCli 命令则忽略 RAID 和物理磁盘相关信息的收集;

4. netstat 命令收集了所有的网络连接信息, 在连接数很大(比如10w+连接)的情况下, 该命令可能执行时间过长;

5. fio-status 则仅在 fio 设备(pcie, nvme 等固态硬盘)存在的情况下运行, 目前线上存在 fio 设备的仅有部分数据库主机;


### 备注说明

sys-summary 最初从 [pt-summary](https://www.percona.com/doc/percona-toolkit/LATEST/pt-summary.html) 修改而来, 在修改的过程中也修复了很多小问题, 系统或运维人员在线上使用的时候最好使用 sys-summary 工具, 有问题的时候也请及时反馈. sys-summary 主要包含以下改动:
```
1. 修复 file 命令查看软链接文件的错误问题;
2. 忽略执行 /lib/libc.so.6 命令时加载 snoopy 的错误提示;
3. 修复 fio-status 命令解析错误问题;
4. 修复分区信息在 sort 和 join 时的错误不匹配信息;
5. 修复进程列表解析错误问题;
6. 内存使用解析增加 Centos 7 版本支持;
7. 网卡数据信息增加 dropped 信息;
8. MegaCli 命令查找同时支持 MegaCli64 和 MegaCli 两个版本; 
8. 修复 MegaCli 重复解析物理磁盘问题;
9. 增加 zpool/zfs 的汇总信息;
10. 修复 top 命令输出异常问题;
```

### 使用说明

`sys-summary` 主要包含以下选项:
```
Options and values after processing arguments:

  --config                         (No value)
  --help                           TRUE
  --read-samples                   (No value)
  --save-samples                   (No value)
  --sleep                          5
  --summarize-mounts               TRUE
  --summarize-network              TRUE
  --summarize-processes            TRUE
  --version                        FALSE
```

可以将工具执行过程中生成的中间文件通过 `--save-samples` 选项存储起来供以后回归分析. sleep 选项为 vmstat 运行的时间, 一般保持默认即可. mounts, network, processes 默认情况想都会进行汇总. 可以直接执行 sys-summary 命令查看主机的汇总信息, 如下所示为线上一台配有 PCIE 固态盘的主机:
```bash
# Percona Toolkit System Summary Report ######################
        Date | 2019-09-23 11:39:15 UTC (local TZ: CST +0800)
    Hostname | ctdb
      Uptime | 76 days,  4:19,  1 user,  load average: 0.07, 0.10, 0.13
      System | Dell Inc.; PowerEdge R720; vNot Specified (Rack Mount Chassis)
 Service Tag | 9LQ5JY1
    Platform | Linux
     Release | CentOS Linux release 7.5.1804 (Core) 
      Kernel | 3.10.0-862.14.4.el7.x86_64
Architecture | CPU = 64-bit, OS = 64-bit
   Threading | NPTL 2.17
     SELinux | Disabled
 Virtualized | No virtualization detected
# Processor ##################################################
  Processors | physical = 2, cores = 8, virtual = 16, hyperthreading = yes
      Speeds | 1x1199.835, 1x1268.719, 1x1285.034, 1x1287.652, 1x1291.278, 1x1296.716, 1x1314.239, 1x1330.554, 1x1370.837, 1x1670.544, 1x1709.619, 1x1754.937, 1x1779.107, 1x2251.629, 1x2504.003, 1x2580.340
      Models | 16xIntel(R) Xeon(R) CPU E5-2643 0 @ 3.30GHz
      Caches | 16x10240 KB
# Memory #####################################################
       Total | 188.7G
        Free | 161.2G
        Used | physical = 2.7G, swap allocated = 0.0, swap used = 0.0, virtual = 2.7G
      Shared | 4.0G
Buffer/Cache | 24.8G
   Available | 181.1G
       Dirty | 32 kB
     UsedRSS | 520.6M
  Swappiness | 60
 DirtyPolicy | 20, 10
 DirtyStatus | 0, 0
  Locator   Size     Speed             Form Factor   Type          Type Detail
  ========= ======== ================= ============= ============= ===========
  DIMM_A1   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A2   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A3   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A4   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A5   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A6   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B1   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B2   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B3   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B4   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B5   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_B6   16384 MB 1600 MHz          DIMM          DDR3          Synchronous Registered (Buffered)
  DIMM_A10  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_A11  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_A12  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_A7   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_A8   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_A9   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B10  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B11  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B12  {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B7   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B8   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
  DIMM_B9   {EMPTY}  Unknown           DIMM          DDR3          Synchronous
# Fusion-io Card #############################################
  fio Driver | 3.2.15 build 1699
Single Controller Adapter | Fusion-io ioScale 845GB, Product Number:F11-001-845G-CS-0001, SN:1241D9421, FIO SN:1241D9421
            fct0 | Attached
                 | ioDrive2 Adapter Controller, Product Number:F11-001-845G-CS-0001, SN:1241D9421
                 | Firmware v7.1.17, rev 116786 Public
                 | Internal temperature: 44.30 degC, max 53.15 degC
                 | Reserve space status: Healthy; Reserves: 100.00%, warn at 10.00%
                 | Rated PBW: 6.00 PB, 81.83% remaining
Single Controller Adapter | Fusion-io ioScale 845GB, Product Number:F11-001-845G-CS-0001, SN:1241D9268, FIO SN:1241D9268
            fct1 | Attached
                 | ioDrive2 Adapter Controller, Product Number:F11-001-845G-CS-0001, SN:1241D9268
                 | Firmware v7.1.17, rev 116786 Public
                 | Internal temperature: 49.71 degC, max 60.54 degC
                 | Reserve space status: Healthy; Reserves: 100.00%, warn at 10.00%
                 | Rated PBW: 6.00 PB, 75.70% remaining
# Mounted Filesystems ########################################
  Filesystem   Size Used Type     Opts                                                 Mountpoint
  datapool/db  760G   1% zfs      rw,xattr,noacl                                       /data
  /dev/sda1     10G  66% xfs      rw,relatime,attr2,inode64,noquota                    /
  /dev/sdb     549G  14% xfs      rw,relatime,attr2,inode64,noquota                    /dataex
  devtmpfs      95G   0% devtmpfs rw,nosuid,size=98925508k,nr_inodes=24731377,mode=755 /dev
  tmpfs         19G   0% tmpfs    rw,nosuid,nodev                                      /run/user/0
  tmpfs         19G   0% tmpfs    rw,nosuid,nodev,mode=755                             /run/user/0
  tmpfs         19G   0% tmpfs    rw,nosuid,nodev,relatime,size=19787152k,mode=700     /run/user/0
  tmpfs         19G   0% tmpfs    ro,nosuid,nodev,noexec,mode=755                      /run/user/0
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev                                      /dev/shm
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev,mode=755                             /dev/shm
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev,relatime,size=19787152k,mode=700     /dev/shm
  tmpfs         95G   0% tmpfs    ro,nosuid,nodev,noexec,mode=755                      /dev/shm
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev                                      /sys/fs/cgroup
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev,mode=755                             /sys/fs/cgroup
  tmpfs         95G   0% tmpfs    rw,nosuid,nodev,relatime,size=19787152k,mode=700     /sys/fs/cgroup
  tmpfs         95G   0% tmpfs    ro,nosuid,nodev,noexec,mode=755                      /sys/fs/cgroup
  tmpfs         95G   5% tmpfs    rw,nosuid,nodev                                      /run
  tmpfs         95G   5% tmpfs    rw,nosuid,nodev,mode=755                             /run
  tmpfs         95G   5% tmpfs    rw,nosuid,nodev,relatime,size=19787152k,mode=700     /run
  tmpfs         95G   5% tmpfs    ro,nosuid,nodev,noexec,mode=755                      /run
# Disk Schedulers And Queue Size #############################
        fioa | 128
        fiob | 128
         sda | [deadline] 128
         sdb | [deadline] 128
# Disk Partioning ############################################
Device       Type      Start        End               Size
============ ==== ========== ========== ==================
/dev/fioa    Disk                             844999999488
/dev/fioa1   Part        256  206298827       844998946816
/dev/fiob    Disk                             844999999488
/dev/fiob1   Part        256  206298827       844998946816
/dev/sda     Disk                              10737418240
/dev/sda1    Part       2048   20971519        10736369152
/dev/sdb     Disk                             588813172736
# Kernel Inode State #########################################
dentry-state | 315045   299138  45      0       0       0
     file-nr | 832      0       65535
    inode-nr | 112328   11598
# LVM Volumes ################################################
Unable to collect information
# LVM Volume Groups ##########################################
Unable to collect information
# ZPOOL status ###############################################
  NAME       SIZE  ALLOC   FREE  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
  datapool   784G   632K   784G         -     0%     0%  1.00x  ONLINE  -
  
    pool: datapool
   state: ONLINE
    scan: none requested
  config:
  
        NAME        STATE     READ WRITE CKSUM
        datapool    ONLINE       0     0     0
          mirror-0  ONLINE       0     0     0
            fioa1   ONLINE       0     0     0
            fiob1   ONLINE       0     0     0
  
# ZFS filesystem #############################################
  NAME          USED  AVAIL  REFER  MOUNTPOINT
  datapool      572K   759G    96K  /datapool
  datapool/db   200K   759G   200K  /data
# RAID Controller ############################################
  Controller | LSI Logic MegaRAID SAS
       Model | PERC H710P Mini, PCIE interface, 8 ports
       Cache | 1024MB Memory, BBU Present
         BBU | 98% Charged, Charge status: Complete Temperature 30C, isSOHGood=Yes

  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache
  ========== ========= ========== ===== ======= ====== ======= =========
  0root      10240MB   1 (1-0-0)      2     1-1   64kB Optimal WB, RA
  1export    561536MB  1 (1-0-0)      2     1-1   64kB Optimal WB, RA

  PhysiclDev Type State   Errors Vendor  Model        Size
  ========== ==== ======= ====== ======= ============ ===========
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST600MM0006  572325MB
  Hard Disk  SAS  Online   0/0/0 SEAGATE ST600MM0006  572325MB
# Network Config #############################################
  Controller | Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
  Controller | Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
  Controller | Intel Corporation I350 Gigabit Network Connection (rev 01)
  Controller | Intel Corporation I350 Gigabit Network Connection (rev 01)
 FIN Timeout | 60
  Port Range | 65000
# Interface Statistics #######################################
  interface          rx_bytes   rx_packets  rx_errors rx_dropped      tx_bytes   tx_packets  tx_errors tx_dropped
  ============  ============= ============ ========== ========== ============= ============ ========== ==========
  lo                 30000000       500000          0          0      30000000       500000          0          0
  eno3                      0            0          0          0             0            0          0          0
  eno4                      0            0          0          0             0            0          0          0
  eno1           175000000000     60000000          0          0  175000000000     60000000          0          0
  eno2              350000000      6000000          0          0             0            0          0          0
  bond0          175000000000     70000000          0          0  175000000000     60000000          0          0
  bond0.2@bond0  175000000000     60000000          0          0  175000000000     50000000          0          0
# Network Devices ############################################
  Device    Speed     Duplex
  ========= ========= =========
  bond0      10000Mb/s  Full      
  eno1       10000Mb/s  Full      
  eno2       10000Mb/s  Full      
  eno3       Unknown!   Unknown!  
  eno4       Unknown!   Unknown!  
# Network Connections ########################################
  Connections from remote IP addresses
    10.0.21.5          20
    10.0.21.7           2
    10.0.21.17          1
  Connections to local IP addresses
    10.0.21.5          20
  Connections to top 10 local ports
    10050              20
    22                  1
    40118               1
    56954               1
  States of connections
    ESTABLISHED         3
    LISTEN             10
    TIME_WAIT          20
# Top Processes ##############################################
  PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
24770 root      20   0  150440   2124   1412 R  12.5  0.0   0:00.03 top
21748 root      20   0       0      0      0 S   6.2  0.0   0:01.66 kworker/u6+
    1 root      20   0   52592   4904   2596 S   0.0  0.0  34:13.29 systemd
    2 root      20   0       0      0      0 S   0.0  0.0   7:36.93 kthreadd
    3 root      20   0       0      0      0 S   0.0  0.0   7:46.78 ksoftirqd/0
    5 root       0 -20       0      0      0 S   0.0  0.0   0:00.00 kworker/0:+
    8 root      rt   0       0      0      0 S   0.0  0.0   0:09.19 migration/0
    9 root      20   0       0      0      0 S   0.0  0.0   0:00.00 rcu_bh
   10 root      20   0       0      0      0 S   0.0  0.0 167:50.59 rcu_sched
   11 root       0 -20       0      0      0 S   0.0  0.0   0:00.00 lru-add-dr+
   12 root      rt   0       0      0      0 S   0.0  0.0   0:34.31 watchdog/0
   13 root      rt   0       0      0      0 S   0.0  0.0   0:39.11 watchdog/1
   14 root      rt   0       0      0      0 S   0.0  0.0   0:09.83 migration/1
   15 root      20   0       0      0      0 S   0.0  0.0   0:37.51 ksoftirqd/1
# Notable Processes ##########################################
  PID    OOM    COMMAND
 2040    -17    sshd
  528    -17    systemd-udevd
# Simplified and fuzzy rounded vmstat (wait please) ##########
  procs  ---swap-- -----io---- ---system---- --------cpu--------
   r  b    si   so    bi    bo     ir     cs  us  sy  il  wa  st
   1  0     0    0    50     9      0      0   0   0 100   0   0
   1  0     0    0     0     0   8000   8000   2   4  94   0   0
   0  0     0    0     0     0   2500   3500   0   0 100   0   0
   0  0     0    0     0    60   3000   4000   0   0  99   0   0
   0  0     0    0     0     0   2500   3500   0   0 100   0   0
# Memory mamagement ##########################################
Transparent huge pages are enabled.
# The End ####################################################
```

[Back_to_TOC](#工具列表)
